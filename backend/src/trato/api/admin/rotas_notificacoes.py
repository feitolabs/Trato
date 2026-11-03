"""Rotas de Comunicação e push (RF-COM-01 a RF-COM-04).

Campanha operacional (andamento de serviço e avisos de conta) é separada de marketing; marketing
respeita a preferência de cada usuário. Antes de enviar, a tela pede a estimativa de destinatários.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/notificacoes", tags=["admin: notificacoes e campanhas"])

_SEGMENTOS = "^(todos|clientes|profissionais|categoria|cidade)$"
_TIPOS = "^(operacional|marketing)$"


class CampanhaOut(BaseModel):
    id: str
    titulo: str
    mensagem: str
    segmento: str
    tipo: str = "marketing"
    categoria_id: str | None = None
    cidade_id: str | None = None
    total_destinatarios: int = 0
    criado_em: str
    autor: str | None = None
    enviados: int = 0
    entregues: int = 0
    abertos: int = 0


class EstimativaOut(BaseModel):
    destinatarios: int
    desativaram: int = 0


class DispararCampanhaIn(BaseModel):
    titulo: str = Field(min_length=3, max_length=50)
    mensagem: str = Field(min_length=5, max_length=140)
    segmento: str = Field(..., pattern=_SEGMENTOS)
    tipo: str = Field(default="marketing", pattern=_TIPOS)
    categoria_id: str | None = None
    cidade_id: str | None = None
    motivo: str = Field(min_length=10, max_length=500)


def _banco(contexto: Contexto) -> Any:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    return banco


def _iso(valor: Any) -> str:
    return valor.isoformat() if hasattr(valor, "isoformat") else str(valor)


def _destinatarios(
    con: Any, segmento: str, tipo: str, categoria_id: Any, cidade_id: Any
) -> tuple[list[Any], int]:
    """(ids que recebem, quantos ficaram de fora por terem desligado o marketing)."""
    if segmento == "categoria" and categoria_id is None:
        raise HTTPException(422, "Escolha a categoria do segmento.")
    if segmento == "cidade" and cidade_id is None:
        raise HTTPException(422, "Escolha a cidade do segmento.")
    base = "select distinct u.id from public.usuarios u"
    onde = "where u.status = 'ativo'"
    params: tuple[Any, ...] = ()
    if segmento == "profissionais":
        base += " join public.perfis_profissional pp on pp.usuario_id = u.id"
    elif segmento == "clientes":
        onde += (
            " and not exists (select 1 from public.perfis_profissional pp"
            " where pp.usuario_id = u.id)"
        )
    elif segmento == "categoria":
        base += (
            " join public.profissional_categorias pc on pc.profissional_id = u.id"
            " and pc.categoria_id = %s"
        )
        params = (categoria_id,)
    elif segmento == "cidade":
        onde += (
            " and (exists (select 1 from public.profissional_regioes r"
            "               where r.profissional_id = u.id and r.cidade_id = %s)"
            "      or exists (select 1 from public.pedidos pe"
            "                 where pe.cliente_id = u.id and pe.cidade_id = %s))"
        )
        params = (cidade_id, cidade_id)
    todos = [r["id"] for r in con.execute(f"{base} {onde}", params).fetchall()]  # noqa: S608
    if tipo != "marketing" or not todos:
        return todos, 0
    # Marketing respeita a preferência: quem desligou o push de marketing não recebe.
    fora = {
        r["usuario_id"]
        for r in con.execute(
            "select usuario_id from public.notificacao_preferencias "
            "where usuario_id = any(%s) and preferencias->'marketing'->>'push' = 'false'",
            (todos,),
        ).fetchall()
    }
    return [i for i in todos if i not in fora], len(fora)


@router.get(
    "/estimativa", response_model=EstimativaOut, summary="Quantas pessoas receberiam a campanha"
)
def estimar(
    segmento: str = Query(..., pattern=_SEGMENTOS),
    tipo: str = Query("marketing", pattern=_TIPOS),
    categoria_id: str | None = None,
    cidade_id: str | None = None,
    operador: Operador = Depends(exigir(Permissao.NOTIFICACOES_ENVIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> EstimativaOut:
    with _banco(contexto).transacao() as con:
        ids, fora = _destinatarios(
            con,
            segmento,
            tipo,
            como_uuid(categoria_id) if categoria_id else None,
            como_uuid(cidade_id) if cidade_id else None,
        )
    return EstimativaOut(destinatarios=len(ids), desativaram=fora)


@router.get(
    "/campanhas", response_model=list[CampanhaOut], summary="Histórico de campanhas enviadas"
)
def listar_campanhas(
    operador: Operador = Depends(exigir(Permissao.NOTIFICACOES_ENVIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[CampanhaOut]:
    with _banco(contexto).transacao() as con:
        linhas = con.execute(
            """
            SELECT c.id, c.titulo, c.mensagem, c.segmento, c.tipo, c.categoria_id, c.cidade_id,
                   c.total_destinatarios, c.criado_em, u.nome AS autor,
                   count(n.id) AS enviados,
                   count(n.id) FILTER (WHERE n.enviada_em IS NOT NULL) AS entregues,
                   count(n.id) FILTER (WHERE n.lida_em IS NOT NULL) AS abertos
            FROM public.campanhas_notificacao c
            LEFT JOIN public.usuarios u ON u.id = c.criado_por
            LEFT JOIN public.notificacoes n ON n.dados->>'campanha_id' = c.id::text
            GROUP BY c.id, u.nome
            ORDER BY c.criado_em DESC
            LIMIT 100
            """
        ).fetchall()
    return [
        CampanhaOut(
            id=str(r["id"]),
            titulo=r["titulo"],
            mensagem=r["mensagem"],
            segmento=r["segmento"],
            tipo=r["tipo"],
            categoria_id=str(r["categoria_id"]) if r["categoria_id"] else None,
            cidade_id=str(r["cidade_id"]) if r["cidade_id"] else None,
            total_destinatarios=int(r["total_destinatarios"] or 0),
            criado_em=_iso(r["criado_em"]),
            autor=r["autor"],
            enviados=int(r["enviados"] or 0),
            entregues=int(r["entregues"] or 0),
            abertos=int(r["abertos"] or 0),
        )
        for r in linhas
    ]


@router.post(
    "/disparar", response_model=CampanhaOut, status_code=201, summary="Disparar push em massa"
)
def disparar_campanha(
    corpo: DispararCampanhaIn,
    operador: Operador = Depends(exigir(Permissao.NOTIFICACOES_ENVIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CampanhaOut:
    cat_uid = como_uuid(corpo.categoria_id) if corpo.categoria_id else None
    cid_uid = como_uuid(corpo.cidade_id) if corpo.cidade_id else None

    with _banco(contexto).transacao() as con:
        ids, fora = _destinatarios(con, corpo.segmento, corpo.tipo, cat_uid, cid_uid)
        if not ids:
            raise HTTPException(422, "Nenhuma pessoa receberia esta campanha. Revise o segmento.")
        camp = con.execute(
            """
            INSERT INTO public.campanhas_notificacao
              (titulo, mensagem, segmento, tipo, categoria_id, cidade_id, total_destinatarios,
               criado_por)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id, titulo, mensagem, segmento, tipo, categoria_id, cidade_id,
                      total_destinatarios, criado_em
            """,
            (
                corpo.titulo,
                corpo.mensagem,
                corpo.segmento,
                corpo.tipo,
                cat_uid,
                cid_uid,
                len(ids),
                operador.id,
            ),
        ).fetchone()
        for uid in ids:
            con.execute(
                """
                INSERT INTO public.notificacoes (usuario_id, tipo, canal, titulo, corpo, dados)
                VALUES (%s, 'aviso_campanha', 'push', %s, %s,
                        jsonb_build_object('campanha_id', %s::text))
                """,
                (uid, corpo.titulo, corpo.mensagem, str(camp["id"])),
            )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="notificacao.campanha_disparada",
            entidade="campanhas_notificacao",
            entidade_id=str(camp["id"]),
            depois={
                "titulo": corpo.titulo,
                "segmento": corpo.segmento,
                "tipo": corpo.tipo,
                "total": len(ids),
                "desativaram": fora,
            },
            motivo=corpo.motivo,
        )
        return CampanhaOut(
            id=str(camp["id"]),
            titulo=camp["titulo"],
            mensagem=camp["mensagem"],
            segmento=camp["segmento"],
            tipo=camp["tipo"],
            categoria_id=str(camp["categoria_id"]) if camp["categoria_id"] else None,
            cidade_id=str(camp["cidade_id"]) if camp["cidade_id"] else None,
            total_destinatarios=len(ids),
            criado_em=_iso(camp["criado_em"]),
            enviados=len(ids),
        )
