"""Cadastro e perfil do profissional.

`POST /v1/profissional/cadastro`, `GET/PATCH /v1/profissional/perfil` e o perfil público
`GET /v1/profissionais/{id}` (sem dado pessoal sensível: nada de documento, telefone, e-mail,
endereço; o nome sai abreviado). O texto livre passa pelo mascaramento de contato.
"""

from __future__ import annotations

import re
import unicodedata
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.persistencia.comum import como_uuid
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.repositorios_app import PerfilDetalhe
from trato.profissional.config import ConfigProfissional, obter_config_profissional
from trato.profissional.repositorio import (
    CatalogoEmMemoria,
    CatalogoProfissional,
    FiltroBusca,
    ItemPortfolio,
    JanelaSemanal,
    PerfilProfissional,
    ProfissionaisEmMemoria,
    Regiao,
    RepositorioProfissionais,
    slugs,
)
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.texto_livre import limpar_texto

router = APIRouter(prefix="/v1", tags=["profissional"])

_pessoa = exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)
_HORA = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RegiaoIO(_Entrada):
    cidade_id: str = Field(min_length=1, max_length=64)
    bairro: str | None = Field(None, max_length=80)


class JanelaIO(_Entrada):
    dia_semana: int = Field(ge=0, le=6, description="0 = segunda ... 6 = domingo.")
    inicio: str = Field(description="HH:MM")
    fim: str = Field(description="HH:MM")


class PortfolioIO(_Entrada):
    titulo: str = Field(min_length=1, max_length=120)
    descricao: str | None = Field(None, max_length=600)


class CadastroIn(_Entrada):
    categorias: list[str] = Field(min_length=1, max_length=100)
    regioes: list[RegiaoIO] = Field(min_length=1, max_length=200)
    disponibilidade: list[JanelaIO] = Field(default_factory=list, max_length=100)
    bio: str | None = Field(None, max_length=20_000)
    portfolio: list[PortfolioIO] = Field(default_factory=list, max_length=100)


class PerfilEditarIn(_Entrada):
    categorias: list[str] | None = Field(None, min_length=1, max_length=100)
    regioes: list[RegiaoIO] | None = Field(None, min_length=1, max_length=200)
    disponibilidade: list[JanelaIO] | None = Field(None, max_length=100)
    bio: str | None = Field(None, max_length=20_000)
    portfolio: list[PortfolioIO] | None = Field(None, max_length=100)


class PerfilProfissionalOut(BaseModel):
    usuario_id: str
    status: str
    nivel_verificacao: str
    nivel_verificacao_exigido: str = Field(description="Mínimo para as suas categorias.")
    bio: str | None
    categorias: list[str]
    regioes: list[RegiaoIO]
    disponibilidade: list[JanelaIO]
    portfolio: list[PortfolioIO]


class AvaliacaoRecebidaOut(BaseModel):
    nota_geral: int
    comentario: str | None
    etiquetas: list[str]
    criada_em: datetime


class PerfilPublicoOut(BaseModel):
    id: str
    nome: str | None
    bio: str | None
    nivel_verificacao: str
    nota_publica: float | None
    servicos_concluidos: int | None
    categorias: list[str]
    regioes: list[RegiaoIO]
    disponibilidade: list[JanelaIO]
    portfolio: list[PortfolioIO]
    avaliacoes: list[AvaliacaoRecebidaOut]
    no_trato_desde: datetime = Field(description="Quando o perfil foi criado.")
    cidades: list[str] = Field(
        default_factory=list, description='Cidades que atende, em texto ("Belo Horizonte/MG").'
    )


# --- Ligações ----------------------------------------------------------------------------


class Modulo:
    """O que as rotas precisam: repositório, catálogo e configuração."""

    def __init__(
        self,
        repo: RepositorioProfissionais,
        catalogo: CatalogoProfissional,
        config: ConfigProfissional,
    ) -> None:
        self.repo, self.catalogo, self.config = repo, catalogo, config


def obter_modulo(request: Request) -> Modulo:
    modulo = getattr(request.app.state, "modulo_profissional", None)
    if modulo is None:
        raise HTTPException(503, "O cadastro de profissionais ainda não foi ligado.")
    return modulo


def registrar_rotas(
    app: FastAPI,
    repo: RepositorioProfissionais | None = None,
    catalogo: CatalogoProfissional | None = None,
) -> None:
    """Liga as rotas. Sem adaptador Postgres, passe `repo`/`catalogo` (ou use os de memória)."""
    app.include_router(router)
    if repo is not None and catalogo is not None:
        app.state.modulo_profissional = Modulo(repo, catalogo, obter_config_profissional())


