"""Exclusividade paga pelo CLIENTE (Termos 13.6, 13.8 e I.4; ajuste 6).

O cliente usa os Tratinhos e, por 48 h, o pedido não vai para outros profissionais. Sem
contratação no prazo, não voltam; voltam por desistência do profissional ou falha do Trato
(`api/admin/rotas_exclusividade.py`). Custo e prazo vêm da configuração de moedas.
"""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.exclusividades import Exclusividade
from trato.api.moedas_saldo import creditos_validos
from trato.api.rotas_app import pedido_visivel_ao_profissional
from trato.api.rotas_mei import servico_mei
from trato.api.selo import selo_retirado
from trato.notificacoes.eventos import Evento

router = APIRouter(prefix="/v1", tags=["exclusividade do cliente"])

_ERROS = {
    "nao_encontrado": (404, "Pedido não encontrado."),
    "pedido_indisponivel": (409, "Este pedido não está disponível para exclusividade."),
    "orcamento_invalido": (422, "Este orçamento não vale mais para este pedido."),
    "profissional_indisponivel": (422, "Este profissional não pode atender este pedido."),
    "saldo_insuficiente": (422, "Você não tem Tratinhos suficientes."),
    "indisponivel": (503, "A exclusividade está indisponível no momento."),
}


class PedirExclusividadeIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    profissional_id: str | None = Field(None, max_length=64)
    orcamento_id: str | None = Field(None, max_length=64)
    chave_idempotencia: str = Field(min_length=8, max_length=80)


class ExclusividadeClienteOut(BaseModel):
    id: str
    pedido_id: str
    profissional_id: str
    orcamento_id: str | None = None
    status: str = Field(
        description="ativa | concluida | cancelada | expirada_sem_contratacao",
    )
    moedas: int
    criada_em: datetime
    expira_em: datetime | None = None
    encerrada_em: datetime | None = None
    motivo_encerramento: str | None = None
    devolvida: bool = False


class CreditoOut(BaseModel):
    moedas: int
    expira_em: datetime | None = None


class SituacaoExclusividadeOut(BaseModel):
    disponivel: bool
    custo_moedas: int
    duracao_horas: int
    saldo_livre: int = Field(description="Saldo válido menos o preso em descontos abertos.")
    creditos: list[CreditoOut] = Field(description="Saldo por validade, na ordem de uso.")
    exclusividade: ExclusividadeClienteOut | None = None


class DevolucaoOut(BaseModel):
    resultado: str
    moedas_devolvidas: int


def saida(item: Exclusividade) -> ExclusividadeClienteOut:
    return ExclusividadeClienteOut(
        id=item.id,
        pedido_id=item.pedido_id,
        profissional_id=item.profissional_id,
        orcamento_id=item.orcamento_id,
        status=item.status,
        moedas=item.moedas_cobradas,
        criada_em=item.criada_em,
        expira_em=item.expira_em,
        encerrada_em=item.encerrada_em,
        motivo_encerramento=item.motivo_encerramento,
        devolvida=item.estornada,
    )


def _erro(status: int, codigo: str, mensagem: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo})


@router.get(
    "/pedidos/{pedido_id}/exclusividade-cliente",
    response_model=SituacaoExclusividadeOut,
    summary="Cliente: custo, saldo com validade e a exclusividade do pedido",
)
def situacao(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
):
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or pedido.cliente_id != usuario.id:
        return _erro(404, "nao_encontrado", "Pedido não encontrado.")
    cfg = contexto.moedas.config()
    disponivel = contexto.exclusividades.cliente_disponivel()
    agora = contexto.agora()
    item = contexto.exclusividades.do_pedido_cliente(pedido.id) if disponivel else None
    carteira = contexto.moedas.lancamentos_da_carteira(usuario.id, "cliente")
    return SituacaoExclusividadeOut(
        disponivel=disponivel,
        custo_moedas=cfg.exclusividade_custo_moedas,
        duracao_horas=cfg.exclusividade_duracao_horas,
        saldo_livre=contexto.exclusividades.saldo_livre(usuario.id, agora) if disponivel else 0,
        creditos=[
            CreditoOut(moedas=p.quantidade, expira_em=p.expira_em)
            for p in creditos_validos(carteira, agora)
        ],
        exclusividade=saida(item) if item else None,
    )


