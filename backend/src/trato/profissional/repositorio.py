"""Perfil do profissional: dados, interfaces e a versão em memória (não é o armazenamento real).

O adaptador Postgres (`perfis_profissional`, `profissional_categorias`, `profissional_regioes`)
ainda não existe; sem ele ligado, as rotas respondem 503.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from trato.api.repositorios_app import PerfilDetalhe


@dataclass(frozen=True)
class Regiao:
    cidade_id: str
    bairro: str | None = None


@dataclass(frozen=True)
class JanelaSemanal:
    dia_semana: int  # 0 = segunda ... 6 = domingo
    inicio: str  # HH:MM
    fim: str


@dataclass(frozen=True)
class ItemPortfolio:
    titulo: str
    descricao: str | None = None


@dataclass(frozen=True)
class PerfilProfissional:
    usuario_id: str
    status: str  # em_analise | aprovado | recusado | suspenso
    bio: str | None
    categorias: tuple[str, ...]  # ids de categoria
    regioes: tuple[Regiao, ...]
    disponibilidade: tuple[JanelaSemanal, ...]
    portfolio: tuple[ItemPortfolio, ...]
    criado_em: datetime
    nivel_verificacao: str = "basico"


@dataclass(frozen=True)
class CategoriaPublica:
    id: str
    nome: str
    slug: str
    icone: str | None = None
    pai_id: str | None = None


@dataclass(frozen=True)
class CidadePublica:
    id: str
    nome: str
    uf: str


@dataclass(frozen=True)
class FiltroBusca:
    """Filtros da busca de profissionais. Só profissionais APROVADOS entram, sempre."""

    categoria_ids: frozenset[str] | None = None  # None = qualquer categoria
    cidade_id: str | None = None
    bairro: str | None = None  # quem atende a cidade toda (sem bairro) também entra
    limite: int = 20
    deslocamento: int = 0


@dataclass(frozen=True)
class ResultadoBusca:
    """Só o que a lista mostra: nada de documento, telefone, e-mail nem endereço."""

    usuario_id: str
    nome: str | None  # completo; a rota abrevia
    bio: str | None
    nivel_verificacao: str
    nota_publica: float | None
    servicos_concluidos: int | None
    categorias: tuple[str, ...]


class RepositorioProfissionais(Protocol):
    def obter(self, usuario_id: str) -> PerfilProfissional | None: ...

    def salvar(self, perfil: PerfilProfissional) -> None: ...

    def buscar(
        self, filtro: FiltroBusca, detalhe: Callable[[str], PerfilDetalhe | None]
    ) -> tuple[list[ResultadoBusca], int]:
        """(página, total). Ordem: melhor nota, mais serviços, id. `detalhe` dá nome e nota
        para quem não os guarda (a versão Postgres lê tudo na própria consulta)."""


class CatalogoProfissional(Protocol):
    def categorias_ativas(self) -> dict[str, str]:
        """id -> slug das categorias ATIVAS."""

    def cidades_ativas(self) -> set[str]: ...

    def categorias_publicas(self) -> list[CategoriaPublica]:
        """Categorias ativas, na ordem do catálogo."""

    def cidades_publicas(self) -> list[CidadePublica]:
        """Cidades ativas, em ordem alfabética."""


class ProfissionaisEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, PerfilProfissional] = {}

    def obter(self, usuario_id: str) -> PerfilProfissional | None:
        return self._itens.get(usuario_id)

    def salvar(self, perfil: PerfilProfissional) -> None:
        self._itens[perfil.usuario_id] = perfil

    def buscar(
        self, filtro: FiltroBusca, detalhe: Callable[[str], PerfilDetalhe | None]
    ) -> tuple[list[ResultadoBusca], int]:
        achados = []
        for p in self._itens.values():
            if p.status != "aprovado":
                continue
            if filtro.categoria_ids is not None and not filtro.categoria_ids & set(p.categorias):
                continue
            if not _atende(p, filtro):
                continue
            d = detalhe(p.usuario_id)
            achados.append(
                ResultadoBusca(
                    p.usuario_id,
                    d.nome if d else None,
                    p.bio,
                    p.nivel_verificacao,
                    d.nota_publica if d else None,
                    d.servicos_concluidos if d else None,
                    p.categorias,
                )
            )
        achados.sort(
            key=lambda r: (
                r.nota_publica is None,
                -(r.nota_publica or 0),
                -(r.servicos_concluidos or 0),
                r.usuario_id,
            )
        )
        return achados[filtro.deslocamento : filtro.deslocamento + filtro.limite], len(achados)


def _atende(p: PerfilProfissional, filtro: FiltroBusca) -> bool:
    if filtro.cidade_id is None and filtro.bairro is None:
        return True
    bairro = (filtro.bairro or "").strip().casefold()
    for r in p.regioes:
        if filtro.cidade_id is not None and r.cidade_id != filtro.cidade_id:
            continue
        if bairro and r.bairro is not None and r.bairro.strip().casefold() != bairro:
            continue
        return True
    return False


@dataclass
class CatalogoEmMemoria:
    categorias: dict[str, str] = field(default_factory=dict)
    cidades: set[str] = field(default_factory=set)
    # Opcionais (a demonstração local): nome e UF; sem eles usa o slug / o id.
    nomes: dict[str, str] = field(default_factory=dict)
    ufs: dict[str, str] = field(default_factory=dict)

    def categorias_ativas(self) -> dict[str, str]:
        return dict(self.categorias)

    def cidades_ativas(self) -> set[str]:
        return set(self.cidades)

    def categorias_publicas(self) -> list[CategoriaPublica]:
        return [
            CategoriaPublica(i, self.nomes.get(i, slug), slug)
            for i, slug in sorted(self.categorias.items(), key=lambda kv: kv[1])
        ]

    def cidades_publicas(self) -> list[CidadePublica]:
        return sorted(
            (CidadePublica(i, self.nomes.get(i, i), self.ufs.get(i, "")) for i in self.cidades),
            key=lambda c: (c.nome, c.id),
        )


def slugs(catalogo: CatalogoProfissional, ids: Sequence[str]) -> list[str]:
    ativas = catalogo.categorias_ativas()
    return [ativas[i] for i in ids if i in ativas]
