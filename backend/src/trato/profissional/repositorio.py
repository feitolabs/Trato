"""Perfil do profissional: dados, interfaces e a versão em memória (não é o armazenamento real).

O adaptador Postgres (`perfis_profissional`, `profissional_categorias`, `profissional_regioes`)
ainda não existe; sem ele ligado, as rotas respondem 503.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from typing import TYPE_CHECKING, Protocol
from zoneinfo import ZoneInfo

_FUSO_BRASILIA = ZoneInfo("America/Sao_Paulo")
_SEPARADOR_BUSCA = re.compile(r"[^0-9a-zA-Z]+")


def normalizar_busca(texto: str) -> str:
    """Remove acentos e pontuação, mantendo palavras separadas por espaço único."""
    sem_acento = unicodedata.normalize("NFKD", texto or "").encode("ascii", "ignore").decode()
    return " ".join(_SEPARADOR_BUSCA.sub(" ", sem_acento.casefold()).split())


def nome_publico_busca(nome: str | None) -> str:
    """Forma abreviada visível na busca (primeiro nome + inicial do último)."""
    partes = (nome or "").split()
    if not partes:
        return ""
    return partes[0] if len(partes) == 1 else f"{partes[0]} {partes[-1][0]}."


def dia_semana_hoje() -> int:
    return datetime.now(_FUSO_BRASILIA).weekday()

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
class ContaRecebimento:
    """Conta de liquidação / chave Pix do profissional para recebimento de repasses (D15)."""

    tipo_pix: str  # cpf | cnpj | email | telefone | aleatoria
    chave_pix: str
    banco_codigo: str | None = None
    banco_nome: str | None = None
    agencia: str | None = None
    conta: str | None = None
    tipo_conta: str | None = None  # corrente | poupanca
    atualizada_em: datetime | None = None


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
    # O que o profissional atende. Padrão = só presencial (como os cadastros anteriores).
    atende_presencial: bool = True
    atende_remoto: bool = False
    disponivel_agora: bool = False
    conta_recebimento: ContaRecebimento | None = None


@dataclass(frozen=True)
class CategoriaPublica:
    id: str
    nome: str
    slug: str
    icone: str | None = None
    pai_id: str | None = None
    aceita_remoto: bool = False  # o admin liga por categoria; padrão: só presencial


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
    nota_minima: float | None = None
    atende_hoje: bool = False
    atende_remoto: bool | None = None
    texto: str | None = None
    # Preenchidos pela rota quando há `texto` para permitir casar categoria/cidade em memória.
    categorias_texto: frozenset[str] = field(default_factory=frozenset)
    cidades_texto: frozenset[str] = field(default_factory=frozenset)
    excluir_usuario_id: str | None = None
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
    cidades: tuple[str, ...] = ()
    bairros: tuple[str, ...] = ()
    atende_remoto: bool = False
    _regioes_ids: tuple[Regiao, ...] = ()
    _portfolio_texto: str = ""


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


_PESO_VERIFICACAO = {
    "verificado_plus": 0,
    "verificado": 1,
    "basico": 2,
}


def _correspondencia_texto(
    p: PerfilProfissional,
    nome: str | None,
    filtro: FiltroBusca,
) -> int:
    """Devolve 0 se não há busca textual, >0 para relevância ou -1 se não casa."""
    tokens = [t for t in normalizar_busca(filtro.texto or "").split() if t]
    if not tokens:
        return 0
    nome_pub = normalizar_busca(nome_publico_busca(nome))
    bio = normalizar_busca(p.bio or "")
    portfolio = " ".join(
        normalizar_busca(f"{i.titulo} {i.descricao or ''}") for i in p.portfolio
    )
    bairros = " ".join(normalizar_busca(r.bairro or "") for r in p.regioes)
    cat_casa = bool(filtro.categorias_texto & set(p.categorias))
    cid_casa = any(r.cidade_id in filtro.cidades_texto for r in p.regioes)

    pontos = 0
    for tok in tokens:
        acertou = False
        if tok in nome_pub:
            pontos += 3
            acertou = True
        if cat_casa or tok in bio or tok in portfolio:
            pontos += 2
            acertou = True
        if cid_casa or (bairros and tok in bairros):
            pontos += 1
            acertou = True
        if not acertou:
            return -1
    return pontos


def _match_exato_bairro(p: PerfilProfissional, filtro: FiltroBusca) -> bool:
    bairro = normalizar_busca(filtro.bairro or "")
    if not bairro:
        return False
    return any(
        (filtro.cidade_id is None or r.cidade_id == filtro.cidade_id)
        and r.bairro is not None
        and normalizar_busca(r.bairro) == bairro
        for r in p.regioes
    )


class ProfissionaisEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, PerfilProfissional] = {}

    def obter(self, usuario_id: str) -> PerfilProfissional | None:
        return self._itens.get(usuario_id)

    def salvar(self, perfil: PerfilProfissional) -> None:
        self._itens[perfil.usuario_id] = perfil

    def listar_disponiveis_agora(self) -> list[PerfilProfissional]:
        """Profissionais aprovados com o modo 'Disponível agora' ativo."""
        return [
            p for p in self._itens.values() if p.status == "aprovado" and p.disponivel_agora
        ]

    def buscar(
        self, filtro: FiltroBusca, detalhe: Callable[[str], PerfilDetalhe | None]
    ) -> tuple[list[ResultadoBusca], int]:
        hoje = dia_semana_hoje() if filtro.atende_hoje else None
        ranqueados: list[tuple[tuple[object, ...], ResultadoBusca]] = []
        for p in self._itens.values():
            if p.status != "aprovado":
                continue
            if filtro.excluir_usuario_id and p.usuario_id == filtro.excluir_usuario_id:
                continue
            if filtro.categoria_ids is not None and not filtro.categoria_ids & set(p.categorias):
                continue
            if filtro.atende_remoto is not None and p.atende_remoto != filtro.atende_remoto:
                continue
            if not _atende(p, filtro):
                continue
            if hoje is not None and not any(j.dia_semana == hoje for j in p.disponibilidade):
                continue
            d = detalhe(p.usuario_id)
            nome = d.nome if d else None
            pontos_texto = _correspondencia_texto(p, nome, filtro)
            if pontos_texto < 0:
                continue
            nota = d.nota_publica if d else None
            if filtro.nota_minima is not None and (nota is None or nota < filtro.nota_minima):
                continue
            bairros = tuple(
                dict.fromkeys(r.bairro.strip() for r in p.regioes if r.bairro and r.bairro.strip())
            )
            resultado = ResultadoBusca(
                p.usuario_id,
                nome,
                p.bio,
                p.nivel_verificacao,
                nota,
                d.servicos_concluidos if d else None,
                p.categorias,
                bairros=bairros,
                atende_remoto=p.atende_remoto,
                _regioes_ids=p.regioes,
            )
            chave = (
                -pontos_texto,
                nota is None,
                -(nota or 0),
                -(d.servicos_concluidos if d and d.servicos_concluidos else 0),
                not _match_exato_bairro(p, filtro),
                _PESO_VERIFICACAO.get(p.nivel_verificacao, 9),
                not bool((p.bio or "").strip()),
                p.usuario_id,
            )
            ranqueados.append((chave, resultado))
        ranqueados.sort(key=lambda par: par[0])
        achados = [par[1] for par in ranqueados]
        return achados[filtro.deslocamento : filtro.deslocamento + filtro.limite], len(achados)


def _atende(p: PerfilProfissional, filtro: FiltroBusca) -> bool:
    if filtro.cidade_id is None and filtro.bairro is None:
        return True
    bairro = normalizar_busca(filtro.bairro or "")
    for r in p.regioes:
        if filtro.cidade_id is not None and r.cidade_id != filtro.cidade_id:
            continue
        if bairro and r.bairro is not None and normalizar_busca(r.bairro) != bairro:
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
            for i, slug in sorted(
                self.categorias.items(),
                key=lambda kv: (normalizar_busca(self.nomes.get(kv[0], kv[1])), kv[0]),
            )
        ]

    def cidades_publicas(self) -> list[CidadePublica]:
        return sorted(
            (CidadePublica(i, self.nomes.get(i, i), self.ufs.get(i, "")) for i in self.cidades),
            key=lambda c: (c.nome, c.id),
        )


def slugs(catalogo: CatalogoProfissional, ids: Sequence[str]) -> list[str]:
    ativas = catalogo.categorias_ativas()
    return [ativas[i] for i in ids if i in ativas]
