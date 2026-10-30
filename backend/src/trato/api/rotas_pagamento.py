"""Rotas de pagamento (F4.10): cobrança, aditivo e decisão da disputa com efeito no dinheiro.

Arquivo próprio para não mexer nas rotas de pedido. Ligue com `instalar_pagamento`.
O app só pede e mostra: quem decide o dinheiro é `pagamentos/orquestrador.py`.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato import disputas
from trato.api.admin.contexto import Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.servicos import ator_de, carregar_pedido
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import Aditivo, CobrancaLocal
from trato.pagamentos.orquestrador import ErroFluxo, ServicoPagamento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, DecisaoDisputa, Estado, ResultadoDisputa

router = APIRouter(prefix="/v1/pedidos", tags=["pagamento"])


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CobrarIn(_Entrada):
    meio: MeioPagamento


class CobrancaOut(BaseModel):
    id: str
    pedido_id: str
    aditivo_id: str | None
    valor_centavos: int
    meio: str
    status: str = Field(
        description="`aguardando` até o webhook assinado; o app não mostra pago antes."
    )
    instrucao: str | None = Field(None, description="Pix copia e cola ou segredo do cartão.")
    criada_em: datetime


class AditivoIn(_Entrada):
    descricao: str = Field(min_length=1)
    valor_centavos: int = Field(gt=0)


class AprovarAditivoIn(_Entrada):
    meio: MeioPagamento


class AditivoOut(BaseModel):
    id: str
    pedido_id: str
    descricao: str
    valor_centavos: int
    estado: str


class AditivoAprovadoOut(BaseModel):
    aditivo: AditivoOut
    cobranca: CobrancaOut


class DecisaoIn(_Entrada):
    resultado: ResultadoDisputa
    justificativa: str = Field(min_length=3, max_length=2000)
    percentual_cliente_bps: int | None = None
    valor_cliente_centavos: int | None = None


class DecisaoOut(BaseModel):
    estado_disputa: str
    estado_pedido: str
    para_profissional_centavos: int | None
    para_cliente_centavos: int | None
    retido_centavos: int | None


def servico_de(request: Request) -> ServicoPagamento:
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is None:
        raise HTTPException(503, "Pagamento ainda não configurado.")
    return servico


Servico = Annotated[ServicoPagamento, Depends(servico_de)]


def _cobranca_out(c: CobrancaLocal) -> CobrancaOut:
    return CobrancaOut(
        id=c.id,
        pedido_id=c.pedido_id,
        aditivo_id=c.aditivo_id,
        valor_centavos=c.valor_centavos,
        meio=c.meio.value,
        status=c.status.value,
        instrucao=c.instrucao,
        criada_em=c.criada_em,
    )


def _aditivo_out(a: Aditivo) -> AditivoOut:
    return AditivoOut(
        id=a.id,
        pedido_id=a.pedido_id,
        descricao=a.descricao,
        valor_centavos=a.valor_centavos,
        estado=a.estado.value,
    )


@router.post(
    "/{pedido_id}/cobranca",
    response_model=CobrancaOut,
    status_code=201,
    summary="Criar a cobrança do pedido (Pix ou cartão)",
)
def criar_cobranca(
    pedido_id: str,
    corpo: CobrarIn,
    servico: Servico,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> CobrancaOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.estado is not Estado.ORCAMENTO_ACEITO:
        raise ErroFluxo("O pedido não está esperando pagamento.")
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    if contrato is None:
        raise ErroFluxo("Pedido sem contrato.", 409)
    cobranca = servico.cobrar(contexto, pedido, contrato.valor_centavos, corpo.meio)
    return _cobranca_out(cobranca)


@router.get(
    "/{pedido_id}/cobrancas", response_model=list[CobrancaOut], summary="Cobranças do pedido"
)
def listar_cobrancas(
    pedido_id: str,
    request: Request,
    servico: Servico,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[CobrancaOut]:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="cobrancas",
    )
    return [_cobranca_out(c) for c in servico.cobrancas.do_pedido(pedido.id)]


@router.post(
    "/{pedido_id}/aditivos",
    response_model=AditivoOut,
    status_code=201,
    summary="Profissional propõe aditivo (nada é cobrado ainda)",
)
def propor_aditivo(
    pedido_id: str,
    corpo: AditivoIn,
    servico: Servico,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AditivoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.profissional_id != usuario.id:
        raise HTTPException(403, "Só o profissional contratado neste pedido pode propor aditivo.")
    return _aditivo_out(
        servico.propor_aditivo(contexto, pedido, corpo.descricao, corpo.valor_centavos)
    )


@router.post(
    "/{pedido_id}/aditivos/{aditivo_id}/aprovacao",
    response_model=AditivoAprovadoOut,
    summary="Cliente aprova o aditivo; a cobrança é criada",
)
def aprovar_aditivo(
    pedido_id: str,
    aditivo_id: str,
    corpo: AprovarAditivoIn,
    servico: Servico,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> AditivoAprovadoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    aditivo, cobranca = servico.aprovar_aditivo(contexto, pedido, aditivo_id, corpo.meio)
    return AditivoAprovadoOut(aditivo=_aditivo_out(aditivo), cobranca=_cobranca_out(cobranca))


@router.get("/{pedido_id}/aditivos", response_model=list[AditivoOut], summary="Aditivos do pedido")
def listar_aditivos(
    pedido_id: str,
    request: Request,
    servico: Servico,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[AditivoOut]:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="aditivos",
    )
    return [_aditivo_out(a) for a in servico.aditivos.do_pedido(pedido.id)]


@router.post(
    "/{pedido_id}/disputa/decisao",
    response_model=DecisaoOut,
    summary="Equipe decide a disputa (move o dinheiro)",
    description=(
        "Só a equipe com a permissão `disputas_decidir` (mediador, líder de suporte, "
        "administrador). Divide o valor congelado, pede o estorno ao provedor, espelha no ledger "
        "e reparte a parte do profissional com a taxa do contrato. A alçada é a de quem decide "
        "(`equipe.alcada_centavos`, vazia = 0); acima dela fica aguardando segunda pessoa "
        "(`/v1/admin/disputas/{id}/aprovacao`). A decisão entra na auditoria."
    ),
)
def decidir_disputa(
    pedido_id: str,
    corpo: DecisaoIn,
    servico: Servico,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    contexto: Contexto = Depends(obter_contexto),
) -> DecisaoOut:
    usuario = operador.usuario
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.DISPUTAS_DECIDIR,),
        consulta="disputa_decisao",
    )
    disputa = contexto.disputas.obter(pedido.id)
    if disputa is None:
        raise HTTPException(404, "Este pedido não tem disputa.")
    agora = contexto.agora()
    decisao = disputas.Decisao(
        disputas.Resultado(corpo.resultado.value),
        corpo.percentual_cliente_bps,
        corpo.valor_cliente_centavos,
    )
    alcada = operador.membro.alcada_centavos or 0
    nova = disputa.decidir(disputas.Ator.ANALISTA, usuario.id, decisao, agora, alcada)
    admin = obter_admin(request, contexto)
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="financeiro.disputa_decisao",
        entidade="pedidos",
        entidade_id=pedido.id,
        depois={
            "resultado": decisao.resultado.value,
            "valor_congelado_centavos": nova.valor_congelado,
            "alcada_centavos": alcada,
            "efetivada": nova.divisao is not None,
        },
        motivo=corpo.justificativa,
    )
    if nova.divisao is None:  # aguardando segunda pessoa
        contexto.disputas.salvar(pedido.id, nova)
        return DecisaoOut(
            estado_disputa=nova.estado.value,
            estado_pedido=pedido.estado.value,
            para_profissional_centavos=None,
            para_cliente_centavos=None,
            retido_centavos=None,
        )

    transicao = estados.transicionar(
        pedido,
        Acao.DECIDIR_DISPUTA,
        ator_de(usuario),
        agora,
        DecisaoDisputa(corpo.resultado, corpo.justificativa),
    )
    divisao = nova.divisao
    servico.aplicar_dinheiro(
        contexto,
        transicao.pedido,
        devolver_ao_cliente=divisao.para_cliente,
        repartir=transicao.pedido.estado is Estado.CONCLUIDO,
    )
    contexto.disputas.salvar(pedido.id, nova)
    contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    return DecisaoOut(
        estado_disputa=nova.estado.value,
        estado_pedido=transicao.pedido.estado.value,
        para_profissional_centavos=divisao.para_profissional,
        para_cliente_centavos=divisao.para_cliente,
        retido_centavos=divisao.retido,
    )


def _erro_fluxo(request: Request, erro: Exception) -> JSONResponse:
    status = erro.status if isinstance(erro, ErroFluxo) else 409
    return JSONResponse({"detail": str(erro)}, status_code=status)


def instalar_pagamento(app: FastAPI, contexto: Contexto, servico: ServicoPagamento) -> FastAPI:
    """Liga o serviço de pagamento: rotas, webhooks (no contexto) e ganchos de transição."""
    servico.ligar(contexto)
    app.state.servico_pagamento = servico
    app.include_router(router)
    app.add_exception_handler(ErroFluxo, _erro_fluxo)
    return app
