"""De onde vêm os pedidos monitorados (`Fonte`) e como cada ação é executada (`Executor`).

`FonteContexto` e `ExecutorContexto` usam o `Contexto` da API (memória ou Postgres). As regras
em si estão em `trato.rotinas.regras` e não são reescritas aqui.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import fields, replace
from datetime import date, datetime, timedelta
from typing import Protocol

from trato.api.contexto import Contexto
from trato.disputas import Estado as EstadoDisputa
from trato.financeiro.ledger import Lancamento, TipoLancamento, a_liberar, liberado
from trato.notificacoes.eventos import Evento
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Pedido, TransicaoInvalida, transicionar
from trato.persistencia.conexao import Banco
from trato.rotinas.regras import (
    SISTEMA,
    AcaoRotina,
    ConfigRotinas,
    DisputaMonitorada,
    Lembrete,
    PedidoMonitorado,
    TipoAcaoRotina,
)

Carga = tuple[list[PedidoMonitorado], ConfigRotinas, frozenset[date]]


class Fonte(Protocol):
    def carregar(self, agora: datetime) -> Carga: ...


class Executor(Protocol):
    def executar(self, acao: AcaoRotina, agora: datetime) -> None:
        """Faz a ação. Precisa ser idempotente (rodar de novo não pode duplicar efeito)."""


def config_rotinas_da_api(
    contexto: Contexto, complemento: ConfigRotinas | None = None
) -> ConfigRotinas:
    """Monta a `ConfigRotinas` com o que a configuração publicada já tem.

    O resto (liberação, lembretes, limite de valor) vem de `complemento`; campo `None` deixa a
    rotina daquele item desligada, como manda `trato.rotinas`.
    """
    api = contexto.config.carregar()
    prazos, disputas = api.prazos_pedido, api.disputas
    base = ConfigRotinas(
        validade_pedido=prazos.receber_orcamentos,
        prazo_pagamento=prazos.pagamento,
        tolerancia_comparecimento=prazos.tolerancia_comparecimento,
        prazo_confirmacao_cliente=prazos.confirmacao_cliente,
        prazo_resposta_disputa=None,
        prazo_decisao_disputa_dias_uteis=disputas.prazo_decisao_dias_uteis,
        janela_congelamento_repasse=None,
    )
    base = replace(
        base,
        prazo_resposta_disputa=timedelta(hours=disputas.prazo_resposta_horas),
        janela_congelamento_repasse=timedelta(hours=disputas.prazo_congelar_repasse_horas),
    )
    if complemento is None:
        return base
    extras = {
        c.name: getattr(complemento, c.name)
        for c in fields(complemento)
        if getattr(complemento, c.name) not in (None, False)
    }
    return replace(base, **extras)


def ids_ativos_memoria(contexto: Contexto) -> Callable[[], list[str]]:
    return lambda: sorted(getattr(contexto.pedidos, "_pedidos", {}))


def ids_ativos_postgres(banco: Banco, dias_concluidos: int = 60) -> Callable[[], list[str]]:
    """Pedidos em andamento + os concluídos há pouco (que ainda podem ter saldo a liberar)."""

    def ids() -> list[str]:
        with banco.transacao() as con:
            linhas = con.execute(
                "select id from public.pedidos where status <> 'cancelado' and "
                "(status <> 'concluido' or atualizado_em > now() - make_interval(days => %s)) "
                "order by criado_em",
                (dias_concluidos,),
            ).fetchall()
        return [str(l["id"]) for l in linhas]  # noqa: E741

    return ids


class FonteContexto:
    def __init__(
        self,
        contexto: Contexto,
        ids_ativos: Callable[[], list[str]],
        complemento: ConfigRotinas | None = None,
    ) -> None:
        self._c = contexto
        self._ids = ids_ativos
        self._complemento = complemento

    def carregar(self, agora: datetime) -> Carga:
        c = self._c
        itens = []
        for pid in self._ids():
            pedido = c.pedidos.obter(pid)
            if pedido is None:
                continue
            contrato = c.contratos.obter_do_pedido(pid)
            disputa = c.disputas.obter(pid)
            saldo = (
                c.ledger.saldos_pedido(pid, pedido.profissional_id).a_liberar
                if pedido.profissional_id
                else 0
            )
            itens.append(
                PedidoMonitorado(
                    pedido,
                    valor_servico_centavos=contrato.valor_centavos if contrato else 0,
                    orcamentos_recebidos=len(c.orcamentos.do_pedido(pid)),
                    saldo_a_liberar_centavos=saldo,
                    disputa=DisputaMonitorada(disputa.aberta_em, disputa.respondida_em is not None)
                    if disputa
                    else None,
                    disputa_aberta=bool(disputa and disputa.estado is not EstadoDisputa.DECIDIDA),
                )
            )
        feriados = frozenset(c.config.carregar().disputas.feriados)
        return itens, config_rotinas_da_api(c, self._complemento), feriados


_LEMBRETE_PARA_EVENTO = {
    Lembrete.CONFIRMACAO_PENDENTE: (Evento.CONCLUSAO_PARA_CONFIRMAR, "cliente"),
    Lembrete.RESPOSTA_DISPUTA: (Evento.LEMBRETE_RESPOSTA_DISPUTA, "profissional"),
    Lembrete.ADITIVO_AGUARDANDO: (Evento.ADITIVO_PENDENTE, "cliente"),
    # DECISAO_DISPUTA é da equipe (sem destinatário individual): fica para o painel admin.
}


class ExecutorContexto:
    def __init__(self, contexto: Contexto, notificacoes: ServicoNotificacoes | None = None) -> None:
        self._c = contexto
        self._notif = notificacoes

    def executar(self, acao: AcaoRotina, agora: datetime) -> None:
        if acao.tipo is TipoAcaoRotina.TRANSICIONAR:
            self._transicionar(acao, agora)
        elif acao.tipo is TipoAcaoRotina.LIBERAR_SALDO:
            self._liberar(acao, agora)
        elif acao.tipo is TipoAcaoRotina.LEMBRETE:
            self._lembrar(acao)

    def _transicionar(self, acao: AcaoRotina, agora: datetime) -> None:
        c = self._c
        antes = c.pedidos.obter(acao.pedido_id)
        if antes is None or acao.acao is None:
            return
        try:
            t = transicionar(
                antes, acao.acao, SISTEMA, agora, prazos=c.config.carregar().prazos_pedido
            )
        except TransicaoInvalida:
            return  # outra instância ou o usuário já mudou o pedido: nada a fazer
        depois = c.pedidos.salvar(t.pedido, t.evento)
        for gancho in c.apos_transicao:
            gancho(antes, depois, acao.acao, c)

    def _liberar(self, acao: AcaoRotina, agora: datetime) -> None:
        if not acao.profissional_id or not acao.valor_centavos:
            return
        self._c.ledger.lancar_varios(
            [
                Lancamento(
                    acao.chave,
                    acao.pedido_id,
                    TipoLancamento.LIBERACAO,
                    a_liberar(acao.profissional_id),
                    liberado(acao.profissional_id),
                    acao.valor_centavos,
                    agora,
                )  # fmt: skip
            ]
        )

    def _lembrar(self, acao: AcaoRotina) -> None:
        alvo = _LEMBRETE_PARA_EVENTO.get(acao.lembrete) if acao.lembrete else None
        pedido: Pedido | None = self._c.pedidos.obter(acao.pedido_id)
        if alvo is None or pedido is None or self._notif is None:
            return
        evento, quem = alvo
        usuario = pedido.cliente_id if quem == "cliente" else pedido.profissional_id
        if usuario:
            self._notif.notificar(evento, usuario, chave=acao.chave, pedido_id=pedido.id)
