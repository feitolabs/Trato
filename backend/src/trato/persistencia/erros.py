"""Erros de persistência em termos do domínio.

O banco recusa o que viola uma regra (gatilho, restrição, chave repetida). Aqui o erro cru do
Postgres vira um erro nosso, com mensagem em português e sem vazar nome de tabela ou SQL.
"""

from __future__ import annotations

import logging
import re

import psycopg
from psycopg import errors as pg

_log = logging.getLogger(__name__)
_UUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")


def texto_seguro(mensagem: str | None, padrao: str) -> str:
    """Texto do gatilho para a resposta, sem uuid (o detalhe vai para o log)."""
    if not mensagem:
        return padrao
    if _UUID.search(mensagem):
        _log.warning("Recusa do banco com identificador: %s", mensagem)
        return padrao
    return mensagem


class ErroPersistencia(Exception):
    """Base. A API traduz em resposta 4xx/5xx (ver `trato.api.erros`)."""


class NaoEncontrado(ErroPersistencia):
    """O registro pedido não existe (ou não é visível)."""


class RegraDoBanco(ErroPersistencia):
    """Um gatilho ou restrição do banco recusou a gravação (imutável, total que não fecha...)."""


class ConflitoDeEstado(ErroPersistencia):
    """Outra requisição mudou o registro antes desta (compare-and-set falhou). Ler de novo."""


class Duplicado(ErroPersistencia):
    """Já existe um registro igual (chave única)."""


class DadosInvalidos(ErroPersistencia):
    """Faltou dado, ou o dado tem formato/valor inválido."""


class ConfigNaoPublicada(ErroPersistencia):
    """A configuração versionada ainda não tem o valor que a regra precisa."""


class BancoIndisponivel(ErroPersistencia):
    """Sem conexão com o banco."""


def traduzir(erro: psycopg.Error) -> ErroPersistencia:
    """Traduz o erro do psycopg. Mensagens de gatilho (`raise exception`) são nossas e seguras."""
    if isinstance(erro, pg.UniqueViolation):
        return Duplicado("Esse registro já existe.")
    if isinstance(erro, pg.ForeignKeyViolation):
        return DadosInvalidos("Referência inexistente (usuário, categoria, cidade ou pedido).")
    if isinstance(erro, pg.NotNullViolation):
        return DadosInvalidos("Falta um dado obrigatório.")
    if isinstance(erro, pg.CheckViolation | pg.RestrictViolation):
        if erro.diag.constraint_name:  # CHECK da tabela: a mensagem do Postgres cita colunas
            return RegraDoBanco("O valor informado não é permitido.")
        return RegraDoBanco(texto_seguro(erro.diag.message_primary, "O banco recusou a gravação."))
    if isinstance(erro, pg.DataError):
        return DadosInvalidos("Dado em formato inválido.")
    if isinstance(erro, pg.InsufficientPrivilege):
        return ErroPersistencia("O backend não tem permissão para essa operação no banco.")
    if isinstance(erro, pg.SerializationFailure | pg.DeadlockDetected | pg.LockNotAvailable):
        # Duas requisições disputaram o mesmo registro (ex.: duplo toque em "aceitar"): é um
        # conflito de estado (409), não banco fora do ar (503).
        return ConflitoDeEstado("Outra ação mexeu nisso ao mesmo tempo. Tente de novo.")
    if isinstance(erro, psycopg.OperationalError | psycopg.InterfaceError):
        return BancoIndisponivel("Banco de dados indisponível.")
    _log.error("Erro no Postgres não tratado especificamente (%s): %s", type(erro).__name__, erro, exc_info=True)
    return ErroPersistencia("Erro ao acessar o banco de dados.")