def modulo_em_memoria(app: FastAPI) -> Modulo:
    """Só para teste e demonstração local: repositório e catálogo em memória."""
    modulo = Modulo(ProfissionaisEmMemoria(), CatalogoEmMemoria(), obter_config_profissional())
    app.state.modulo_profissional = modulo
    return modulo


# --- Validação ---------------------------------------------------------------------------


def _texto(valor: str | None, campo: str, maximo: int) -> str | None:
    if not valor or not valor.strip():
        return None
    return limpar_texto(valor, campo, maximo, obter_config_seguranca())


def _categorias(modulo: Modulo, ids: list[str]) -> tuple[str, ...]:
    unicas = tuple(dict.fromkeys(ids))
    if len(unicas) > modulo.config.categorias_max:
        raise HTTPException(422, f"Escolha no máximo {modulo.config.categorias_max} categorias.")
    ativas = modulo.catalogo.categorias_ativas()
    if any(c not in ativas for c in unicas):
        raise HTTPException(422, "Uma das categorias não existe ou não está ativa.")
    return unicas


def _regioes(modulo: Modulo, itens: list[RegiaoIO]) -> tuple[Regiao, ...]:
    if len(itens) > modulo.config.regioes_max:
        raise HTTPException(422, f"Informe no máximo {modulo.config.regioes_max} regiões.")
    cidades = modulo.catalogo.cidades_ativas()
    saida: dict[tuple[str, str], Regiao] = {}
    for r in itens:
        if r.cidade_id not in cidades:
            raise HTTPException(422, "Uma das cidades não existe ou não está ativa.")
        bairro = _texto(r.bairro, "bairro", 80)
        saida[(r.cidade_id, (bairro or "").lower())] = Regiao(r.cidade_id, bairro)
    return tuple(saida.values())


def _disponibilidade(modulo: Modulo, itens: list[JanelaIO]) -> tuple[JanelaSemanal, ...]:
    if len(itens) > modulo.config.disponibilidade_max:
        raise HTTPException(422, "Janelas de disponibilidade demais.")
    for j in itens:
        if not (_HORA.match(j.inicio) and _HORA.match(j.fim)) or j.fim <= j.inicio:
            raise HTTPException(422, "Horário inválido: use HH:MM e o fim depois do início.")
    return tuple(JanelaSemanal(j.dia_semana, j.inicio, j.fim) for j in itens)


def _portfolio(modulo: Modulo, itens: list[PortfolioIO]) -> tuple[ItemPortfolio, ...]:
    if len(itens) > modulo.config.portfolio_max:
        raise HTTPException(422, f"No máximo {modulo.config.portfolio_max} itens no portfólio.")
    return tuple(
        ItemPortfolio(_texto(i.titulo, "título", 120) or "", _texto(i.descricao, "descrição", 600))
        for i in itens
    )


def _bio(modulo: Modulo, bio: str | None) -> str | None:
    return _texto(bio, "bio", modulo.config.bio_max_chars)


def _perfil_out(modulo: Modulo, p: PerfilProfissional) -> PerfilProfissionalOut:
    return PerfilProfissionalOut(
        usuario_id=p.usuario_id,
        status=p.status,
        nivel_verificacao=p.nivel_verificacao,
        nivel_verificacao_exigido=modulo.config.nivel_exigido(slugs(modulo.catalogo, p.categorias)),
        bio=p.bio,
        categorias=list(p.categorias),
        regioes=[RegiaoIO(cidade_id=r.cidade_id, bairro=r.bairro) for r in p.regioes],
        disponibilidade=[JanelaIO(**vars(j)) for j in p.disponibilidade],
        portfolio=[PortfolioIO(**vars(i)) for i in p.portfolio],
    )


# --- Rotas -------------------------------------------------------------------------------


@router.post(
    "/profissional/cadastro",
    response_model=PerfilProfissionalOut,
    status_code=201,
    summary="Cadastrar-se como profissional",
    description=(
        "Categorias e cidades precisam estar ativas. O perfil nasce `em_analise`; a verificação "
        "(`/v1/profissional/verificacao`) decide quando ele aparece para os clientes."
    ),
)
def cadastrar(
    corpo: CadastroIn,
    usuario: Usuario = Depends(_pessoa),
    contexto: Contexto = Depends(obter_contexto),
    modulo: Modulo = Depends(obter_modulo),
) -> PerfilProfissionalOut:
    if modulo.repo.obter(usuario.id) is not None:
        raise HTTPException(409, "Você já tem cadastro de profissional.")
    perfil = PerfilProfissional(
        usuario_id=usuario.id,
        status="em_analise",
        bio=_bio(modulo, corpo.bio),
        categorias=_categorias(modulo, corpo.categorias),
        regioes=_regioes(modulo, corpo.regioes),
        disponibilidade=_disponibilidade(modulo, corpo.disponibilidade),
        portfolio=_portfolio(modulo, corpo.portfolio),
        criado_em=contexto.agora(),
    )
    modulo.repo.salvar(perfil)
    return _perfil_out(modulo, perfil)


