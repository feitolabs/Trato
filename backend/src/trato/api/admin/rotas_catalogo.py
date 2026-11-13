"""Rotas administrativas de categorias, cidades e suporte (F7.4).

Permite controle total de CRUD sobre o catálogo e regiões que administram o app Trato.
"""

from __future__ import annotations

import re
import unicodedata
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin", tags=["admin: catalogo e suporte"])


def slugificar(texto: str) -> str:
    texto = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode("ascii")
    texto = re.sub(r"[^\w\s-]", "", texto).strip().lower()
    return re.sub(r"[-\s]+", "-", texto)


# =============================================================================
# MODELOS DE CATEGORIAS
# =============================================================================

class CategoriaAdminOut(BaseModel):
    id: str
    nome: str
    slug: str
    icone: str | None = None
    garantia_retrabalho_dias: int | None = None
    ordem: int = 0
    ativa: bool = True
    profissionais: int = 0
    aceita_remoto: bool = False


class CriarCategoriaIn(BaseModel):
    nome: str = Field(min_length=2, max_length=100)
    slug: str | None = Field(default=None, max_length=100)
    icone: str | None = Field(default=None, max_length=100)
    garantia_retrabalho_dias: int | None = Field(default=None, ge=1, le=365)
    ordem: int = 0
    ativa: bool = True
    aceita_remoto: bool = False
    motivo: str = Field(min_length=10, max_length=500)


class EditarCategoriaIn(BaseModel):
    nome: str | None = Field(default=None, min_length=2, max_length=100)
    slug: str | None = Field(default=None, max_length=100)
    icone: str | None = Field(default=None, max_length=100)
    garantia_retrabalho_dias: int | None = Field(default=None, ge=1, le=365)
    ordem: int | None = None
    ativa: bool | None = None
    aceita_remoto: bool | None = None
    motivo: str = Field(min_length=10, max_length=500)


class AlterarStatusIn(BaseModel):
    ativa: bool
    motivo: str = Field(min_length=10, max_length=500)


class ExcluirComMotivoIn(BaseModel):
    motivo: str = Field(min_length=10, max_length=500)


# =============================================================================
# MODELOS DE CIDADES
# =============================================================================

class CidadeAdminOut(BaseModel):
    id: str
    nome: str
    uf: str
    ativa: bool
    centro_lat: float | None = None
    centro_lng: float | None = None


class CriarCidadeIn(BaseModel):
    nome: str = Field(min_length=2, max_length=100)
    uf: str = Field(min_length=2, max_length=2)
    ativa: bool = True
    centro_lat: float | None = None
    centro_lng: float | None = None
    motivo: str = Field(min_length=10, max_length=500)


# =============================================================================
# MODELOS DE SUPORTE
# =============================================================================

class ChamadoOut(BaseModel):
    id: str
    assunto: str
    solicitante: str
    status: str
    aberto_em: datetime


