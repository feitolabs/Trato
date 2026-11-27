"""O que, no histórico de um pedido concluído, muda a data da liberação (Termos 5.8 e 8.7).

Usado pelo agendador e pelas telas, para a data prometida ser a mesma que a rotina cumpre.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime

from trato.api.contexto import Contexto
from trato.disputas import Estado as EstadoDisputa
from trato.pedidos.estados import Acao, Estado, Pedido
from trato.persistencia.contestacoes_decisao import PENDENTES
from trato.persistencia.sac import ENCERRADO, Filtro

_CONFIRMACOES = (Acao.CONFIRMAR_CONCLUSAO, Acao.CONCLUIR_POR_PRAZO)


@dataclass(frozen=True)
class Fatos:
    # 5.8: concluiu por confirmação (expressa ou pelo silêncio), sem disputa
    confirmado: bool = False
    # 8.7: fim do prazo para contestar a decisão da disputa
    contestar_ate: datetime | None = None
    contestacao_pendente: bool = False
    # disputa decidida sem data conhecida: não dá para saber quando o prazo acaba
    prazo_desconhecido: bool = False
    disputa_aberta: bool = False
    # pedido cancelado com retenção de ausência confirmada: quando foi confirmada
    retencao_em: datetime | None = None
    # 8.8 e 9.6: o que mantém o valor retido (incidente, chamado_seguranca, denuncia_grave)
    relato: str | None = None


def _retencao_de_ausencia(contexto: Contexto, pedido: Pedido) -> Fatos:
    """7.6 e 8.7: só a retenção confirmada, depois do prazo para contestar a confirmação."""
    from trato.api.ausencia_base import contestar_ate, revisao_de  # tardio: evita ciclo

    caso = contexto.cancelamentos.do_pedido(pedido.id)
    if (
        caso is None
        or caso.tipo != "cliente_ausente"
        or caso.status != "confirmado"
        or caso.retencao_centavos <= 0
    ):
        return Fatos()
    confirmacoes = [
        e.em for e in contexto.pedidos.eventos(pedido.id) if e.acao is Acao.CANCELAR_CLIENTE_AUSENTE
    ]
    if not confirmacoes:
        return Fatos()
    marcos = [confirmacoes[-1], caso.retencao_mostrada_em]
    revisao = revisao_de(contexto, caso)
    return Fatos(
        retencao_em=confirmacoes[-1],
        contestar_ate=max(contestar_ate(contexto, m) for m in marcos if m is not None),
        contestacao_pendente=revisao is not None
        and revisao.status not in ("mantida", "alterada", "revertida"),
    )


def relato_de_seguranca(contexto: Contexto, pedido_id: str) -> str | None:
    """Relato de dano ou de incidente ligado ao pedido cuja análise não terminou."""
    if contexto.chamados.incidente_aberto(pedido_id):
        return "incidente"
    if contexto.sac.disponivel():
        filtro = Filtro(pedido_id=pedido_id, categoria="seguranca")
        chamados, _ = contexto.sac.listar(filtro, 100, 0)
        if any(c.status != ENCERRADO for c in chamados):
            return "chamado_seguranca"
    if contexto.denuncias.grave_aberta(pedido_id):
        return "denuncia_grave"
    return None


def fatos_da_liberacao(contexto: Contexto, pedido: Pedido) -> Fatos:
    return replace(_fatos(contexto, pedido), relato=relato_de_seguranca(contexto, pedido.id))


def _fatos(contexto: Contexto, pedido: Pedido) -> Fatos:
    if pedido.estado is Estado.CANCELADO:
        return _retencao_de_ausencia(contexto, pedido)
    conclusoes = [
        e
        for e in contexto.pedidos.eventos(pedido.id)
        if e.para is Estado.CONCLUIDO and e.de is not Estado.CONCLUIDO
    ]
    ultima = conclusoes[-1] if conclusoes else None
    disputa = contexto.disputas.obter(pedido.id)
    if disputa is None:
        return Fatos(confirmado=ultima is not None and ultima.acao in _CONFIRMACOES)
    if disputa.estado is not EstadoDisputa.DECIDIDA:
        # O histórico vale também para acordos antigos, que não fechavam o registro.
        acordo = (
            ultima is not None
            and ultima.acao is Acao.ENCERRAR_DISPUTA_POR_ACORDO
            and ultima.em >= disputa.aberta_em
        )
        if acordo or disputa.estado is EstadoDisputa.ACORDO:
            return Fatos(confirmado=acordo)  # 8.2: o cliente concordou em encerrar
        return Fatos(disputa_aberta=True)
    from trato.api.contestacao_disputa import decisao_da_disputa  # tardio: evita ciclo

    decidida = decisao_da_disputa(contexto, pedido)
    repo = contexto.contestacoes_decisao
    pendente = False
    if repo.disponivel():
        itens, _ = repo.listar(pedido_id=pedido.id, limite=10)
        pendente = any(i.status in PENDENTES for i in itens)
    return Fatos(
        contestar_ate=decidida.contestar_ate if decidida else None,
        contestacao_pendente=pendente,
        prazo_desconhecido=decidida is None,
    )
