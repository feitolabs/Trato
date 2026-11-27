"""Pedidos de titular LGPD e revisão de decisão automatizada no painel (14.9 e 14.10).

Permissões:
- `lgpd_pedidos_gerenciar` (`dpo`, `administrador`): todos os pedidos de titular.
- `lgpd_revisao_automatizada` (`dpo`, `seguranca`, `administrador`): `revisao_decisao_automatizada`.
Auditoria grava apenas metadados (sem texto livre nem dados pessoais). Sem tabela: 503 limpo.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao, pode
from trato.api.contexto import Contexto, obter_contexto
from trato.api.rotas_lgpd_titular import DecisaoAutomatizada, TipoPedidoTitular
from trato.persistencia.lgpd_titular import PedidoTitularLgpd

router = APIRouter(prefix="/v1/admin/lgpd/pedidos", tags=["admin: pedidos de titular LGPD"])

StatusPedido = Literal[
    "aberto",
    "em_analise",
    "aguardando_titular",
    "atendido",
    "atendido_parcial",
    "negado",
]
StatusResposta = Literal["atendido", "atendido_parcial", "negado"]
TIPO_AUTOMATIZADA = "revisao_decisao_automatizada"


class ResponderPedidoTitularIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    status: StatusResposta
    resposta: str = Field(min_length=10, max_length=4000)
    motivo_nao_atendido: str | None = Field(default=None, min_length=10, max_length=2000)
    criterios_informados: str | None = Field(default=None, min_length=10, max_length=2000)


class PedidoTitularAdminOut(BaseModel):
    id: str
    protocolo: str
    usuario_id: str | None = None
    contato: str | None = None
    tipo: TipoPedidoTitular
    decisao_automatizada: DecisaoAutomatizada | None = None
    referencia_tipo: str | None = None
    referencia_id: str | None = None
    descricao: str
    canal: str
    exclusao_id: str | None = None
    aberto_em: datetime
    responder_ate: datetime
    status: StatusPedido
    analista_id: str | None = None
    resposta: str | None = None
    motivo_nao_atendido: str | None = None
    criterios_informados: str | None = None
    respondido_em: datetime | None = None


def _out(p: PedidoTitularLgpd) -> PedidoTitularAdminOut:
    return PedidoTitularAdminOut(
        id=p.id,
        protocolo=p.protocolo,
        usuario_id=p.usuario_id,
        contato=p.contato,
        tipo=p.tipo,  # type: ignore[arg-type]
        decisao_automatizada=p.decisao_automatizada,  # type: ignore[arg-type]
        referencia_tipo=p.referencia_tipo,
        referencia_id=p.referencia_id,
        descricao=p.descricao,
        canal=p.canal,
        exclusao_id=p.exclusao_id,
        aberto_em=p.aberto_em,
        responder_ate=p.responder_ate,
        status=p.status,  # type: ignore[arg-type]
        analista_id=p.analista_id,
        resposta=p.resposta,
        motivo_nao_atendido=p.motivo_nao_atendido,
        criterios_informados=p.criterios_informados,
        respondido_em=p.respondido_em,
    )


def _exigir_tabela(contexto: Contexto) -> None:
    if not contexto.lgpd_titular.disponivel():
        raise HTTPException(
            503,
            "Pedidos de titular LGPD indisponíveis: a tabela ainda não existe no banco de dados.",
        )


def _exigir_alcance(operador: Operador, tipo: str) -> None:
    if tipo != TIPO_AUTOMATIZADA and not pode(
        operador.membro.papel, Permissao.LGPD_PEDIDOS_GERENCIAR
    ):
        raise HTTPException(
            403, "Apenas DPO ou administrador pode tratar pedidos de titular deste tipo."
        )


@router.get(
    "",
    response_model=Pagina[PedidoTitularAdminOut],
    summary="Listar pedidos de titular LGPD",
)
def listar_pedidos_titular(
    status: StatusPedido | None = Query(None),
    tipo: TipoPedidoTitular | None = Query(None),
    usuario_id: str | None = Query(None),
    limite: int = Query(50, ge=1, le=200),
    deslocamento: int = Query(0, ge=0),
    operador: Operador = Depends(exigir(Permissao.LGPD_REVISAO_AUTOMATIZADA)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[PedidoTitularAdminOut]:
    _exigir_tabela(contexto)
    tipo_efetivo: str | None = tipo
    if not pode(operador.membro.papel, Permissao.LGPD_PEDIDOS_GERENCIAR):
        if tipo is not None and tipo != TIPO_AUTOMATIZADA:
            raise HTTPException(
                403, "Seu papel só pode consultar pedidos de `revisao_decisao_automatizada`."
            )
        tipo_efetivo = TIPO_AUTOMATIZADA
    itens, total = contexto.lgpd_titular.listar_admin(
        status, tipo_efetivo, usuario_id, limite, deslocamento
    )
    return Pagina(
        itens=[_out(p) for p in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/{pedido_id}/analisar",
    response_model=PedidoTitularAdminOut,
    summary="Passar pedido de titular LGPD para em_analise",
)
def analisar_pedido_titular(
    pedido_id: str,
    operador: Operador = Depends(exigir(Permissao.LGPD_REVISAO_AUTOMATIZADA)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> PedidoTitularAdminOut:
    _exigir_tabela(contexto)
    atual = contexto.lgpd_titular.obter(pedido_id)
    if atual is None:
        raise HTTPException(404, "Pedido de titular não encontrado.")
    _exigir_alcance(operador, atual.tipo)
    pedido, cod = contexto.lgpd_titular.iniciar_analise(pedido_id, operador.id)
    if cod == "nao_encontrado" or pedido is None:
        raise HTTPException(404, "Pedido de titular não encontrado.")
    if cod == "ja_respondido":
        raise HTTPException(409, "Este pedido de titular já foi respondido.")
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="lgpd.pedido_titular_em_analise",
            entidade="lgpd_pedidos_titular",
            entidade_id=pedido.id,
            depois={"status": "em_analise", "tipo": pedido.tipo, "protocolo": pedido.protocolo},
            motivo=f"Análise iniciada para pedido LGPD {pedido.protocolo}",
        )
    return _out(pedido)


@router.post(
    "/{pedido_id}/responder",
    response_model=PedidoTitularAdminOut,
    summary="Responder e encerrar pedido de titular LGPD",
)
def responder_pedido_titular(
    pedido_id: str,
    corpo: ResponderPedidoTitularIn,
    operador: Operador = Depends(exigir(Permissao.LGPD_REVISAO_AUTOMATIZADA)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> PedidoTitularAdminOut:
    _exigir_tabela(contexto)
    atual = contexto.lgpd_titular.obter(pedido_id)
    if atual is None:
        raise HTTPException(404, "Pedido de titular não encontrado.")
    _exigir_alcance(operador, atual.tipo)
    if corpo.status in ("atendido_parcial", "negado") and not corpo.motivo_nao_atendido:
        raise HTTPException(
            422, "Informe `motivo_nao_atendido` para resposta parcial ou negada (Termos 14.9)."
        )
    if atual.tipo == TIPO_AUTOMATIZADA and not corpo.criterios_informados:
        raise HTTPException(
            422, "Informe `criterios_informados` na revisão de decisão automatizada (Termos 14.10)."
        )
    pedido, cod = contexto.lgpd_titular.responder(
        pedido_id,
        corpo.status,
        operador.id,
        corpo.resposta,
        contexto.agora(),
        corpo.motivo_nao_atendido,
        corpo.criterios_informados,
    )
    if cod == "nao_encontrado" or pedido is None:
        raise HTTPException(404, "Pedido de titular não encontrado.")
    if cod == "ja_respondido":
        raise HTTPException(409, "Este pedido de titular já foi respondido.")
    if cod == "ok":
        # Sem texto livre ou dados pessoais na trilha de auditoria.
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="lgpd.pedido_titular_respondido",
            entidade="lgpd_pedidos_titular",
            entidade_id=pedido.id,
            depois={"status": pedido.status, "tipo": pedido.tipo, "protocolo": pedido.protocolo},
            motivo=f"Resposta registrada para pedido LGPD {pedido.protocolo}",
        )
    return _out(pedido)