# =============================================================================
# ROTAS: CATEGORIAS (CRUD COMPLETO)
# =============================================================================

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
            SELECT c.id, c.nome, c.slug, c.icone, c.garantia_retrabalho_dias, c.ordem, c.ativa,
                   c.aceita_remoto, count(pc.profissional_id) as profissionais
            FROM public.categorias c
            LEFT JOIN public.profissional_categorias pc ON pc.categoria_id = c.id
            GROUP BY c.id, c.nome, c.slug, c.icone, c.garantia_retrabalho_dias, c.ordem, c.ativa,
                     c.aceita_remoto
            ORDER BY c.ordem, c.nome
            """
        ).fetchall()
        return [
            CategoriaAdminOut(
                id=str(r["id"]),
                nome=str(r["nome"]),
                slug=str(r["slug"]),
                icone=str(r["icone"]) if r["icone"] else None,
                garantia_retrabalho_dias=int(r["garantia_retrabalho_dias"]) if r["garantia_retrabalho_dias"] else None,
                ordem=int(r["ordem"] or 0),
                ativa=bool(r["ativa"]),
                profissionais=int(r["profissionais"] or 0),
                aceita_remoto=bool(r["aceita_remoto"]),
            )
            for r in linhas
        ]


@router.post("/categorias", response_model=CategoriaAdminOut, status_code=201, summary="Criar nova categoria")
def criar_categoria(
    corpo: CriarCategoriaIn,
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CategoriaAdminOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    slug = corpo.slug.strip() if corpo.slug else slugificar(corpo.nome)
    if not slug:
        slug = slugificar(corpo.nome) or "categoria"
    with banco.transacao() as con:
        existe = con.execute("SELECT id FROM public.categorias WHERE slug = %s", (slug,)).fetchone()
        if existe:
            raise HTTPException(409, f"Já existe uma categoria com o identificador (slug) '{slug}'.")
        linha = con.execute(
            """
            INSERT INTO public.categorias
                (nome, slug, icone, garantia_retrabalho_dias, ordem, ativa, aceita_remoto)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id, nome, slug, icone, garantia_retrabalho_dias, ordem, ativa, aceita_remoto
            """,
            (corpo.nome.strip(), slug, corpo.icone, corpo.garantia_retrabalho_dias, corpo.ordem,
             corpo.ativa, corpo.aceita_remoto),
        ).fetchone()
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="categoria.criada",
            entidade="categorias",
            entidade_id=str(linha["id"]),
            depois={
                "nome": corpo.nome,
                "slug": slug,
                "ativa": corpo.ativa,
                "aceita_remoto": corpo.aceita_remoto,
            },
            motivo=corpo.motivo,
        )
        return CategoriaAdminOut(
            id=str(linha["id"]),
            nome=linha["nome"],
            slug=linha["slug"],
            icone=linha["icone"],
            garantia_retrabalho_dias=linha["garantia_retrabalho_dias"],
            ordem=linha["ordem"],
            ativa=linha["ativa"],
            profissionais=0,
            aceita_remoto=bool(linha["aceita_remoto"]),
        )


@router.put("/categorias/{categoria_id}", response_model=CategoriaAdminOut, summary="Editar categoria existente")
def editar_categoria(
    categoria_id: str,
    corpo: EditarCategoriaIn,
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
        atual = con.execute("SELECT * FROM public.categorias WHERE id = %s", (uid,)).fetchone()
        if atual is None:
            raise HTTPException(404, "Categoria não encontrada.")
        novo_nome = corpo.nome.strip() if corpo.nome is not None else atual["nome"]
        novo_slug = corpo.slug.strip() if corpo.slug is not None else atual["slug"]
        if novo_slug != atual["slug"]:
            existe = con.execute("SELECT id FROM public.categorias WHERE slug = %s AND id != %s", (novo_slug, uid)).fetchone()
            if existe:
                raise HTTPException(409, f"O slug '{novo_slug}' já está em uso por outra categoria.")
        novo_icone = corpo.icone if corpo.icone is not None else atual["icone"]
        nova_garantia = corpo.garantia_retrabalho_dias if corpo.garantia_retrabalho_dias is not None else atual["garantia_retrabalho_dias"]
        nova_ordem = corpo.ordem if corpo.ordem is not None else atual["ordem"]
        nova_ativa = corpo.ativa if corpo.ativa is not None else atual["ativa"]
        novo_remoto = (
            corpo.aceita_remoto if corpo.aceita_remoto is not None else atual["aceita_remoto"]
        )
        if atual["aceita_remoto"] and not novo_remoto:
            abertos = con.execute(
                "SELECT count(*) AS n FROM public.pedidos WHERE categoria_id = %s "
                "AND modalidade = 'remoto' AND status NOT IN ('concluido', 'cancelado')",
                (uid,),
            ).fetchone()
            if abertos and int(abertos["n"] or 0) > 0:
                raise HTTPException(
                    409,
                    "Há pedidos remotos em andamento nesta categoria. Termine ou cancele esses "
                    "pedidos antes de desligar o atendimento remoto.",
                )

        con.execute(
            """
            UPDATE public.categorias
            SET nome = %s, slug = %s, icone = %s, garantia_retrabalho_dias = %s, ordem = %s,
                ativa = %s, aceita_remoto = %s, atualizado_em = now()
            WHERE id = %s
            """,
            (novo_nome, novo_slug, novo_icone, nova_garantia, nova_ordem, nova_ativa,
             novo_remoto, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="categoria.editada",
            entidade="categorias",
            entidade_id=str(uid),
            depois={
                "nome": novo_nome,
                "slug": novo_slug,
                "ativa": nova_ativa,
                "aceita_remoto": bool(novo_remoto),
            },
            motivo=corpo.motivo,
        )
        contagem = con.execute(
            "SELECT count(*) as total FROM public.profissional_categorias WHERE categoria_id = %s", (uid,)
        ).fetchone()
        return CategoriaAdminOut(
            id=str(uid),
            nome=novo_nome,
            slug=novo_slug,
            icone=novo_icone,
            garantia_retrabalho_dias=nova_garantia,
            ordem=nova_ordem,
            ativa=nova_ativa,
            profissionais=int(contagem["total"] or 0) if contagem else 0,
            aceita_remoto=bool(novo_remoto),
        )


@router.patch("/categorias/{categoria_id}", response_model=CategoriaAdminOut, summary="Ativar ou desativar categoria")
def alterar_status_categoria(
    categoria_id: str,
    corpo: AlterarStatusIn,
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
        cat = con.execute("SELECT id, nome, slug, icone, garantia_retrabalho_dias, ordem, ativa FROM public.categorias WHERE id = %s", (uid,)).fetchone()
        if cat is None:
            raise HTTPException(404, "Categoria não encontrada.")
        con.execute("UPDATE public.categorias SET ativa = %s, atualizado_em = now() WHERE id = %s", (corpo.ativa, uid))
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
            slug=cat["slug"],
            icone=cat["icone"],
            garantia_retrabalho_dias=cat["garantia_retrabalho_dias"],
            ordem=cat["ordem"],
            ativa=corpo.ativa,
            profissionais=int(contagem["total"] or 0) if contagem else 0,
        )


@router.delete("/categorias/{categoria_id}", status_code=204, summary="Excluir categoria sem dependências")
def excluir_categoria(
    categoria_id: str,
    motivo: str = Query(..., min_length=10, max_length=500),
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> None:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(categoria_id)
    if uid is None:
        raise HTTPException(404, "Categoria não encontrada.")
    with banco.transacao() as con:
        cat = con.execute("SELECT id, nome FROM public.categorias WHERE id = %s", (uid,)).fetchone()
        if cat is None:
            raise HTTPException(404, "Categoria não encontrada.")
        pedidos_vinculados = con.execute("SELECT count(*) as total FROM public.pedidos WHERE categoria_id = %s", (uid,)).fetchone()["total"]
        if pedidos_vinculados > 0:
            raise HTTPException(
                409,
                f"Esta categoria não pode ser excluída porque possui {pedidos_vinculados} pedido(s) histórico(s). Você pode desativá-la.",
            )
        prof_vinculados = con.execute("SELECT count(*) as total FROM public.profissional_categorias WHERE categoria_id = %s", (uid,)).fetchone()["total"]
        if prof_vinculados > 0:
            raise HTTPException(
                409,
                f"Esta categoria possui {prof_vinculados} profissional(is) vinculado(s). Remova os vínculos ou desative a categoria.",
            )
        con.execute("DELETE FROM public.categoria_perguntas WHERE categoria_id = %s", (uid,))
        con.execute("DELETE FROM public.categorias WHERE id = %s", (uid,))
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="categoria.excluida",
            entidade="categorias",
            entidade_id=str(uid),
            depois={"nome": cat["nome"]},
            motivo=motivo,
        )


# =============================================================================
# ROTAS: CIDADES (EXPANSÃO REGIONAL DO APP)
# =============================================================================

@router.get("/cidades", response_model=list[CidadeAdminOut], summary="Listar cidades de atuação")
def listar_cidades(
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[CidadeAdminOut]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        return []
    with banco.transacao() as con:
        linhas = con.execute(
            "SELECT id, nome, uf, ativa, centro_lat, centro_lng FROM public.cidades ORDER BY uf, nome"
        ).fetchall()
        return [
            CidadeAdminOut(
                id=str(r["id"]),
                nome=str(r["nome"]),
                uf=str(r["uf"]),
                ativa=bool(r["ativa"]),
                centro_lat=float(r["centro_lat"]) if r["centro_lat"] is not None else None,
                centro_lng=float(r["centro_lng"]) if r["centro_lng"] is not None else None,
            )
            for r in linhas
        ]


@router.post("/cidades", response_model=CidadeAdminOut, status_code=201, summary="Cadastrar nova cidade de atuação")
def criar_cidade(
    corpo: CriarCidadeIn,
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CidadeAdminOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uf = corpo.uf.strip().upper()
    nome = corpo.nome.strip()
    with banco.transacao() as con:
        existe = con.execute("SELECT id FROM public.cidades WHERE lower(nome) = lower(%s) AND uf = %s", (nome, uf)).fetchone()
        if existe:
            raise HTTPException(409, f"A cidade {nome} - {uf} já está cadastrada.")
        linha = con.execute(
            """
            INSERT INTO public.cidades (nome, uf, ativa, centro_lat, centro_lng)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id, nome, uf, ativa, centro_lat, centro_lng
            """,
            (nome, uf, corpo.ativa, corpo.centro_lat, corpo.centro_lng),
        ).fetchone()
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cidade.criada",
            entidade="cidades",
            entidade_id=str(linha["id"]),
            depois={"nome": nome, "uf": uf, "ativa": corpo.ativa},
            motivo=corpo.motivo,
        )
        return CidadeAdminOut(
            id=str(linha["id"]),
            nome=linha["nome"],
            uf=linha["uf"],
            ativa=linha["ativa"],
            centro_lat=linha["centro_lat"],
            centro_lng=linha["centro_lng"],
        )


@router.patch("/cidades/{cidade_id}", response_model=CidadeAdminOut, summary="Ativar ou desativar cidade")
def alterar_status_cidade(
    cidade_id: str,
    corpo: AlterarStatusIn,
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CidadeAdminOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(cidade_id)
    if uid is None:
        raise HTTPException(404, "Cidade não encontrada.")
    with banco.transacao() as con:
        cid = con.execute("SELECT id, nome, uf, ativa, centro_lat, centro_lng FROM public.cidades WHERE id = %s", (uid,)).fetchone()
        if cid is None:
            raise HTTPException(404, "Cidade não encontrada.")
        con.execute("UPDATE public.cidades SET ativa = %s, atualizado_em = now() WHERE id = %s", (corpo.ativa, uid))
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cidade.ativada" if corpo.ativa else "cidade.desativada",
            entidade="cidades",
            entidade_id=str(uid),
            depois={"ativa": corpo.ativa, "nome": cid["nome"], "uf": cid["uf"]},
            motivo=corpo.motivo,
        )
        return CidadeAdminOut(
            id=str(uid),
            nome=cid["nome"],
            uf=cid["uf"],
            ativa=corpo.ativa,
            centro_lat=cid["centro_lat"],
            centro_lng=cid["centro_lng"],
        )


# =============================================================================
# MODELOS DE PERGUNTAS DINÂMICAS DE CATEGORIA
# =============================================================================

class PerguntaAdminOut(BaseModel):
    id: str
    categoria_id: str
    texto: str
    tipo: str
    opcoes: list[str] | None = None
    obrigatoria: bool = False
    ordem: int = 0
    ativa: bool = True


class CriarPerguntaIn(BaseModel):
    texto: str = Field(min_length=3, max_length=300)
    tipo: str = Field(..., pattern="^(texto|numero|escolha_unica|multipla|sim_nao)$")
    opcoes: list[str] | None = None
    obrigatoria: bool = False
    ordem: int = 0
    motivo: str = Field(min_length=10, max_length=500)


class EditarPerguntaIn(BaseModel):
    texto: str | None = Field(default=None, min_length=3, max_length=300)
    tipo: str | None = Field(default=None, pattern="^(texto|numero|escolha_unica|multipla|sim_nao)$")
    opcoes: list[str] | None = None
    obrigatoria: bool | None = None
    ordem: int | None = None
    ativa: bool | None = None
    motivo: str = Field(min_length=10, max_length=500)


# =============================================================================
# ROTAS: SUPORTE
# =============================================================================

@router.get("/chamados", response_model=list[ChamadoOut], summary="Listar chamados de suporte abertos")
def listar_chamados(
    operador: Operador = Depends(exigir(Permissao.SUPORTE_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[ChamadoOut]:
    return []


# =============================================================================
# ROTAS: PERGUNTAS DINÂMICAS DA CATEGORIA
# =============================================================================

@router.get("/categorias/{categoria_id}/perguntas", response_model=list[PerguntaAdminOut], summary="Listar perguntas dinâmicas da categoria")
def listar_perguntas_categoria(
    categoria_id: str,
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[PerguntaAdminOut]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(categoria_id)
    if uid is None:
        raise HTTPException(404, "Categoria não encontrada.")
    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT id, categoria_id, texto, tipo, opcoes, obrigatoria, ordem, ativa
            FROM public.categoria_perguntas
            WHERE categoria_id = %s
            ORDER BY ordem ASC, criado_em ASC
            """,
            (uid,),
        ).fetchall()
        return [
            PerguntaAdminOut(
                id=str(r["id"]),
                categoria_id=str(r["categoria_id"]),
                texto=r["texto"],
                tipo=r["tipo"],
                opcoes=r["opcoes"] if isinstance(r["opcoes"], list) else None,
                obrigatoria=r["obrigatoria"],
                ordem=r["ordem"],
                ativa=r["ativa"],
            )
            for r in linhas
        ]


