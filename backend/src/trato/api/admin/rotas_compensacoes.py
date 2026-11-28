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
from trato.api.admin.papeis import Permissao, pode
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro.extrato_profissional import reais
from trato.financeiro.ledger import reembolso_retido_direto
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


class ReduzirCompensacaoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contestacao_id: str = Field(max_length=64, description="Contestação que ALTEROU para menos.")
    novo_valor_centavos: int = Field(gt=0, strict=True)
    motivo: str = Field(min_length=10, max_length=1000)


class ReducaoOut(BaseModel):
    resultado: str = Field(description="ok | ja_reduzida")
    devolvido_centavos: int = Field(description="Voltou ao profissional nesta redução.")
    compensacao: regras.DividaAdminOut


class RegistroOut(BaseModel):
    resultado: str = Field(description="ok | ja_registrada")
    compensacao: regras.DividaAdminOut
    avisado: bool


class CancelamentoOut(BaseModel):
    resultado: str = Field(description="ok | ja_cancelada")
    devolvido_centavos: int
    compensacao: regras.DividaAdminOut


_ERROS = {
    "conflito": (409, "Esta decisão já tem compensação com outro valor."),
    "acima_do_devido": (422, "O valor passa do que pode ser compensado."),
    "origem_nao_decidida": (409, "Não há decisão final que permita compensar."),
    "decisao_substituida": (409, "A decisão foi mudada por contestação: informe a contestação."),
    "contrato_nao_encontrado": (404, "Pedido sem contrato."),
    "analista_invalido": (403, "Só alguém ativo da equipe pode fazer isto."),
    "nao_encontrada": (404, "Compensação não encontrada."),
    "indisponivel": (503, "A compensação ainda não está disponível."),
    "estorno_ja_ordenado": (
        409,
        "Este pedido já teve uma compensação cancelada com estorno ordenado ao cliente. "
        "Registrar de novo devolveria o dinheiro outra vez: nada foi gravado.",
    ),
    "reembolso_direto_na_disputa": (
        409,
        "Parte retida desta disputa foi devolvida depois de uma liberação parcial e o banco "
        "ainda não a desconta do teto: registrar agora poderia devolver duas vezes. Nada foi "
        "gravado.",
    ),
    "ja_registrada": (409, "Esta referência já virou compensação."),
    "ja_aprovada": (409, "Esta proposta já foi aprovada."),
    "ja_recusada": (409, "Esta proposta já foi recusada."),
    "mesma_pessoa": (403, "Quem propôs não pode aprovar."),
    "proponente_invalido": (409, "Quem propôs não está mais apto: proponha de novo."),
    "proposta_nao_encontrada": (404, "Proposta não encontrada."),
}


_ERROS_REDUCAO = {
    "conflito": (409, "Esta contestação já foi usada para outro valor ou outra compensação."),
    "analista_invalido": (403, "Só líder de suporte ou administrador reduz compensação."),
    "nao_encontrada": (404, "Compensação não encontrada."),
    "ja_cancelada": (409, "Esta compensação foi cancelada: não há o que reduzir."),
    "contestacao_invalida": (422, "Esta contestação não permite reduzir esta compensação."),
    "decisao_substituida": (409, "Uma contestação posterior reduziu mais: use a mais recente."),
    "valor_invalido": (422, "O novo valor precisa ser menor que o atual e caber na decisão."),
    "indisponivel": (503, "A redução ainda não está disponível."),
}


def _erro(codigo: str, **extra: int) -> JSONResponse:
    status, mensagem = _ERROS.get(codigo, _ERROS["indisponivel"])
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo} | extra)


class _EstornoJaOrdenado(Exception):
    """Desfaz a transação do registro (dívida e livro)."""


class _ReembolsoDiretoNaDisputa(Exception):
    """Desfaz a transação do registro (dívida e livro)."""


def _ordenar_estorno(  # type: ignore[no-untyped-def]
    contexto: Contexto, servico, pedido_id: str, valor: int, divida_id: str
) -> None:
    """ÚNICO caminho do painel para estornar por compensação (decisão ou regresso). Chamar na
    transação do registro, com o pedido travado, DEPOIS de a função do banco criar a dívida:
    ela trava o contrato, a mesma trava do cancelamento, então um cancelamento simultâneo já é
    visto aqui. Pedido com dívida cancelada que já teve estorno ordenado não ordena outro: o
    dinheiro daquela não volta, e o teto do banco ignora as canceladas."""
    canceladas, _ = contexto.compensacoes.listar(
        pedido_id=pedido_id, status="cancelada", limite=500
    )
    prefixos = tuple(f"comp/{d.id}/" for d in canceladas)
    if prefixos and any(o.chave.startswith(prefixos) for o in servico.ordens.do_pedido(pedido_id)):
        raise _EstornoJaOrdenado
    servico.ordenar_estorno_compensado(contexto, pedido_id, valor, divida_id)


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
    try:
        with contexto.transacao():  # dívida e ordem de estorno: tudo ou nada
            if travar is not None:  # mesma ordem de travas dos outros fluxos: pedido, contrato
                travar(pedido.id)
            r = contexto.compensacoes.registrar_disputa(
                pedido.id, corpo.contestacao_id, corpo.valor_centavos, motivo, operador.id
            )
            if r.resultado == "ok":
                disputa = contexto.disputas.obter(pedido.id)
                if (
                    disputa is not None
                    and reembolso_retido_direto(
                        contexto.ledger.lancamentos(pedido.id), pedido.id, disputa.aberta_em
                    )
                    and not contexto.compensacoes.conta_reembolso_retido()
                ):
                    # Sem a 20261128040000 o teto do banco não enxerga o reembolso direto:
                    # registrar poderia devolver duas vezes. Desfaz tudo.
                    raise _ReembolsoDiretoNaDisputa
                _ordenar_estorno(
                    contexto, servico, pedido.id, corpo.valor_centavos, r.divida_id or ""
                )
    except _EstornoJaOrdenado:
        return _erro("estorno_ja_ordenado")
    except _ReembolsoDiretoNaDisputa:
        return _erro("reembolso_direto_na_disputa")
    if r.resultado not in ("ok", "ja_registrada"):
        extra = {"maximo_centavos": r.maximo_centavos} if r.resultado == "acima_do_devido" else {}
        return _erro(r.resultado, **extra)
    avisado = regras.avisar_divida(contexto, r.divida_id or "", operador.id)
    divida = contexto.compensacoes.obter(r.divida_id or "")
    return RegistroOut(
        resultado=r.resultado, compensacao=_para_o_painel(operador, divida), avisado=avisado
    )


