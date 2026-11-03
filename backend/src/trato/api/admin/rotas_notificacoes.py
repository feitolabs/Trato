"""Rotas de Notificações Push e Comunicação em Massa (Módulo 4).

Permite aos administradores e moderadores dispararem comunicados, avisos
e promoções para segmentos específicos de usuários.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/notificacoes", tags=["admin: notificacoes e campanhas"])


class CampanhaOut(BaseModel):
    id: str
    titulo: str
    mensagem: str
    segmento: str
    categoria_id: str | None = None
    cidade_id: str | None = None
    total_destinatarios: int = 0
    criado_em: str


class DispararCampanhaIn(BaseModel):
    titulo: str = Field(min_length=3, max_length=150)
    mensagem: str = Field(min_length=5, max_length=1000)
    segmento: str = Field(..., pattern="^(todos|clientes|profissionais|categoria|cidade)$")
    categoria_id: str | None = None
    cidade_id: str | None = None
    motivo: str = Field(min_length=3, max_length=500)


@router.get("/campanhas", response_model=list[CampanhaOut], summary="Listar histórico de campanhas enviadas")
def listar_campanhas(
    operador: Operador = Depends(exigir(Permissao.NOTIFICACOES_ENVIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[CampanhaOut]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT id, titulo, mensagem, segmento, categoria_id, cidade_id, total_destinatarios, criado_em
            FROM public.campanhas_notificacao
            ORDER BY criado_em DESC
            LIMIT 50
            """
        ).fetchall()

        return [
            CampanhaOut(
                id=str(r["id"]),
                titulo=r["titulo"],
                mensagem=r["mensagem"],
                segmento=r["segmento"],
                categoria_id=str(r["categoria_id"]) if r["categoria_id"] else None,
                cidade_id=str(r["cidade_id"]) if r["cidade_id"] else None,
                total_destinatarios=int(r["total_destinatarios"] or 0),
                criado_em=r["criado_em"].isoformat() if hasattr(r["criado_em"], "isoformat") else str(r["criado_em"]),
            )
            for r in linhas
        ]


@router.post("/disparar", response_model=CampanhaOut, status_code=201, summary="Disparar notificação push em massa")
def disparar_campanha(
    corpo: DispararCampanhaIn,
    operador: Operador = Depends(exigir(Permissao.NOTIFICACOES_ENVIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CampanhaOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    cat_uid = como_uuid(corpo.categoria_id) if corpo.categoria_id else None
    cid_uid = como_uuid(corpo.cidade_id) if corpo.cidade_id else None

    with banco.transacao() as con:
        # Seleciona os destinatários conforme o segmento
        if corpo.segmento == "todos":
            destinatarios = con.execute("SELECT id FROM public.usuarios WHERE status = 'ativo'").fetchall()
        elif corpo.segmento == "profissionais":
            destinatarios = con.execute(
                "SELECT u.id FROM public.usuarios u JOIN public.perfis_profissional p ON p.usuario_id = u.id WHERE u.status = 'ativo'"
            ).fetchall()
        elif corpo.segmento == "clientes":
            destinatarios = con.execute(
                "SELECT u.id FROM public.usuarios u WHERE u.status = 'ativo' AND NOT EXISTS (SELECT 1 FROM public.perfis_profissional p WHERE p.usuario_id = u.id)"
            ).fetchall()
        elif corpo.segmento == "categoria" and cat_uid:
            destinatarios = con.execute(
                """
                SELECT distinct u.id FROM public.usuarios u
                JOIN public.perfis_profissional p ON p.usuario_id = u.id
                JOIN public.profissional_categorias pc ON pc.profissional_id = p.usuario_id
                WHERE pc.categoria_id = %s AND u.status = 'ativo'
                """,
                (cat_uid,),
            ).fetchall()
        else:
            destinatarios = con.execute("SELECT id FROM public.usuarios WHERE status = 'ativo' LIMIT 100").fetchall()

        total = len(destinatarios)

        # Insere em massa na tabela de notificações do Trato
        for d in destinatarios:
            con.execute(
                """
                INSERT INTO public.notificacoes (usuario_id, tipo, canal, titulo, corpo)
                VALUES (%s, 'aviso_campanha', 'push', %s, %s)
                """,
                (d["id"], corpo.titulo, corpo.mensagem),
            )

        # Salva o histórico da campanha
        camp = con.execute(
            """
            INSERT INTO public.campanhas_notificacao (titulo, mensagem, segmento, categoria_id, cidade_id, total_destinatarios, criado_por)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id, titulo, mensagem, segmento, categoria_id, cidade_id, total_destinatarios, criado_em
            """,
            (corpo.titulo, corpo.mensagem, corpo.segmento, cat_uid, cid_uid, total, operador.id),
        ).fetchone()

        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="notificacao.campanha_disparada",
            entidade="campanhas_notificacao",
            entidade_id=str(camp["id"]),
            depois={"titulo": corpo.titulo, "segmento": corpo.segmento, "total": total},
            motivo=corpo.motivo,
        )

        return CampanhaOut(
            id=str(camp["id"]),
            titulo=camp["titulo"],
            mensagem=camp["mensagem"],
            segmento=camp["segmento"],
            categoria_id=str(camp["categoria_id"]) if camp["categoria_id"] else None,
            cidade_id=str(camp["cidade_id"]) if camp["cidade_id"] else None,
            total_destinatarios=total,
            criado_em=camp["criado_em"].isoformat() if hasattr(camp["criado_em"], "isoformat") else str(camp["criado_em"]),
        )