@router.post(
    "/pedidos/{pedido_id}/exclusividade-cliente",
    response_model=ExclusividadeClienteOut,
    status_code=201,
    summary="Cliente: usar Tratinhos pela exclusividade de um profissional ou orçamento",
    description="`201` cria; `200` devolve a mesma para a mesma chave. Erros trazem `codigo`.",
)
def pedir(
    pedido_id: str,
    corpo: PedirExclusividadeIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
):
    if not corpo.profissional_id and not corpo.orcamento_id:
        return _erro(422, "falta_escolha", "Escolha um profissional ou um orçamento.")
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or pedido.cliente_id != usuario.id:
        return _erro(404, "nao_encontrado", "Pedido não encontrado.")
    agora = contexto.agora()
    if contexto.medidas.impedida(usuario.id, agora):
        return _erro(403, "conta_com_restricao", "Sua conta tem uma medida ativa.")
    escolhido = corpo.profissional_id
    if corpo.orcamento_id:
        orcamento = contexto.orcamentos.obter(corpo.orcamento_id)
        if orcamento is not None:
            escolhido = escolhido or orcamento.profissional_id
    if escolhido and contexto.medidas.impedida(escolhido, agora):
        return _erro(422, "profissional_indisponivel", _ERROS["profissional_indisponivel"][1])
    mei = servico_mei(request)
    exigir_mei = bool(mei.config.obrigatorio)

    def apto(profissional_id: str) -> bool:
        return (
            profissional_id != usuario.id
            and not selo_retirado(contexto, profissional_id)  # 10.3: não poderia orçar
            and pedido_visivel_ao_profissional(contexto, pedido.id, profissional_id) is not None
            and (not exigir_mei or mei.liberado(profissional_id))
        )

    try:
        r = contexto.exclusividades.solicitar_cliente(
            usuario.id,
            pedido.id,
            corpo.profissional_id,
            corpo.orcamento_id,
            corpo.chave_idempotencia,
            agora,
            exigir_mei,
            apto,
        )
    except ValueError:
        return _erro(422, "chave_invalida", "Chave de idempotência já usada.")
    if r.resultado not in ("ok", "ja_existe"):
        status, mensagem = _ERROS.get(r.resultado, _ERROS["indisponivel"])
        return _erro(status, r.resultado, mensagem)
    item = contexto.exclusividades.obter(r.exclusividade_id or "")
    if item is None:
        return _erro(503, "indisponivel", _ERROS["indisponivel"][1])
    if r.resultado == "ja_existe":
        return JSONResponse(status_code=200, content=jsonable_encoder(saida(item)))
    avisar_partes(
        contexto,
        Evento.EXCLUSIVIDADE_CLIENTE_NOVA,
        (item.profissional_id,),
        pedido_id=item.pedido_id,
        chave=f"{item.id}:nova",
    )
    return saida(item)


@router.post(
    "/profissional/exclusividades/{exclusividade_id}/desistir",
    response_model=DevolucaoOut,
    summary="Profissional: desistir da exclusividade do cliente (os Tratinhos voltam a ele)",
)
def desistir(
    exclusividade_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
):
    r = contexto.exclusividades.desistir_cliente(exclusividade_id, usuario.id, contexto.agora())
    if r.resultado in ("ok", "ja_devolvida"):
        item = contexto.exclusividades.obter(exclusividade_id)
        if item is not None:
            avisar_partes(
                contexto,
                Evento.EXCLUSIVIDADE_CLIENTE_DEVOLVIDA,
                (item.cliente_id,),
                pedido_id=item.pedido_id,
                chave=f"{item.id}:devolvida",
            )
        return DevolucaoOut(resultado=r.resultado, moedas_devolvidas=r.devolvido)
    erros = {
        "nao_encontrada": (404, "Exclusividade não encontrada."),
        "ja_encerrada": (409, "Esta exclusividade já terminou."),
        "prazo_vencido": (409, "O prazo desta exclusividade já terminou."),
    }
    status, mensagem = erros.get(r.resultado, _ERROS["indisponivel"])
    return _erro(status, r.resultado, mensagem)
