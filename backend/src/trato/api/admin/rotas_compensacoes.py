"""Compensações no painel (Termos 8.6 e 17.4). Permissão `disputas_decidir`.

Regresso (17.4): uma pessoa propõe (`regresso_propor`) e outra aprova ou recusa
(`regresso_aprovar`). Não existe rota que registre a dívida de regresso sem proposta.
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api import compensacoes as regras
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro.extrato_profissional import reais
from trato.notificacoes.eventos import Evento
from trato.persistencia.compensacoes import Proposta

router = APIRouter(prefix="/v1/admin/compensacoes", tags=["admin: compensações"])


class RegistrarCompensacaoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pedido_id: str = Field(max_length=64)
    contestacao_id: str | None = Field(
        None, max_length=64, description="Contestação que mudou a decisão; null: decisão original."
    )
    valor_centavos: int = Field(gt=0, strict=True)
    motivo: str = Field(min_length=10, max_length=1000, description="O profissional lê.")


class CancelarCompensacaoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=1000)


class RegistroOut(BaseModel):
    resultado: str = Field(description="ok | ja_registrada")
    compensacao: regras.DividaOut
    avisado: bool


class CancelamentoOut(BaseModel):
    resultado: str = Field(description="ok | ja_cancelada")
    devolvido_centavos: int
    compensacao: regras.DividaOut


_ERROS = {
    "conflito": (409, "Esta decisão já tem compensação com outro valor."),
    "acima_do_devido": (422, "O valor passa do que pode ser compensado."),
    "origem_nao_decidida": (409, "Não há decisão final que permita compensar."),
    "decisao_substituida": (409, "A decisão foi mudada por contestação: informe a contestação."),
    "contrato_nao_encontrado": (404, "Pedido sem contrato."),
    "analista_invalido": (403, "Só alguém ativo da equipe pode fazer isto."),
    "nao_encontrada": (404, "Compensação não encontrada."),
    "indisponivel": (503, "A compensação ainda não está disponível."),
    "ja_registrada": (409, "Esta referência já virou compensação."),
    "ja_aprovada": (409, "Esta proposta já foi aprovada."),
    "ja_recusada": (409, "Esta proposta já foi recusada."),
    "mesma_pessoa": (403, "Quem propôs não pode aprovar."),
    "proponente_invalido": (409, "Quem propôs não está mais apto: proponha de novo."),
    "proposta_nao_encontrada": (404, "Proposta não encontrada."),
}


def _erro(codigo: str, **extra: int) -> JSONResponse:
    status, mensagem = _ERROS.get(codigo, _ERROS["indisponivel"])
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo} | extra)


@router.post("", response_model=RegistroOut, summary="Registrar compensação de uma decisão")
def registrar(
    corpo: RegistrarCompensacaoIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    contexto: Contexto = Depends(obter_contexto),
):
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return JSONResponse(422, {"detail": "Explique o motivo.", "codigo": "motivo_invalido"})
    if not contexto.compensacoes.disponivel():
        return _erro("indisponivel")
    pedido = contexto.pedidos.obter(corpo.pedido_id)
    if pedido is None:
        return _erro("contrato_nao_encontrado")
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is None:
        return _erro("indisponivel")
    travar = getattr(contexto.pedidos, "travar", None)
    with contexto.transacao():  # dívida e ordem de estorno: tudo ou nada
        if travar is not None:  # mesma ordem de travas dos outros fluxos: pedido, contrato
            travar(pedido.id)
        r = contexto.compensacoes.registrar_disputa(
            pedido.id, corpo.contestacao_id, corpo.valor_centavos, motivo, operador.id
        )
        if r.resultado == "ok":
            servico.ordenar_estorno_compensado(
                contexto, pedido.id, corpo.valor_centavos, r.divida_id or ""
            )
    if r.resultado not in ("ok", "ja_registrada"):
        extra = {"maximo_centavos": r.maximo_centavos} if r.resultado == "acima_do_devido" else {}
        return _erro(r.resultado, **extra)
    avisado = regras.avisar_divida(contexto, r.divida_id or "", operador.id)
    divida = contexto.compensacoes.obter(r.divida_id or "")
    return RegistroOut(resultado=r.resultado, compensacao=regras.saida(divida), avisado=avisado)


@router.get("", response_model=Pagina[regras.DividaOut], summary="Compensações")
def listar(
    profissional_id: str | None = None,
    pedido_id: str | None = None,
    status: str | None = Query(None, pattern="^(aberta|quitada|cancelada)$"),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.compensacoes.disponivel():
        return _erro("indisponivel")
    itens, total = contexto.compensacoes.listar(
        profissional_id, pedido_id, status, limite, deslocamento
    )
    return Pagina(
        itens=[regras.saida(d) for d in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/{compensacao_id}/avisar",
    response_model=RegistroOut,
    summary="Reenviar o aviso (sem ele a dívida não é descontada)",
)
def avisar(
    compensacao_id: str,
    operador: Operador = Depends(exigir(Permissao.REGRESSO_PROPOR)),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.compensacoes.disponivel():
        return _erro("indisponivel")
    if contexto.compensacoes.obter(compensacao_id) is None:
        return _erro("nao_encontrada")
    avisado = regras.avisar_divida(contexto, compensacao_id, operador.id)
    divida = contexto.compensacoes.obter(compensacao_id)
    return RegistroOut(resultado="ok", compensacao=regras.saida(divida), avisado=avisado)


@router.post(
    "/{compensacao_id}/cancelar",
    response_model=CancelamentoOut,
    summary="Contestação aceita: cancelar e devolver ao profissional o que foi descontado",
)
def cancelar(
    compensacao_id: str,
    corpo: CancelarCompensacaoIn,
    operador: Operador = Depends(exigir(Permissao.COMPENSACOES_CANCELAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return JSONResponse(422, {"detail": "Explique o motivo.", "codigo": "motivo_invalido"})
    if not contexto.compensacoes.disponivel():
        return _erro("indisponivel")
    r = contexto.compensacoes.cancelar(compensacao_id, operador.id, motivo)  # o banco audita
    if r.resultado not in ("ok", "ja_cancelada"):
        return _erro(r.resultado)
    divida = contexto.compensacoes.obter(compensacao_id)
    avisar_partes(
        contexto,
        Evento.COMPENSACAO_CANCELADA,
        (divida.profissional_id,),
        pedido_id=divida.pedido_id,
        chave=f"compensacao:{divida.id}:cancelada",
        corpo="A compensação foi cancelada. O que já tinha sido descontado "
        f"({reais(r.devolvido_centavos)} agora) voltou ao seu saldo liberado.",
        dados={"compensacao_id": divida.id},
    )
    return CancelamentoOut(
        resultado=r.resultado,
        devolvido_centavos=r.devolvido_centavos,
        compensacao=regras.saida(divida),
    )


# --- regresso (17.4) ------------------------------------------------------------------------------


class ProporRegressoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pedido_id: str = Field(max_length=64)
    referencia: UUID = Field(
        description="Fato que gerou o regresso (ex.: id do chamado). Uma proposta viva por fato."
    )
    valor_centavos: int = Field(gt=0, strict=True)
    motivo: str = Field(min_length=10, max_length=1000, description="O profissional lê.")


class RecusarRegressoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=1000)


class PropostaOut(BaseModel):
    id: str
    pedido_id: str
    profissional_id: str
    referencia: str
    valor_centavos: int
    motivo: str
    status: str = Field(description="proposta | aprovada | recusada")
    proposta_por: str
    proposta_em: datetime
    decidida_por: str | None = None
    decidida_em: datetime | None = None
    motivo_decisao: str | None = None
    compensacao_id: str | None = None


class PropostaResultadoOut(BaseModel):
    resultado: str = Field(description="ok | ja_proposta | ja_recusada")
    proposta: PropostaOut


class AprovacaoRegressoOut(BaseModel):
    resultado: str = Field(description="ok | ja_aprovada")
    proposta: PropostaOut
    compensacao: regras.DividaOut
    avisado: bool


def _proposta_out(p: Proposta) -> PropostaOut:
    campos = {k: getattr(p, k) for k in PropostaOut.model_fields if k != "compensacao_id"}
    return PropostaOut(**campos, compensacao_id=p.divida_id)


@router.post(
    "/regressos",
    response_model=PropostaResultadoOut,
    status_code=201,
    summary="Propor um regresso (outra pessoa aprova)",
)
def propor_regresso(
    corpo: ProporRegressoIn,
    response: Response,
    operador: Operador = Depends(exigir(Permissao.REGRESSO_PROPOR)),
    contexto: Contexto = Depends(obter_contexto),
):
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return JSONResponse(422, {"detail": "Explique o motivo.", "codigo": "motivo_invalido"})
    if not contexto.compensacoes.regresso_disponivel():
        return _erro("indisponivel")
    r = contexto.compensacoes.propor_regresso(  # o banco audita
        corpo.pedido_id, str(corpo.referencia), corpo.valor_centavos, motivo, operador.id
    )
    if r.resultado not in ("ok", "ja_proposta"):
        return _erro(r.resultado)
    if r.resultado == "ja_proposta":
        response.status_code = 200
    proposta = contexto.compensacoes.proposta(r.proposta_id or "")
    return PropostaResultadoOut(resultado=r.resultado, proposta=_proposta_out(proposta))


@router.get("/regressos", response_model=Pagina[PropostaOut], summary="Propostas de regresso")
def listar_regressos(
    status: str | None = Query(None, pattern="^(proposta|aprovada|recusada)$"),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.REGRESSO_PROPOR)),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.compensacoes.regresso_disponivel():
        return _erro("indisponivel")
    itens, total = contexto.compensacoes.propostas(status, limite, deslocamento)
    return Pagina(
        itens=[_proposta_out(p) for p in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/regressos/{proposta_id}/aprovacao",
    response_model=AprovacaoRegressoOut,
    summary="Aprovar o regresso: registra a dívida e a ordem de estorno",
)
def aprovar_regresso(
    proposta_id: str,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.REGRESSO_APROVAR)),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.compensacoes.regresso_disponivel():
        return _erro("indisponivel")
    proposta = contexto.compensacoes.proposta(proposta_id)
    if proposta is None:
        return _erro("proposta_nao_encontrada")
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is None:
        return _erro("indisponivel")
    travar = getattr(contexto.pedidos, "travar", None)
    with contexto.transacao():  # dívida e ordem de estorno: tudo ou nada
        if travar is not None:  # mesma ordem de travas dos outros fluxos: pedido, contrato
            travar(proposta.pedido_id)
        r = contexto.compensacoes.aprovar_regresso(proposta.id, operador.id)
        if r.resultado == "ok":
            servico.ordenar_estorno_compensado(
                contexto, proposta.pedido_id, proposta.valor_centavos, r.divida_id or ""
            )
    if r.resultado not in ("ok", "ja_aprovada"):
        if r.resultado == "nao_encontrada":
            return _erro("proposta_nao_encontrada")
        extra = {"maximo_centavos": r.maximo_centavos} if r.resultado == "acima_do_devido" else {}
        return _erro(r.resultado, **extra)
    avisado = regras.avisar_divida(contexto, r.divida_id or "", operador.id)
    return AprovacaoRegressoOut(
        resultado=r.resultado,
        proposta=_proposta_out(contexto.compensacoes.proposta(proposta.id)),
        compensacao=regras.saida(contexto.compensacoes.obter(r.divida_id or "")),
        avisado=avisado,
    )


@router.post(
    "/regressos/{proposta_id}/recusa",
    response_model=PropostaResultadoOut,
    summary="Recusar o regresso",
)
def recusar_regresso(
    proposta_id: str,
    corpo: RecusarRegressoIn,
    operador: Operador = Depends(exigir(Permissao.REGRESSO_APROVAR)),
    contexto: Contexto = Depends(obter_contexto),
):
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return JSONResponse(422, {"detail": "Explique o motivo.", "codigo": "motivo_invalido"})
    if not contexto.compensacoes.regresso_disponivel():
        return _erro("indisponivel")
    resultado = contexto.compensacoes.recusar_regresso(proposta_id, operador.id, motivo)
    if resultado not in ("ok", "ja_recusada"):
        return _erro("proposta_nao_encontrada" if resultado == "nao_encontrada" else resultado)
    proposta = contexto.compensacoes.proposta(proposta_id)
    return PropostaResultadoOut(resultado=resultado, proposta=_proposta_out(proposta))