@router.post("/categorias/{categoria_id}/perguntas", response_model=PerguntaAdminOut, status_code=201, summary="Criar nova pergunta dinâmica")
def criar_pergunta_categoria(
    categoria_id: str,
    corpo: CriarPerguntaIn,
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> PerguntaAdminOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(categoria_id)
    if uid is None:
        raise HTTPException(404, "Categoria não encontrada.")
    with banco.transacao() as con:
        cat = con.execute("SELECT id, nome FROM public.categorias WHERE id = %s", (uid,)).fetchone()
        if cat is None:
            raise HTTPException(404, "Categoria não encontrada.")
        import json
        opcoes_json = json.dumps(corpo.opcoes) if corpo.opcoes else None
        res = con.execute(
            """
            INSERT INTO public.categoria_perguntas (categoria_id, texto, tipo, opcoes, obrigatoria, ordem, ativa)
            VALUES (%s, %s, %s, %s, %s, %s, true)
            RETURNING id, categoria_id, texto, tipo, opcoes, obrigatoria, ordem, ativa
            """,
            (uid, corpo.texto, corpo.tipo, opcoes_json, corpo.obrigatoria, corpo.ordem),
        ).fetchone()
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="categoria.pergunta_criada",
            entidade="categoria_perguntas",
            entidade_id=str(res["id"]),
            depois={"categoria": cat["nome"], "texto": corpo.texto, "tipo": corpo.tipo},
            motivo=corpo.motivo,
        )
        return PerguntaAdminOut(
            id=str(res["id"]),
            categoria_id=str(res["categoria_id"]),
            texto=res["texto"],
            tipo=res["tipo"],
            opcoes=corpo.opcoes,
            obrigatoria=res["obrigatoria"],
            ordem=res["ordem"],
            ativa=res["ativa"],
        )


