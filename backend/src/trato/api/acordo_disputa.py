"""Acordo com devolução (Termos 8.2): o cliente ACEITA a devolução que o profissional propôs.

Nunca vale devolução decidida por uma parte só. O dinheiro segue o mesmo caminho e a mesma
chave da decisão do analista (`dinheiro_da_disputa`), com o pedido travado: aceite repetido,
aceite simultâneo e decisão ao mesmo tempo movem o valor no máximo uma vez. A devolução ao
cliente vira ordem de estorno; quem marca como devolvido é o retorno do provedor. O que fica
com o profissional segue a liberação normal, com todas as travas.

A proposta é a evidência `proposta_retorno` da resposta (tabela imutável), cujo texto é escrito
só pelo servidor: `texto_da_proposta` grava e `proposta_de_reembolso` lê.
"""

from __future__ import annotations

import re
from contextlib import nullcontext
from dataclasses import replace
from typing import Any

from fastapi import HTTPException

from trato.api.contexto import Contexto
from trato.api.decisao_disputa import _TRAVA_EM_MEMORIA
from trato.api.regra_contratada import dias_de_garantia
from trato.disputas import Decisao, Disputa, Estado, Resultado, dividir_valor
from trato.garantias import abrir_garantia
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Pedido
from trato.persistencia.cancelamentos import EM_ANALISE

PARCIAL = Resultado.REEMBOLSO_PARCIAL.value
_PROPOSTA = re.compile(r"Propõe reembolso parcial de R\$ (\d+),(\d{2})\.")
_ACEITAVEIS = (Estado.EM_ANALISE, Estado.AGUARDANDO_APROVACAO)


def texto_da_proposta(centavos: int) -> str:
    return f"Propõe reembolso parcial de R$ {centavos // 100},{centavos % 100:02d}."


def proposta_de_reembolso(contexto: Contexto, pedido_id: str, disputa: Disputa) -> int | None:
    """Quanto o profissional propôs devolver na resposta desta disputa, em centavos."""
    ler = getattr(contexto.disputas, "propostas", None)
    if ler is None or disputa.respondida_em is None:
        return None
    for texto in reversed(ler(pedido_id)):
        achado = _PROPOSTA.fullmatch(texto or "")
        if achado:
            valor = int(achado[1]) * 100 + int(achado[2])
            return valor if 0 < valor < disputa.valor_congelado else None
    return None


def aceitar(
    contexto: Contexto,
    servico: Any,
    pedido_id: str,
    cliente_id: str,
    solucao: str,
    reembolso_centavos: int,
) -> tuple[Disputa, tuple[Pedido, Pedido] | None]:
    """(disputa em acordo, (pedido antes, depois)). Na repetição do mesmo aceite, o segundo
    item é None: nada foi gravado."""
    travar = getattr(contexto.pedidos, "travar", None)
    with _TRAVA_EM_MEMORIA if travar is None else nullcontext(), contexto.transacao():
        if travar is not None:
            travar(pedido_id)
        pedido = contexto.pedidos.obter(pedido_id)  # lidos só depois da trava
        disputa = contexto.disputas.obter(pedido_id)
        if pedido is None or disputa is None:
            raise HTTPException(404, "Este pedido não tem disputa.")
        if disputa.estado is Estado.ACORDO:
            d = disputa.decisao
            if d is not None and (d.resultado.value, d.valor_cliente_centavos) == (
                solucao,
                reembolso_centavos,
            ):
                return disputa, None
            raise HTTPException(409, "A disputa já foi encerrada por outro acordo.")
        if disputa.estado not in _ACEITAVEIS or pedido.estado is not estados.Estado.EM_DISPUTA:
            raise HTTPException(409, "Esta disputa não aceita mais um acordo.")
        proposto = proposta_de_reembolso(contexto, pedido_id, disputa)
        if proposto is None or (solucao, reembolso_centavos) != (PARCIAL, proposto):
            raise HTTPException(
                409, "A proposta de devolução não é essa. Atualize e confira antes de aceitar."
            )
        caso = contexto.cancelamentos.do_pedido(pedido_id)
        if caso is not None and caso.status == EM_ANALISE:
            raise HTTPException(409, "Este caso é uma desistência e é decidido pela equipe.")
        if servico is None:
            raise HTTPException(503, "O pagamento está indisponível: o acordo não foi aceito.")
        transicao = estados.transicionar(
            pedido,
            Acao.ENCERRAR_DISPUTA_POR_ACORDO,
            Ator(estados.Papel.CLIENTE, cliente_id),
            contexto.agora(),
            None,
            contexto.config.carregar().prazos_pedido,
        )
        decisao = Decisao(Resultado.REEMBOLSO_PARCIAL, valor_cliente_centavos=proposto)
        acordo = replace(
            disputa.encerrar_por_acordo(),
            decisao=decisao,
            divisao=dividir_valor(disputa.valor_congelado, decisao),
        )
        # Dinheiro primeiro: se o ledger ou as cobranças recusarem, nada é gravado.
        servico.dinheiro_da_disputa(contexto, transicao.pedido, acordo)
        gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
        if gravado.concluido_em and contexto.garantias.obter_garantia(gravado.id) is None:
            contrato = contexto.contratos.obter_do_pedido(gravado.id)
            contexto.garantias.salvar_garantia(
                gravado.id,
                abrir_garantia(
                    gravado.concluido_em,
                    contrato.categoria_id if contrato else None,
                    contexto.config.carregar().garantias,
                    dias_contrato=dias_de_garantia(contexto, contrato),
                ),
            )
        contexto.disputas.salvar(pedido_id, acordo)
    return acordo, (pedido, gravado)
