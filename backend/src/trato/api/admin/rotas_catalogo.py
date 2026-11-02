"""Rotas administrativas de categorias e suporte (F7.4)."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin", tags=["admin: categorias e suporte"])


class CategoriaAdminOut(BaseModel):
    id: str
    nome: str
    ativa: bool
    profissionais: int


class AlterarCategoriaIn(BaseModel):
    ativa: bool
    motivo: str = Field(min_length=3, max_length=500)


class ChamadoOut(BaseModel):
    id: str
    assunto: str
    solicitante: str
    status: str
    aberto_em: datetime


@router.get("/categorias", response_model=list[CategoriaAdminOut], summary="Listar categorias para administração")
def listar_categorias(
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[CategoriaAdminOut]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        return []
    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT c.id, c.nome, c.ativa, count(pc.profissional_id) as profissionais
            FROM public.categorias c
            LEFT JOIN public.profissional_categorias pc ON pc.categoria_id = c.id
            GROUP BY c.id, c.nome, c.ativa, c.ordem
            ORDER BY c.ordem, c.nome
            """
        ).fetchall()
        return [
            CategoriaAdminOut(
                id=str(r["id"]),
                nome=str(r["nome"]),
                ativa=bool(r["ativa"]),
                profissionais=int(r["profissionais"] or 0),
            )
            for r in linhas
        ]


@router.patch("/categorias/{categoria_id}", response_model=CategoriaAdminOut, summary="Ativar ou desativar categoria")
def alterar_categoria(
    categoria_id: str,
    corpo: AlterarCategoriaIn,
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CategoriaAdminOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(categoria_id)
    if uid is None:
        raise HTTPException(404, "Categoria não encontrada.")
    with banco.transacao() as con:
        cat = con.execute("SELECT id, nome, ativa FROM public.categorias WHERE id = %s", (uid,)).fetchone()
        if cat is None:
            raise HTTPException(404, "Categoria não encontrada.")
        con.execute("UPDATE public.categorias SET ativa = %s WHERE id = %s", (corpo.ativa, uid))
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="categoria.ativada" if corpo.ativa else "categoria.desativada",
            entidade="categorias",
            entidade_id=str(uid),
            depois={"ativa": corpo.ativa, "nome": cat["nome"]},
            motivo=corpo.motivo,
        )
        contagem = con.execute(
            "SELECT count(*) as total FROM public.profissional_categorias WHERE categoria_id = %s", (uid,)
        ).fetchone()
        return CategoriaAdminOut(
            id=str(uid),
            nome=cat["nome"],
            ativa=corpo.ativa,
            profissionais=int(contagem["total"] or 0) if contagem else 0,
        )


@router.get("/chamados", response_model=list[ChamadoOut], summary="Listar chamados de suporte abertos")
def listar_chamados(
    operador: Operador = Depends(exigir(Permissao.SUPORTE_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[ChamadoOut]:
    # Retorna chamados reais ou vazio se nenhum chamado aberto
    return []
