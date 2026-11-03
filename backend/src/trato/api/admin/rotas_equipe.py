"""Rotas de Gestão de Equipe e Acessos Internos (Módulo 6).

Permite aos administradores cadastrarem novos colaboradores, definirem papéis
de acesso (ex: Atendente N1, N2, Financeiro, Moderador) e alçadas de decisão.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/equipe", tags=["admin: equipe interna"])


class MembroEquipeOut(BaseModel):
    usuario_id: str
    nome: str
    email: str
    papel: str
    ativo: bool
    alcada_centavos: int
    criado_em: str


class AdicionarMembroIn(BaseModel):
    nome: str = Field(min_length=2, max_length=150)
    email: str = Field(min_length=5, max_length=150)
    papel: str = Field(
        ...,
        pattern="^(atendente_n1|atendente_n2|mediador|financeiro|seguranca|cadastro|moderador|juridico|dpo|lider_suporte|administrador)$",
    )
    alcada_centavos: int = Field(default=0, ge=0)
    motivo: str = Field(min_length=3, max_length=500)


class EditarMembroIn(BaseModel):
    papel: str | None = Field(
        default=None,
        pattern="^(atendente_n1|atendente_n2|mediador|financeiro|seguranca|cadastro|moderador|juridico|dpo|lider_suporte|administrador)$",
    )
    alcada_centavos: int | None = Field(default=None, ge=0)
    ativo: bool | None = None
    motivo: str = Field(min_length=3, max_length=500)


@router.get("", response_model=list[MembroEquipeOut], summary="Listar membros da equipe interna")
def listar_equipe(
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[MembroEquipeOut]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT
              e.usuario_id,
              coalesce(u.nome, 'Membro da Equipe') as nome,
              coalesce(au.email, 'equipe@trato.local') as email,
              e.papel,
              e.ativo,
              coalesce(e.alcada_centavos, 0) as alcada_centavos,
              e.criado_em
            FROM public.equipe e
            LEFT JOIN public.usuarios u ON u.id = e.usuario_id
            LEFT JOIN auth.users au ON au.id = e.usuario_id
            ORDER BY e.ativo DESC, e.criado_em ASC
            """
        ).fetchall()

        return [
            MembroEquipeOut(
                usuario_id=str(r["usuario_id"]),
                nome=r["nome"],
                email=r["email"],
                papel=r["papel"],
                ativo=bool(r["ativo"]),
                alcada_centavos=int(r["alcada_centavos"] or 0),
                criado_em=r["criado_em"].isoformat() if hasattr(r["criado_em"], "isoformat") else str(r["criado_em"]),
            )
            for r in linhas
        ]


@router.post("", response_model=MembroEquipeOut, status_code=201, summary="Adicionar membro à equipe")
def adicionar_membro(
    corpo: AdicionarMembroIn,
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> MembroEquipeOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    email_norm = corpo.email.strip().lower()

    with banco.transacao() as con:
        # Verifica se já tem usuário registrado no Auth com esse e-mail
        usr = con.execute("SELECT id, email FROM auth.users WHERE lower(email) = %s", (email_norm,)).fetchone()

        if usr is None:
            raise HTTPException(
                404,
                f"Nenhuma conta encontrada com o e-mail '{email_norm}'. O colaborador precisa se cadastrar na plataforma antes de ser adicionado à equipe.",
            )

        usuario_id = usr["id"]

        # Garante perfil público na tabela usuarios
        con.execute(
            """
            INSERT INTO public.usuarios (id, nome, status)
            VALUES (%s, %s, 'ativo')
            ON CONFLICT (id) DO UPDATE SET nome = coalesce(nullif(EXCLUDED.nome, ''), public.usuarios.nome)
            """,
            (usuario_id, corpo.nome),
        )

        # Insere ou atualiza na equipe
        con.execute(
            """
            INSERT INTO public.equipe (usuario_id, papel, alcada_centavos, ativo)
            VALUES (%s, %s, %s, true)
            ON CONFLICT (usuario_id) DO UPDATE
            SET papel = EXCLUDED.papel,
                alcada_centavos = EXCLUDED.alcada_centavos,
                ativo = true,
                revogado_em = null
            """,
            (usuario_id, corpo.papel, corpo.alcada_centavos),
        )

        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="equipe.membro_adicionado",
            entidade="equipe",
            entidade_id=str(usuario_id),
            depois={"email": email_norm, "papel": corpo.papel, "alcada_centavos": corpo.alcada_centavos},
            motivo=corpo.motivo,
        )

        return MembroEquipeOut(
            usuario_id=str(usuario_id),
            nome=corpo.nome,
            email=email_norm,
            papel=corpo.papel,
            ativo=True,
            alcada_centavos=corpo.alcada_centavos,
            criado_em="agora",
        )


@router.patch("/{usuario_id}", response_model=MembroEquipeOut, summary="Alterar permissões ou status de membro da equipe")
def editar_membro(
    usuario_id: str,
    corpo: EditarMembroIn,
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> MembroEquipeOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(usuario_id)
    if uid is None:
        raise HTTPException(404, "Membro da equipe não encontrado.")

    with banco.transacao() as con:
        m = con.execute(
            """
            SELECT e.usuario_id, coalesce(u.nome, 'Membro') as nome, coalesce(au.email, 'email') as email, e.papel, e.ativo, e.alcada_centavos, e.criado_em
            FROM public.equipe e
            LEFT JOIN public.usuarios u ON u.id = e.usuario_id
            LEFT JOIN auth.users au ON au.id = e.usuario_id
            WHERE e.usuario_id = %s
            """,
            (uid,),
        ).fetchone()

        if m is None:
            raise HTTPException(404, "Membro da equipe não encontrado.")

        novo_papel = corpo.papel if corpo.papel is not None else m["papel"]
        nova_alcada = corpo.alcada_centavos if corpo.alcada_centavos is not None else m["alcada_centavos"]
        novo_ativo = corpo.ativo if corpo.ativo is not None else m["ativo"]

        con.execute(
            """
            UPDATE public.equipe
            SET papel = %s, alcada_centavos = %s, ativo = %s, revogado_em = (case when %s = false then now() else null end)
            WHERE usuario_id = %s
            """,
            (novo_papel, nova_alcada, novo_ativo, novo_ativo, uid),
        )

        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="equipe.membro_atualizado",
            entidade="equipe",
            entidade_id=str(uid),
            depois={"papel": novo_papel, "alcada_centavos": nova_alcada, "ativo": novo_ativo},
            motivo=corpo.motivo,
        )

        return MembroEquipeOut(
            usuario_id=str(uid),
            nome=m["nome"],
            email=m["email"],
            papel=novo_papel,
            ativo=novo_ativo,
            alcada_centavos=int(nova_alcada or 0),
            criado_em=m["criado_em"].isoformat() if hasattr(m["criado_em"], "isoformat") else str(m["criado_em"]),
        )


@router.delete("/{usuario_id}", summary="Revogar acesso de membro da equipe")
def revogar_membro(
    usuario_id: str,
    motivo: str = Query(..., min_length=3),
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(usuario_id)
    if uid is None:
        raise HTTPException(404, "Membro da equipe não encontrado.")

    with banco.transacao() as con:
        con.execute("UPDATE public.equipe SET ativo = false, revogado_em = now() WHERE usuario_id = %s", (uid,))
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="equipe.acesso_revogado",
            entidade="equipe",
            entidade_id=str(uid),
            depois={"ativo": False},
            motivo=motivo,
        )
        return {"mensagem": "Acesso revogado com sucesso."}

