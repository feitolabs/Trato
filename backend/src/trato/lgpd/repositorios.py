"""Interfaces e modelos de LGPD. A versão em memória está em `memoria.py`.

Em modo Postgres os três repositórios precisam de adaptadores (ver `docs/backend-seguranca.md`:
tabela de consentimentos, de pedidos de exclusão e as consultas de exportação/anonimização).
Eles entram pelo contexto: `contexto.extras["lgpd"] = RepositoriosLgpd(...)`.
"""

from __future__ import annotations

from collections.abc import Sequence
from contextlib import AbstractContextManager
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol


@dataclass(frozen=True)
class Consentimento:
    """Linha de histórico, só se acrescenta (revogar = nova linha com `aceito = False`)."""

    usuario_id: str
    finalidade: str
    aceito: bool
    versao_texto: str
    registrado_em: datetime
    ip: str | None = None


@dataclass(frozen=True)
class PedidoExclusao:
    id: str
    usuario_id: str
    status: str  # aguardando_confirmacao | agendada | concluida | cancelada | expirada
    criado_em: datetime
    token_hash: str | None = None
    token_expira_em: datetime | None = None
    executar_apos: datetime | None = None
    concluido_em: datetime | None = None
    resumo: dict[str, Any] | None = None  # o que foi anonimizado/mantido, sem dado pessoal


class FonteDadosPessoais(Protocol):
    def exportar(self, usuario_id: str) -> dict[str, Any]:
        """Tudo que se sabe do titular, em estruturas JSON."""
        ...

    def exclusivo(self, usuario_id: str) -> AbstractContextManager[None]:
        """Dentro dele, o que for lido nas pendências não muda até a anonimização gravar."""
        ...

    def pendencias(self, usuario_id: str) -> list[str]:
        """Motivos que impedem encerrar agora (pedido em andamento, disputa, valor retido)."""
        ...

    def anonimizar(self, usuario_id: str) -> dict[str, list[str]]:
        """Remove/anonimiza o que a lei permite. NUNCA toca em ledger, auditoria, mensagens nem
        contratos (imutáveis). Devolve {"anonimizado": [...], "mantido": [...]} (só categorias)."""
        ...

    def arquivos_a_remover(self, usuario_id: str) -> list[tuple[str, str]]:
        """(bucket, caminho) dos documentos anonimizados e ainda não confirmados como apagados."""
        ...

    def pastas_temporarias(self, usuario_id: str) -> list[tuple[str, str]]:
        """(bucket, pasta) de envios sem valor de prova: apaga tudo dentro."""
        ...

    def limpeza_concluida(self, usuario_id: str, removidos: int) -> None: ...

    def limpezas_pendentes(self) -> list[str]:
        """Contas anonimizadas cujos arquivos ainda não foram todos apagados."""
        ...


class RepositorioConsentimentos(Protocol):
    def registrar(self, consentimento: Consentimento) -> None: ...
    def historico(self, usuario_id: str) -> Sequence[Consentimento]: ...


class RepositorioExclusoes(Protocol):
    def salvar(self, pedido: PedidoExclusao) -> bool:
        """Grava só pedido em aberto (ou novo). `False`: já estava encerrado, nada mudou."""
        ...

    def ativo_do_usuario(self, usuario_id: str) -> PedidoExclusao | None:
        """Pedido em `aguardando_confirmacao` ou `agendada` (no máximo um)."""
        ...

    def agendadas_ate(self, agora: datetime) -> Sequence[PedidoExclusao]: ...
    def novo_id(self) -> str: ...


@dataclass
class RepositoriosLgpd:
    fonte: FonteDadosPessoais
    consentimentos: RepositorioConsentimentos
    exclusoes: RepositorioExclusoes
