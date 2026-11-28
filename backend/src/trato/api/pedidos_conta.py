"""Termos 20.6: conta suspensa ou encerrada não fica com pedido futuro. O sistema cancela sem
custo de cancelamento (valor retido volta inteiro), pausa as séries recorrentes e avisa a outra
parte. Serviço em andamento não é cancelado: a equipe confere (seção 8). O que já é devido ao
profissional segue as regras de sempre, com a trava por fraude.

Cada pedido tem a própria transação e trava; repetir não faz nada."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime

from trato.api.ausencia_base import do_pedido as ausencia_do_pedido
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto
from trato.api.exclusividades import encerrar_exclusividade_do_pedido, encerrar_na_contratacao
from trato.api.recorrencias import ST_ATIVA, ST_PAUSADA, V_AGENDADA, V_CANCELADA
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Estado, Papel, Pedido
from trato.persistencia.ausencias import PENDENTES

log = logging.getLogger("trato.medidas")
TIPOS_QUE_CANCELAM = ("suspensao", "encerramento")
FUTUROS = (
    Estado.ABERTO,
    Estado.RESERVADO,
    Estado.ORCAMENTO_ACEITO,
    Estado.AGUARDANDO_CONFIRMACAO,
    Estado.PAGO_E_RETIDO,
    Estado.AGENDADO,
)
_SISTEMA = Ator(Papel.SISTEMA, "medida_conta")
_PAGINA = 200
_AVISO = (
    "O pedido foi cancelado pelo Trato porque a conta da outra parte foi suspensa ou "
    "encerrada. Não há custo de cancelamento, e o que foi pago por este pedido volta por "
    "inteiro ao cliente (Termos 20.6)."
)
_AVISO_SERIE = (
    "O serviço recorrente foi pausado porque a conta da outra parte foi suspensa ou "
    "encerrada (Termos 20.6). Nenhuma visita nova será criada."
)


@dataclass(frozen=True)
class ResumoPedidos:
    futuros_cancelados: int = 0
    em_andamento: tuple[str, ...] = ()
    # Futuros que não foram cancelados (ausência do cliente em análise ou falha): conferir.
    futuros_pendentes: tuple[str, ...] = ()


def pedidos_do_usuario(contexto: Contexto, usuario_id: str) -> list[Pedido]:
    achados: dict[str, Pedido] = {}
    for como_cliente in (True, False):
        offset = 0
        while True:
            pagina = contexto.pedidos.listar_do_usuario(usuario_id, como_cliente, _PAGINA, offset)
            achados.update((p.id, p) for p in pagina)
            if len(pagina) < _PAGINA:
                break
            offset += _PAGINA
    return list(achados.values())


def _aguarda_analise(contexto: Contexto, pedido: Pedido) -> bool:
    """Visita que já aconteceu com ausência do cliente: quem decide o valor é o analista (7.6)."""
    if pedido.cliente_ausente_em is not None:
        return True
    ausencia = ausencia_do_pedido(contexto, pedido)
    return ausencia is not None and ausencia.status in PENDENTES


def _cancelar(contexto: Contexto, pedido_id: str, usuario_id: str) -> bool:
    with contexto.transacao():
        travar = getattr(contexto.pedidos, "travar", None)
        if travar is not None:
            travar(pedido_id)
        pedido = contexto.pedidos.obter(pedido_id)  # relido com a trava
        if pedido is None or pedido.estado not in FUTUROS or _aguarda_analise(contexto, pedido):
            return False
        transicao = estados.transicionar(
            pedido, Acao.CANCELAR_MEDIDA_CONTA, _SISTEMA, contexto.agora()
        )
        gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
        if pedido.estado in (Estado.ABERTO, Estado.RESERVADO):
            encerrar_exclusividade_do_pedido(contexto, pedido.id, None)
        encerrar_na_contratacao(contexto, pedido.id, None)
        contexto.cancelamentos.descartar_proposta(pedido.id)  # nenhuma retenção sobrevive
        for gancho in contexto.apos_transicao:  # dinheiro: estorno integral, idempotente
            gancho(pedido, gravado, Acao.CANCELAR_MEDIDA_CONTA, contexto)
        avisar_partes(
            contexto,
            Evento.PEDIDO_CANCELADO_CONTA,
            tuple(u for u in (pedido.cliente_id, pedido.profissional_id) if u != usuario_id),
            pedido_id=pedido.id,
            chave=f"{pedido.id}:medida_conta",
            corpo=_AVISO,
        )
    return True


def _pausar_series(contexto: Contexto, usuario_id: str) -> None:
    repo = contexto.recorrencias
    for serie in repo.do_usuario(usuario_id):
        try:
            with contexto.transacao():
                if repo.mudar_status(serie.id, (ST_ATIVA,), ST_PAUSADA, contexto.agora()):
                    outra = (
                        serie.profissional_id
                        if serie.cliente_id == usuario_id
                        else serie.cliente_id
                    )
                    avisar_partes(
                        contexto,
                        Evento.SERIE_PAUSADA_CONTA,
                        (outra,),
                        pedido_id=serie.pedido_origem_id,
                        chave=f"serie:{serie.id}:medida_conta",
                        corpo=_AVISO_SERIE,
                    )
                # Visita ainda sem pagamento sai da agenda. Quem é só o profissional da série
                # ainda não é parte do pedido aberto, por isso ele é cancelado por aqui.
                for visita in repo.visitas(serie.id):
                    if visita.status != V_AGENDADA or not visita.pedido_id:
                        continue
                    _cancelar(contexto, visita.pedido_id, usuario_id)
                    pedido = contexto.pedidos.obter(visita.pedido_id)
                    if pedido is not None and pedido.estado is Estado.CANCELADO:
                        repo.mudar_visita(visita.id, (V_AGENDADA,), V_CANCELADA, None)
        except Exception:  # noqa: BLE001 - o agendador tenta de novo
            log.exception("Não pausei a série %s da conta suspensa", serie.id)


def tratar_pedidos(contexto: Contexto, usuario_id: str) -> int:
    """Cancela os futuros e pausa as séries. Devolve quantos cancelou agora. Nunca levanta."""
    cancelados = 0
    try:
        _pausar_series(contexto, usuario_id)
        for pedido in pedidos_do_usuario(contexto, usuario_id):
            if pedido.estado not in FUTUROS:
                continue
            try:
                cancelados += _cancelar(contexto, pedido.id, usuario_id)
            except Exception:  # noqa: BLE001 - um pedido ruim não segura os outros
                log.exception("Não cancelei o pedido %s da conta suspensa", pedido.id)
    except Exception:  # noqa: BLE001 - a medida já está gravada
        log.exception("Tratamento dos pedidos da conta suspensa falhou")
    return cancelados


def resumo(contexto: Contexto, usuario_id: str, desde: datetime) -> ResumoPedidos:
    """Lido do histórico dos pedidos (sem coluna nova): cancelados por conta desde `desde`."""
    cancelados, andamento, pendentes = 0, [], []
    todos = {p.id: p for p in pedidos_do_usuario(contexto, usuario_id)}
    for serie in contexto.recorrencias.do_usuario(usuario_id):
        for visita in contexto.recorrencias.visitas(serie.id):
            if visita.pedido_id and visita.pedido_id not in todos:
                achado = contexto.pedidos.obter(visita.pedido_id)
                if achado is not None:
                    todos[achado.id] = achado
    for pedido in todos.values():
        if pedido.estado is Estado.EM_ANDAMENTO:
            andamento.append(pedido.id)
        elif pedido.estado in FUTUROS:
            pendentes.append(pedido.id)
        elif pedido.estado is Estado.CANCELADO:
            cancelados += any(
                e.acao is Acao.CANCELAR_MEDIDA_CONTA and e.em >= desde
                for e in contexto.pedidos.eventos(pedido.id)
            )
    return ResumoPedidos(cancelados, tuple(sorted(andamento)), tuple(sorted(pendentes)))
