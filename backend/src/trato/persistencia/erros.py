"""Erros de persistência em termos do domínio.

O banco recusa o que viola uma regra (gatilho, restrição, chave repetida). Aqui o erro cru do
Postgres vira um erro nosso, com mensagem em português e sem vazar nome de tabela ou SQL.
"""

from __future__ import annotations

import psycopg
from psycopg import errors as pg


class ErroPersistencia(Exception):
    """Base. A API traduz em resposta 4xx/5xx (ver `trato.api.erros`)."""


class NaoEncontrado(ErroPersistencia):
    """O registro pedido não existe (ou não é visível)."""


class RegraDoBanco(ErroPersistencia):
    """Um gatilho ou restrição do banco recusou a gravação (imutável, total que não fecha...)."""


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
        return RegraDoBanco(erro.diag.message_primary or "O banco recusou a gravação.")
    if isinstance(erro, pg.DataError):
        return DadosInvalidos("Dado em formato inválido.")
    if isinstance(erro, pg.InsufficientPrivilege):
        return ErroPersistencia("O backend não tem permissão para essa operação no banco.")
    if isinstance(erro, psycopg.OperationalError | psycopg.InterfaceError):
        return BancoIndisponivel("Banco de dados indisponível.")
    return ErroPersistencia("Erro ao gravar no banco.")
