"""Perfil do profissional: dados, interfaces e a versão em memória (não é o armazenamento real).

O adaptador Postgres (`perfis_profissional`, `profissional_categorias`, `profissional_regioes`)
ainda não existe; sem ele ligado, as rotas respondem 503.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol


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


class RepositorioProfissionais(Protocol):
    def obter(self, usuario_id: str) -> PerfilProfissional | None: ...

    def salvar(self, perfil: PerfilProfissional) -> None: ...


class CatalogoProfissional(Protocol):
    def categorias_ativas(self) -> dict[str, str]:
        """id -> slug das categorias ATIVAS."""

    def cidades_ativas(self) -> set[str]: ...


class ProfissionaisEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, PerfilProfissional] = {}

    def obter(self, usuario_id: str) -> PerfilProfissional | None:
        return self._itens.get(usuario_id)

    def salvar(self, perfil: PerfilProfissional) -> None:
        self._itens[perfil.usuario_id] = perfil


@dataclass
class CatalogoEmMemoria:
    categorias: dict[str, str] = field(default_factory=dict)
    cidades: set[str] = field(default_factory=set)

    def categorias_ativas(self) -> dict[str, str]:
        return dict(self.categorias)

    def cidades_ativas(self) -> set[str]:
        return set(self.cidades)


def slugs(catalogo: CatalogoProfissional, ids: Sequence[str]) -> list[str]:
    ativas = catalogo.categorias_ativas()
    return [ativas[i] for i in ids if i in ativas]