def _perfil_do_usuario(modulo: Modulo, usuario: Usuario) -> PerfilProfissional:
    perfil = modulo.repo.obter(usuario.id)
    if perfil is None:
        raise HTTPException(404, "Você ainda não se cadastrou como profissional.")
    return perfil


@router.get("/profissional/perfil", response_model=PerfilProfissionalOut, summary="Meu perfil")
def meu_perfil_profissional(
    usuario: Usuario = Depends(_pessoa), modulo: Modulo = Depends(obter_modulo)
) -> PerfilProfissionalOut:
    return _perfil_out(modulo, _perfil_do_usuario(modulo, usuario))


@router.patch(
    "/profissional/perfil",
    response_model=PerfilProfissionalOut,
    summary="Editar meu perfil (só os campos enviados)",
    description="Status e nível de verificação não se editam aqui: só a equipe os muda.",
)
def editar_perfil(
    corpo: PerfilEditarIn,
    usuario: Usuario = Depends(_pessoa),
    modulo: Modulo = Depends(obter_modulo),
) -> PerfilProfissionalOut:
    atual = _perfil_do_usuario(modulo, usuario)
    enviados = corpo.model_fields_set
    novo = PerfilProfissional(
        usuario_id=atual.usuario_id,
        status=atual.status,
        nivel_verificacao=atual.nivel_verificacao,
        criado_em=atual.criado_em,
        bio=_bio(modulo, corpo.bio) if "bio" in enviados else atual.bio,
        categorias=_categorias(modulo, corpo.categorias)
        if corpo.categorias is not None
        else atual.categorias,
        regioes=_regioes(modulo, corpo.regioes) if corpo.regioes is not None else atual.regioes,
        disponibilidade=_disponibilidade(modulo, corpo.disponibilidade)
        if corpo.disponibilidade is not None
        else atual.disponibilidade,
        portfolio=_portfolio(modulo, corpo.portfolio)
        if corpo.portfolio is not None
        else atual.portfolio,
    )
    modulo.repo.salvar(novo)
    return _perfil_out(modulo, novo)


def _nome_abreviado(nome: str | None) -> str | None:
    partes = (nome or "").split()
    if not partes:
        return None
    return partes[0] if len(partes) == 1 else f"{partes[0]} {partes[-1][0]}."


# --- Catálogo e busca ----------------------------------------------------------------------


class CategoriaOut(BaseModel):
    id: str
    nome: str
    slug: str
    icone: str | None
    pai_id: str | None


class CidadeOut(BaseModel):
    id: str
    nome: str
    uf: str


class ProfissionalBuscaOut(BaseModel):
    id: str
    nome: str | None = Field(description="Abreviado (primeiro nome e inicial do último).")
    bio: str | None
    nivel_verificacao: str
    nota_publica: float | None
    servicos_concluidos: int | None
    categorias: list[str] = Field(description="Ids das categorias em que atua (não suspensas).")


class BuscaProfissionaisOut(BaseModel):
    itens: list[ProfissionalBuscaOut]
    pagina: int
    limite: int
    total: int
    tem_mais: bool


@router.get(
    "/catalogo/categorias",
    response_model=list[CategoriaOut],
    summary="Categorias ativas (para o cadastro e a busca)",
    description="Só categorias ativas, na ordem do catálogo. Exige login; não traz dado pessoal.",
)
def catalogo_categorias(
    _: Usuario = Depends(usuario_atual), modulo: Modulo = Depends(obter_modulo)
) -> list[CategoriaOut]:
    return [CategoriaOut(**vars(c)) for c in modulo.catalogo.categorias_publicas()]


@router.get(
    "/catalogo/cidades",
    response_model=list[CidadeOut],
    summary="Cidades ativas (para o cadastro e a busca)",
    description="Só cidades onde o Trato atende, em ordem alfabética. Exige login.",
)
def catalogo_cidades(
    _: Usuario = Depends(usuario_atual), modulo: Modulo = Depends(obter_modulo)
) -> list[CidadeOut]:
    return [CidadeOut(**vars(c)) for c in modulo.catalogo.cidades_publicas()]


def _normalizar(texto: str) -> str:
    sem_acento = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    return " ".join(sem_acento.casefold().split())


def _categorias_do_servico(modulo: Modulo, servico: str) -> set[str]:
    """Ids das categorias cujo nome ou slug contém o texto (e as filhas delas)."""
    busca = _normalizar(servico)
    todas = modulo.catalogo.categorias_publicas()
    achadas = {c.id for c in todas if busca in _normalizar(c.nome) or busca in _normalizar(c.slug)}
    return achadas | {c.id for c in todas if c.pai_id in achadas}


