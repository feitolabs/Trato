"""Impedimentos de cadastro e pedidos de retorno de conta no painel (Termos 20.9).

Permissões:
- `conta_retorno_analisar` (`mediador`, `lider_suporte`, `seguranca`, `administrador`):
  listar impedimentos/retornos, passar retorno para `em_analise` e recusar retorno.
- `conta_retorno_aprovar` (`lider_suporte`, `administrador`):
  aprovar retorno (`risco_identificado=false`) e revogar impedimento de cadastro.
Todas as ações são auditadas; sem as tabelas, responde 503 limpo.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.api.medidas import restabelecer_por_retorno
from trato.persistencia.retorno_conta import ImpedimentoCadastro, PedidoRetornoConta

router = APIRouter(prefix="/v1/admin/conta", tags=["admin: retorno e impedimento de conta"])

StatusRetorno = Literal["aberto", "em_analise", "aprovado", "recusado"]


class RevogarImpedimentoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=1000)


class DecidirRetornoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=2000)
    risco_identificado: bool = False


class ImpedimentoAdminOut(BaseModel):
    id: str
    medida_id: str
    tipo_identificador: str
    criado_por: str
    criado_em: datetime
    revogado_em: datetime | None = None
    revogado_por: str | None = None
    motivo_revogacao: str | None = None


class PedidoRetornoAdminOut(BaseModel):
    id: str
    protocolo: str
    usuario_id: str
    medida_id: str
    justificativa_usuario: str
    canal: str
    status: StatusRetorno
    solicitado_em: datetime
    prazo_dias_aplicado: int
    elegivel_a_partir_de: datetime
    analista_id: str | None = None
    decisao_motivo: str | None = None
    risco_identificado: bool
    decidido_em: datetime | None = None


def _imp_out(i: ImpedimentoCadastro) -> ImpedimentoAdminOut:
    return ImpedimentoAdminOut(
        id=i.id,
        medida_id=i.medida_id,
        tipo_identificador=i.tipo_identificador,
        criado_por=i.criado_por,
        criado_em=i.criado_em,
        revogado_em=i.revogado_em,
        revogado_por=i.revogado_por,
        motivo_revogacao=i.motivo_revogacao,
    )


def _ret_out(r: PedidoRetornoConta) -> PedidoRetornoAdminOut:
    return PedidoRetornoAdminOut(
        id=r.id,
        protocolo=r.protocolo,
        usuario_id=r.usuario_id,
        medida_id=r.medida_id,
        justificativa_usuario=r.justificativa_usuario,
        canal=r.canal,
        status=r.status,  # type: ignore[arg-type]
        solicitado_em=r.solicitado_em,
        prazo_dias_aplicado=r.prazo_dias_aplicado,
        elegivel_a_partir_de=r.elegivel_a_partir_de,
        analista_id=r.analista_id,
        decisao_motivo=r.decisao_motivo,
        risco_identificado=r.risco_identificado,
        decidido_em=r.decidido_em,
    )


def _exigir_tabelas(contexto: Contexto) -> None:
    if not contexto.retorno_conta.disponivel():
        raise HTTPException(
            503,
            "Retorno/impedimento indisponível: as tabelas ainda não existem no banco de dados.",
        )


@router.get(
    "/impedimentos",
    response_model=Pagina[ImpedimentoAdminOut],
    summary="Listar impedimentos de novo cadastro",
)
def listar_impedimentos(
    medida_id: str | None = Query(None),
    apenas_ativos: bool = Query(False),
    limite: int = Query(50, ge=1, le=200),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.CONTA_RETORNO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[ImpedimentoAdminOut]:
    _exigir_tabelas(contexto)
    itens, total = contexto.retorno_conta.listar_impedimentos(
        medida_id, apenas_ativos, limite, deslocamento
    )
    return Pagina(
        itens=[_imp_out(i) for i in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/impedimentos/{impedimento_id}/revogar",
    response_model=ImpedimentoAdminOut,
    summary="Revogar impedimento de cadastro (líder de suporte ou administrador)",
)
def revogar_impedimento(
    impedimento_id: str,
    corpo: RevogarImpedimentoIn,
    operador: Operador = Depends(exigir(Permissao.CONTA_RETORNO_APROVAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ImpedimentoAdminOut:
    _exigir_tabelas(contexto)
    imp, cod = contexto.retorno_conta.revogar_impedimento(
        impedimento_id, operador.id, corpo.motivo, contexto.agora()
    )
    if cod == "nao_encontrado" or imp is None:
        raise HTTPException(404, "Impedimento não encontrado.")
    if cod == "ja_revogado":
        raise HTTPException(409, "Este impedimento já foi revogado.")
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="conta.impedimento_revogado",
        entidade="conta_impedimentos_cadastro",
        entidade_id=imp.id,
        depois={"medida_id": imp.medida_id, "tipo_identificador": imp.tipo_identificador},
        motivo=corpo.motivo,
    )
    return _imp_out(imp)


@router.get(
    "/retornos",
    response_model=Pagina[PedidoRetornoAdminOut],
    summary="Listar pedidos de retorno de conta",
)
def listar_retornos(
    status: StatusRetorno | None = Query(None),
    usuario_id: str | None = Query(None),
    limite: int = Query(50, ge=1, le=200),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.CONTA_RETORNO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[PedidoRetornoAdminOut]:
    _exigir_tabelas(contexto)
    itens, total = contexto.retorno_conta.listar_retornos_admin(
        status, usuario_id, limite, deslocamento
    )
    return Pagina(
        itens=[_ret_out(r) for r in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/retornos/{retorno_id}/analisar",
    response_model=PedidoRetornoAdminOut,
    summary="Passar pedido de retorno para em_analise",
)
def analisar_retorno(
    retorno_id: str,
    operador: Operador = Depends(exigir(Permissao.CONTA_RETORNO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> PedidoRetornoAdminOut:
    _exigir_tabelas(contexto)
    ret, cod = contexto.retorno_conta.iniciar_analise_retorno(retorno_id, operador.id)
    if cod == "nao_encontrado" or ret is None:
        raise HTTPException(404, "Pedido de retorno não encontrado.")
    if cod == "ja_decidido":
        raise HTTPException(409, "Este pedido de retorno já foi decidido.")
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="conta.retorno_em_analise",
            entidade="conta_pedidos_retorno",
            entidade_id=ret.id,
            depois={"status": "em_analise", "protocolo": ret.protocolo},
            motivo=f"Análise iniciada para pedido de retorno {ret.protocolo}",
        )
    return _ret_out(ret)


@router.post(
    "/retornos/{retorno_id}/aprovar",
    response_model=PedidoRetornoAdminOut,
    summary="Aprovar pedido de retorno (líder de suporte ou administrador, sem risco)",
)
def aprovar_retorno(
    retorno_id: str,
    corpo: DecidirRetornoIn,
    operador: Operador = Depends(exigir(Permissao.CONTA_RETORNO_APROVAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> PedidoRetornoAdminOut:
    _exigir_tabelas(contexto)
    if corpo.risco_identificado:
        raise HTTPException(
            422, "Não é permitido aprovar pedido de retorno com risco identificado (20.9)."
        )
    ret, cod = contexto.retorno_conta.decidir_retorno(
        retorno_id, "aprovado", operador.id, corpo.motivo, False, contexto.agora()
    )
    if cod == "nao_encontrado" or ret is None:
        raise HTTPException(404, "Pedido de retorno não encontrado.")
    if cod == "ja_decidido":
        raise HTTPException(409, "Este pedido de retorno já foi decidido.")
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="conta.retorno_aprovado",
            entidade="conta_pedidos_retorno",
            entidade_id=ret.id,
            depois={"status": "aprovado", "protocolo": ret.protocolo},
            motivo=corpo.motivo,
        )
    if ret.status == "aprovado":  # também na repetição: a chave não deixa creditar duas vezes
        restabelecer_por_retorno(contexto, ret.medida_id, ret.solicitado_em)
    return _ret_out(ret)


@router.post(
    "/retornos/{retorno_id}/recusar",
    response_model=PedidoRetornoAdminOut,
    summary="Recusar pedido de retorno",
)
def recusar_retorno(
    retorno_id: str,
    corpo: DecidirRetornoIn,
    operador: Operador = Depends(exigir(Permissao.CONTA_RETORNO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> PedidoRetornoAdminOut:
    _exigir_tabelas(contexto)
    ret, cod = contexto.retorno_conta.decidir_retorno(
        retorno_id,
        "recusado",
        operador.id,
        corpo.motivo,
        corpo.risco_identificado,
        contexto.agora(),
    )
    if cod == "nao_encontrado" or ret is None:
        raise HTTPException(404, "Pedido de retorno não encontrado.")
    if cod == "ja_decidido":
        raise HTTPException(409, "Este pedido de retorno já foi decidido.")
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="conta.retorno_recusado",
            entidade="conta_pedidos_retorno",
            entidade_id=ret.id,
            depois={
                "status": "recusado",
                "protocolo": ret.protocolo,
                "risco_identificado": corpo.risco_identificado,
            },
            motivo=corpo.motivo,
        )
    return _ret_out(ret)
