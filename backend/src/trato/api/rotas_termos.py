"""Histórico de versões dos Termos (23.7), para o app mostrar qual versão valia em cada Pedido.

Só aparece versão cujo dia de vigência já chegou: nada é publicado antes da hora. A data vem de
`termos_versoes` (é ela que carimba o contrato); sem a tabela, vem de `trato.legal`. O texto só é
entregue quando o arquivo da versão existe."""

from __future__ import annotations

import logging
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from trato import legal
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro import periodo

log = logging.getLogger("trato.termos")
router = APIRouter(prefix="/v1/termos", tags=["legal"])


class VersaoOut(BaseModel):
    versao: str
    vigente_desde: date = Field(description="Dia (Brasília) em que passou a valer.")
    vigente_ate: date | None = Field(description="Último dia em que valeu. Nulo: é a atual.")
    atual: bool
    texto_disponivel: bool


class HistoricoOut(BaseModel):
    itens: list[VersaoOut] = Field(description="Da mais nova para a mais antiga.")


class TextoOut(VersaoOut):
    texto: str = Field(description="Markdown.")


def _da_tabela(contexto: Contexto) -> dict[str, date]:
    banco = contexto.extras.get("banco")
    if banco is None:
        return {}
    try:
        with banco.transacao() as con:
            linhas = con.execute(
                "select versao, vigente_desde from public.termos_versoes"
            ).fetchall()
    except Exception:  # noqa: BLE001 - sem a tabela (ou banco fora): vale o que o código tem
        log.warning("termos_versoes indisponível: histórico pelo código", exc_info=True)
        return {}
    return {x["versao"]: x["vigente_desde"] for x in linhas}


def historico(contexto: Contexto) -> list[VersaoOut]:
    publicadas = {v.versao: v.vigente_desde for v in legal.VERSOES}
    datas = publicadas | _da_tabela(contexto)
    hoje = contexto.agora().astimezone(periodo.BRASILIA).date()
    valeram = sorted((d, v) for v, d in datas.items() if d <= hoje)
    saida: list[VersaoOut] = []
    for i, (desde, versao) in enumerate(valeram):
        seguinte = valeram[i + 1][0] if i + 1 < len(valeram) else None
        saida.append(
            VersaoOut(
                versao=versao,
                vigente_desde=desde,
                vigente_ate=date.fromordinal(seguinte.toordinal() - 1) if seguinte else None,
                atual=seguinte is None,
                texto_disponivel=versao in publicadas,
            )
        )
    return saida[::-1]


@router.get("/versoes", response_model=HistoricoOut, summary="Histórico de versões dos Termos")
def listar(contexto: Contexto = Depends(obter_contexto)) -> HistoricoOut:
    return HistoricoOut(itens=historico(contexto))


@router.get(
    "/versoes/{versao}", response_model=TextoOut, summary="Texto de uma versão que já valeu"
)
def texto(versao: str, contexto: Contexto = Depends(obter_contexto)) -> TextoOut:
    item = next((v for v in historico(contexto) if v.versao == versao), None)
    publicada = next((v for v in legal.VERSOES if v.versao == versao), None)
    if item is None or publicada is None:
        raise HTTPException(404, "Texto desta versão não disponível.")
    return TextoOut(**item.model_dump(), texto=publicada.texto())
