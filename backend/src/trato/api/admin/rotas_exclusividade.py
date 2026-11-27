"""Falha do Trato numa exclusividade do cliente (Termos 13.6): o analista devolve os Tratinhos."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, obter_contexto
from trato.notificacoes.eventos import Evento

router = APIRouter(prefix="/v1/admin/exclusividades", tags=["admin: exclusividade"])


class FalhaTratoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=1000)


class FalhaTratoOut(BaseModel):
    resultado: str
    moedas_devolvidas: int


def _erro(status: int, codigo: str, mensagem: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo})


class ExclusividadeAdminOut(BaseModel):
    id: str
    pedido_id: str
    cliente_id: str
    cliente_nome: str | None = None
    profissional_id: str
    profissional_nome: str | None = None
    orcamento_id: str | None = None
    status: str
    moedas: int
    estornada: bool
    estornada_em: datetime | None = None
    criada_em: datetime
    expira_em: datetime | None = None
    encerrada_em: datetime | None = None
    motivo_encerramento: str | None = None


@router.get(
    "",
    response_model=Pagina[ExclusividadeAdminOut],
    summary="Exclusividades pagas pelo cliente",
)
def listar(
    pedido_id: str | None = None,
    cliente_id: str | None = None,
    status: str | None = Query(
        None, pattern="^(ativa|concluida|cancelada|expirada_sem_contratacao)$"
    ),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.exclusividades.cliente_disponivel():
        return _erro(503, "indisponivel", "A exclusividade do cliente não está disponível.")
    itens, total = contexto.exclusividades.listar_cliente(
        pedido_id, cliente_id, status, limite, deslocamento
    )
    ids = list({u for i in itens for u in (i.cliente_id, i.profissional_id)})
    achados = admin.usuarios.nomes(ids) if admin.usuarios is not None and ids else {}
    nomes = {str(k).replace("-", ""): v for k, v in achados.items()}  # com ou sem hífen
    return Pagina(
        itens=[
            ExclusividadeAdminOut(
                id=i.id,
                pedido_id=i.pedido_id,
                cliente_id=i.cliente_id,
                cliente_nome=nomes.get(i.cliente_id.replace("-", "")),
                profissional_id=i.profissional_id,
                profissional_nome=nomes.get(i.profissional_id.replace("-", "")),
                orcamento_id=i.orcamento_id,
                status=i.status,
                moedas=i.moedas_cobradas,
                estornada=i.estornada,
                estornada_em=i.estornada_em,
                criada_em=i.criada_em,
                expira_em=i.expira_em,
                encerrada_em=i.encerrada_em,
                motivo_encerramento=i.motivo_encerramento,
            )
            for i in itens
        ],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/{exclusividade_id}/falha-trato",
    response_model=FalhaTratoOut,
    summary="Registrar falha do Trato e devolver os Tratinhos",
)
def falha_trato(
    exclusividade_id: str,
    corpo: FalhaTratoIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return _erro(422, "motivo_invalido", "Explique o motivo.")
    with contexto.transacao():
        r = contexto.exclusividades.falha_trato(
            exclusividade_id, operador.id, motivo, contexto.agora()
        )
        # No banco a própria função grava a auditoria; em memória, grava aqui.
        if r.resultado == "ok" and not hasattr(contexto.pedidos, "travar"):
            admin.auditoria.registrar(
                ator_id=operador.id,
                acao="estorno.exclusividade_falha_trato",
                entidade="exclusividade",
                entidade_id=exclusividade_id,
                antes={},
                depois={"moedas_devolvidas": r.devolvido},
                motivo=motivo,
            )
    if r.resultado not in ("ok", "ja_devolvida"):
        status = {"nao_encontrada": 404, "analista_invalido": 403, "nao_elegivel": 409}
        return _erro(status.get(r.resultado, 503), r.resultado, f"Não foi possível: {r.resultado}.")
    item = contexto.exclusividades.obter(exclusividade_id)
    if item is not None:
        avisar_partes(
            contexto,
            Evento.EXCLUSIVIDADE_CLIENTE_DEVOLVIDA,
            (item.cliente_id,),
            pedido_id=item.pedido_id,
            chave=f"{item.id}:devolvida",
        )
    return FalhaTratoOut(resultado=r.resultado, moedas_devolvidas=r.devolvido)