def _para_o_painel(operador: Operador, divida) -> regras.DividaAdminOut:  # type: ignore[no-untyped-def]
    # Reduzir e cancelar exigem a mesma permissão.
    return regras.saida_admin(divida, pode(operador.membro.papel, Permissao.COMPENSACOES_CANCELAR))


@router.get("", response_model=Pagina[regras.DividaAdminOut], summary="Compensações")
def listar(
    profissional_id: str | None = None,
    pedido_id: str | None = None,
    status: str | None = Query(None, pattern="^(aberta|quitada|cancelada)$"),
    revisao_pendente: bool = Query(
        False, description="Só as com decisão posterior mais baixa ainda sem tratamento."
    ),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.compensacoes.disponivel():
        return _erro("indisponivel")
    filtro = {"revisao_pendente": True} if revisao_pendente else {}
    itens, total = contexto.compensacoes.listar(
        profissional_id, pedido_id, status, limite, deslocamento, **filtro
    )
    return Pagina(
        itens=[_para_o_painel(operador, d) for d in itens],
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
    return RegistroOut(
        resultado="ok", compensacao=_para_o_painel(operador, divida), avisado=avisado
    )


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
        compensacao=_para_o_painel(operador, divida),
    )


@router.post(
    "/{compensacao_id}/reduzir",
    response_model=ReducaoOut,
    summary="Contestação reduziu a decisão: reduzir a dívida, sem novo estorno",
)
def reduzir(
    compensacao_id: str,
    corpo: ReduzirCompensacaoIn,
    operador: Operador = Depends(exigir(Permissao.COMPENSACOES_CANCELAR)),
    contexto: Contexto = Depends(obter_contexto),
):
    """Nada vai nem volta para o cliente: o Trato absorve só a diferença e o profissional segue
    devendo o novo valor. O banco audita."""
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return JSONResponse(422, {"detail": "Explique o motivo.", "codigo": "motivo_invalido"})
    if not contexto.compensacoes.disponivel():
        return _erro_reducao("indisponivel")
    r = contexto.compensacoes.reduzir(
        compensacao_id, corpo.contestacao_id, corpo.novo_valor_centavos, motivo, operador.id
    )
    if r.resultado not in ("ok", "ja_reduzida"):
        return _erro_reducao(r.resultado)
    divida = contexto.compensacoes.obter(compensacao_id)
    avisar_partes(
        contexto,
        Evento.COMPENSACAO_REDUZIDA,
        (divida.profissional_id,),
        pedido_id=divida.pedido_id,
        chave=f"compensacao:{divida.id}:reduzida:{corpo.contestacao_id}",
        corpo=f"A compensação foi reduzida para {reais(corpo.novo_valor_centavos)}. "
        f"Voltaram ao seu saldo liberado {reais(r.devolvido_centavos)}.",
        dados={"compensacao_id": divida.id},
    )
    return ReducaoOut(
        resultado=r.resultado,
        devolvido_centavos=r.devolvido_centavos,
        compensacao=_para_o_painel(operador, divida),
    )


def _erro_reducao(codigo: str) -> JSONResponse:
    status, mensagem = _ERROS_REDUCAO.get(codigo, _ERROS_REDUCAO["indisponivel"])
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo})


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
    compensacao: regras.DividaAdminOut
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
    try:
        with contexto.transacao():  # dívida e ordem de estorno: tudo ou nada
            if travar is not None:  # mesma ordem de travas dos outros fluxos: pedido, contrato
                travar(proposta.pedido_id)
            r = contexto.compensacoes.aprovar_regresso(proposta.id, operador.id)
            if r.resultado == "ok":
                _ordenar_estorno(
                    contexto, servico, proposta.pedido_id, proposta.valor_centavos,
                    r.divida_id or "",
                )  # fmt: skip
    except _EstornoJaOrdenado:
        return _erro("estorno_ja_ordenado")
    if r.resultado not in ("ok", "ja_aprovada"):
        if r.resultado == "nao_encontrada":
            return _erro("proposta_nao_encontrada")
        extra = {"maximo_centavos": r.maximo_centavos} if r.resultado == "acima_do_devido" else {}
        return _erro(r.resultado, **extra)
    avisado = regras.avisar_divida(contexto, r.divida_id or "", operador.id)
    return AprovacaoRegressoOut(
        resultado=r.resultado,
        proposta=_proposta_out(contexto.compensacoes.proposta(proposta.id)),
        compensacao=_para_o_painel(operador, contexto.compensacoes.obter(r.divida_id or "")),
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