@router.get(
    "/profissionais",
    response_model=BuscaProfissionaisOut,
    summary="Buscar profissionais por serviço, categoria ou bairro",
    description=(
        "Só profissionais APROVADOS. Sem documento, telefone, e-mail nem endereço; o nome sai "
        "abreviado. `servico` procura no nome da categoria (sem acento, sem maiúsculas); "
        "`categoria_id` é exato; `cidade_id` e `bairro` filtram a região (quem atende a cidade "
        "toda também entra). Ordem: melhor nota, mais serviços. Paginada (`pagina` a partir de 1)."
    ),
)
def buscar_profissionais(
    servico: Annotated[str | None, Query(min_length=2, max_length=80)] = None,
    categoria_id: Annotated[str | None, Query(max_length=64)] = None,
    cidade_id: Annotated[str | None, Query(max_length=64)] = None,
    bairro: Annotated[str | None, Query(min_length=2, max_length=80)] = None,
    pagina: Annotated[int, Query(ge=1, le=1000)] = 1,
    limite: Annotated[int, Query(ge=1, le=50)] = 20,
    _: Usuario = Depends(_pessoa),
    contexto: Contexto = Depends(obter_contexto),
    modulo: Modulo = Depends(obter_modulo),
) -> BuscaProfissionaisOut:
    categorias: set[str] | None = None
    if servico is not None:
        categorias = _categorias_do_servico(modulo, servico)
    if categoria_id is not None:
        categorias = {categoria_id} if categorias is None else categorias & {categoria_id}
    vazio = BuscaProfissionaisOut(itens=[], pagina=pagina, limite=limite, total=0, tem_mais=False)
    if categorias is not None and not categorias:
        return vazio
    filtro = FiltroBusca(
        categoria_ids=frozenset(categorias) if categorias is not None else None,
        cidade_id=cidade_id,
        bairro=bairro,
        limite=limite,
        deslocamento=(pagina - 1) * limite,
    )
    achados, total = modulo.repo.buscar(filtro, contexto.usuarios.detalhe)
    return BuscaProfissionaisOut(
        itens=[
            ProfissionalBuscaOut(
                id=r.usuario_id,
                nome=_nome_abreviado(r.nome),
                bio=r.bio,
                nivel_verificacao=r.nivel_verificacao,
                nota_publica=r.nota_publica,
                servicos_concluidos=r.servicos_concluidos,
                categorias=list(r.categorias),
            )
            for r in achados
        ],
        pagina=pagina,
        limite=limite,
        total=total,
        tem_mais=pagina * limite < total,
    )


@router.get(
    "/profissionais/{profissional_id}",
    response_model=PerfilPublicoOut,
    summary="Perfil público do profissional (com as avaliações recebidas)",
    description=(
        "Só profissionais aprovados aparecem. Sem documento, telefone, e-mail, endereço nem "
        "o nome completo; a avaliação não mostra quem avaliou."
    ),
)
def perfil_publico(
    profissional_id: str,
    _: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
    modulo: Modulo = Depends(obter_modulo),
) -> PerfilPublicoOut:
    perfil = modulo.repo.obter(profissional_id)
    if perfil is None or perfil.status != "aprovado":
        raise HTTPException(404, "Profissional não encontrado.")
    detalhe = contexto.usuarios.detalhe(profissional_id) or PerfilDetalhe(
        profissional_id, None, PapelUsuario.PROFISSIONAL
    )
    recebidas = getattr(contexto.avaliacoes, "recebidas", None)
    avaliacoes = recebidas(profissional_id) if recebidas else ()
    base = _perfil_out(modulo, perfil)
    nomes = {
        c.id: f"{c.nome}/{c.uf}" if c.uf else c.nome for c in modulo.catalogo.cidades_publicas()
    }
    return PerfilPublicoOut(
        no_trato_desde=perfil.criado_em,
        cidades=list(
            dict.fromkeys(nomes[r.cidade_id] for r in perfil.regioes if r.cidade_id in nomes)
        ),
        id=perfil.usuario_id,
        nome=_nome_abreviado(detalhe.nome),
        bio=base.bio,
        nivel_verificacao=perfil.nivel_verificacao,
        nota_publica=detalhe.nota_publica,
        servicos_concluidos=detalhe.servicos_concluidos,
        categorias=base.categorias,
        regioes=base.regioes,
        disponibilidade=base.disponibilidade,
        portfolio=base.portfolio,
        avaliacoes=[
            AvaliacaoRecebidaOut(
                nota_geral=a.nota_geral,
                comentario=a.comentario,
                etiquetas=list(a.etiquetas),
                criada_em=a.criada_em,
            )
            for a in avaliacoes
            if a.direcao == "cliente_para_profissional"
        ],
    )
