"""Efetivar a decisão de uma disputa: o ÚNICO caminho, usado pela rota do pedido
(`/v1/pedidos/{id}/disputa/decisao`) e pelo painel (`/v1/admin/disputas/{id}/decisao` e
`/aprovacao`).

Uma transação só: pedido, ledger, ordens de estorno, repasse, garantia, disputa e a auditoria de
quem chamou. O provedor só é chamado depois do commit, com a chave da ordem; o que falhar fica
pendente para o agendador. Uma decisão por vez no pedido: repetir, decidir junto ou aprovar duas
vezes responde 409 sem mover nada. Proposta acima da alçada não move dinheiro.
"""

from __future__ import annotations

import threading
from collections.abc import Callable, Iterator
from contextlib import contextmanager, nullcontext
from functools import partial
from typing import Any

from fastapi import HTTPException

from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto
from trato.api.regra_contratada import dias_de_garantia
from trato.disputas import Disputa, Estado, Resultado
from trato.financeiro.ledger import Lancamento
from trato.garantias import abrir_garantia
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Pedido
from trato.persistencia.cancelamentos import EM_ANALISE
from trato.persistencia.erros import ConflitoDeEstado

# Em memória não há trava de linha: este cadeado faz o papel dela.
_TRAVA_EM_MEMORIA = threading.RLock()

Auditar = Callable[[Pedido, Pedido, list[Lancamento]], None]

_RESULTADOS = {
    Resultado.LIBERAR_TUDO: "o valor vai para o profissional",
    Resultado.REEMBOLSO_TOTAL: "reembolso total ao cliente",
    Resultado.REEMBOLSO_PARCIAL: "reembolso parcial ao cliente",
    Resultado.NOVA_VISITA: "o profissional vai refazer o serviço",
}


def _avisar_decisao(contexto: Contexto, pedido: Pedido, disputa: Disputa) -> None:
    assert disputa.decisao is not None  # noqa: S101 - só decisões finais chegam aqui
    avisar_partes(
        contexto,
        Evento.DISPUTA_DECIDIDA,
        (pedido.cliente_id, pedido.profissional_id),
        pedido_id=pedido.id,
        chave=f"{pedido.id}:decisao:{int(disputa.aberta_em.timestamp())}",
        corpo=f"A análise da reclamação terminou: {_RESULTADOS[disputa.decisao.resultado]}. "
        "Veja os detalhes no pedido.",
    )


@contextmanager
def _uma_por_vez(contexto: Contexto, pedido_id: str, lida: Disputa) -> Iterator[None]:
    """Trava o pedido e confere que a disputa ainda é a que foi lida antes de decidir."""
    travar = getattr(contexto.pedidos, "travar", None)
    with _TRAVA_EM_MEMORIA if travar is None else nullcontext():
        with contexto.transacao():
            if travar is not None:
                travar(pedido_id)
            if contexto.disputas.obter(pedido_id) != lida:
                raise ConflitoDeEstado(
                    "A disputa mudou enquanto você decidia. Atualize e confira antes de decidir."
                )
            yield


def guardar_proposta(contexto: Contexto, pedido_id: str, lida: Disputa, nova: Disputa) -> None:
    """Decisão acima da alçada: só registra, esperando a segunda pessoa."""
    with _uma_por_vez(contexto, pedido_id, lida):
        contexto.disputas.salvar(pedido_id, nova)


def efetivar(
    contexto: Contexto,
    servico: Any,
    pedido_id: str,
    lida: Disputa,
    decidida: Disputa,
    ator: Ator,
    justificativa: str,
    auditar: Auditar | None = None,
) -> tuple[Pedido, list[Lancamento]]:
    """Aplica uma disputa já DECIDIDA. Devolve o pedido gravado e os lançamentos novos."""
    if decidida.estado is not Estado.DECIDIDA or decidida.decisao is None:
        raise ConflitoDeEstado("A disputa ainda não tem decisão final.")
    if servico is None:
        raise HTTPException(
            503, "O serviço de pagamento não está ligado: a decisão não pode mover o dinheiro."
        )
    with _uma_por_vez(contexto, pedido_id, lida):
        pedido = contexto.pedidos.obter(pedido_id)
        if pedido is None:
            raise HTTPException(404, "Pedido da disputa não encontrado.")
        transicao = estados.transicionar(
            pedido,
            Acao.DECIDIR_DISPUTA,
            ator,
            contexto.agora(),
            estados.DecisaoDisputa(
                estados.ResultadoDisputa(decidida.decisao.resultado.value), justificativa
            ),
            contexto.config.carregar().prazos_pedido,
        )
        caso = contexto.cancelamentos.do_pedido(pedido.id)
        if caso is not None and caso.status != EM_ANALISE:
            caso = None
        if caso is not None and decidida.decisao.resultado is Resultado.NOVA_VISITA:
            raise ConflitoDeEstado(
                "Este caso é uma desistência: decida o reembolso, não um novo atendimento."
            )
        antes = {i.id for i in contexto.ledger.lancamentos(pedido.id)}
        pago = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id).cliente_pagou
        # Dinheiro primeiro: se o ledger ou as cobranças recusarem, nada é gravado.
        servico.dinheiro_da_disputa(contexto, transicao.pedido, decidida)
        # O pedido antes da disputa: ela lê a descrição do histórico dele.
        gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
        if gravado.estado is estados.Estado.CONCLUIDO and gravado.concluido_em is not None:
            if contexto.garantias.obter_garantia(gravado.id) is None:
                contrato = contexto.contratos.obter_do_pedido(gravado.id)
                categoria = contrato.categoria_id if contrato else None
                contexto.garantias.salvar_garantia(
                    gravado.id,
                    abrir_garantia(
                        gravado.concluido_em,
                        categoria,
                        contexto.config.carregar().garantias,
                        dias_de_garantia(contexto, contrato),
                    ),
                )
        contexto.disputas.salvar(pedido_id, decidida)
        if caso is not None:  # caso de desistência: a decisão fica no registro dele
            devolvido = (
                pago
                - contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id).cliente_pagou
            )
            contexto.cancelamentos.decidir(
                pedido.id,
                "confirmado" if devolvido > 0 else "recusado",
                ator.id,
                justificativa,
                devolvido,
                contexto.agora(),
            )
        # Termos 15.2: as duas partes são avisadas da decisão, só depois de gravada.
        contexto.depois_do_commit(partial(_avisar_decisao, contexto, gravado, decidida))
        novos = [i for i in contexto.ledger.lancamentos(pedido.id) if i.id not in antes]
        if auditar is not None:
            auditar(pedido, gravado, novos)
    return gravado, novos