@router.put("/categorias/{categoria_id}/perguntas/{pergunta_id}", response_model=PerguntaAdminOut, summary="Editar pergunta dinâmica")
def editar_pergunta_categoria(
    categoria_id: str,
    pergunta_id: str,
    corpo: EditarPerguntaIn,
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> PerguntaAdminOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(categoria_id)
    pid = como_uuid(pergunta_id)
    if uid is None or pid is None:
        raise HTTPException(404, "Pergunta ou categoria não encontrada.")
    with banco.transacao() as con:
        p_antiga = con.execute(
            "SELECT * FROM public.categoria_perguntas WHERE id = %s AND categoria_id = %s",
            (pid, uid),
        ).fetchone()
        if p_antiga is None:
            raise HTTPException(404, "Pergunta não encontrada.")
        texto = corpo.texto if corpo.texto is not None else p_antiga["texto"]
        tipo = corpo.tipo if corpo.tipo is not None else p_antiga["tipo"]
        obrigatoria = corpo.obrigatoria if corpo.obrigatoria is not None else p_antiga["obrigatoria"]
        ordem = corpo.ordem if corpo.ordem is not None else p_antiga["ordem"]
        ativa = corpo.ativa if corpo.ativa is not None else p_antiga["ativa"]
        import json
        opcoes_json = json.dumps(corpo.opcoes) if corpo.opcoes is not None else (json.dumps(p_antiga["opcoes"]) if p_antiga["opcoes"] else None)

        con.execute(
            """
            UPDATE public.categoria_perguntas
            SET texto = %s, tipo = %s, opcoes = %s, obrigatoria = %s, ordem = %s, ativa = %s, atualizado_em = now()
            WHERE id = %s
            """,
            (texto, tipo, opcoes_json, obrigatoria, ordem, ativa, pid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="categoria.pergunta_editada",
            entidade="categoria_perguntas",
            entidade_id=str(pid),
            depois={"texto": texto, "tipo": tipo, "ativa": ativa},
            motivo=corpo.motivo,
        )
        return PerguntaAdminOut(
            id=str(pid),
            categoria_id=str(uid),
            texto=texto,
            tipo=tipo,
            opcoes=corpo.opcoes if corpo.opcoes is not None else (p_antiga["opcoes"] if isinstance(p_antiga["opcoes"], list) else None),
            obrigatoria=obrigatoria,
            ordem=ordem,
            ativa=ativa,
        )


@router.delete("/categorias/{categoria_id}/perguntas/{pergunta_id}", summary="Desativar pergunta da categoria")
def desativar_pergunta_categoria(
    categoria_id: str,
    pergunta_id: str,
    motivo: str = Query(..., min_length=10),
    operador: Operador = Depends(exigir(Permissao.CATEGORIAS_EDITAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(categoria_id)
    pid = como_uuid(pergunta_id)
    if uid is None or pid is None:
        raise HTTPException(404, "Pergunta ou categoria não encontrada.")
    with banco.transacao() as con:
        con.execute(
            "UPDATE public.categoria_perguntas SET ativa = false, atualizado_em = now() WHERE id = %s AND categoria_id = %s",
            (pid, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="categoria.pergunta_desativada",
            entidade="categoria_perguntas",
            entidade_id=str(pid),
            depois={"ativa": False},
            motivo=motivo,
        )
        return {"mensagem": "Pergunta desativada com sucesso."}
