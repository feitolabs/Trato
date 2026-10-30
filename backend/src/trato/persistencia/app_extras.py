"""Verificação do profissional e taxa do Trato no Postgres.

A verificação guarda só REFERÊNCIAS aos arquivos (caminho no bucket privado `verificacao`); o
envio do arquivo em si é por URL assinada, fora desta camada.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime

from trato.api.repositorios_app import DocumentoVerificacao, Verificacao
from trato.persistencia.comum import exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.config import (
    parametros_globais,
    taxa_da_versao,
    taxa_do_valor,
    versao_vigente,
)
from trato.persistencia.erros import NaoEncontrado, RegraDoBanco


class VerificacoesPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def enviar(
        self,
        profissional_id: str,
        nivel: str,
        documentos: Sequence[DocumentoVerificacao],
        agora: datetime,
    ) -> Verificacao:
        pessoa = exigir_uuid(profissional_id, "profissional")
        with self._banco.transacao() as con:
            if (
                con.execute(
                    "select 1 from public.perfis_profissional where usuario_id = %s", (pessoa,)
                ).fetchone()
                is None
            ):
                raise NaoEncontrado("Termine o cadastro de profissional antes de se verificar.")
            if (
                con.execute(
                    "select 1 from public.verificacoes where profissional_id = %s "
                    "and status in ('enviada', 'em_analise')",
                    (pessoa,),
                ).fetchone()
                is not None
            ):
                raise RegraDoBanco("Você já tem uma verificação em análise.")
            nova = con.execute(
                "insert into public.verificacoes (profissional_id, nivel_solicitado, "
                "consentimento_lgpd_em, enviada_em) values (%s, %s, %s, %s) returning id",
                (pessoa, nivel, agora, agora),
            ).fetchone()
            for doc in documentos:
                con.execute(
                    "insert into public.verificacao_documentos (verificacao_id, tipo, "
                    "storage_path, sha256, excluir_em) values (%s, %s, %s, %s, %s)",
                    (nova["id"], doc.tipo, doc.storage_path, doc.sha256, doc.excluir_em),
                )
        return Verificacao(str(nova["id"]), pessoa, nivel, "enviada", agora, tuple(documentos))

    def da_pessoa(self, profissional_id: str) -> Sequence[Verificacao]:
        pessoa = exigir_uuid(profissional_id, "profissional")
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select v.id, v.nivel_solicitado, v.status, v.enviada_em, v.motivo_recusa, "
                "coalesce(json_agg(json_build_object('tipo', d.tipo, 'caminho', d.storage_path) "
                "order by d.criado_em, d.id) filter (where d.id is not null), '[]') as docs "
                "from public.verificacoes v "
                "left join public.verificacao_documentos d on d.verificacao_id = v.id "
                "where v.profissional_id = %s group by v.id order by v.enviada_em desc",
                (pessoa,),
            ).fetchall()
        return tuple(
            Verificacao(
                str(l["id"]),
                pessoa,
                l["nivel_solicitado"],
                l["status"],
                l["enviada_em"],
                tuple(DocumentoVerificacao(d["tipo"], d["caminho"]) for d in l["docs"]),
                l["motivo_recusa"],
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )


class TaxaPostgres:
    """Taxa da versão VIGENTE da configuração: só para o ORÇAMENTO (calculadora). Depois do aceite
    a taxa é a congelada no contrato (A3); a conta é a mesma do contrato (faixa + mínimo)."""

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def calcular(self, valor_centavos: int) -> int:
        with self._banco.transacao() as con:
            versao = versao_vigente(con)
            config = taxa_da_versao(con, versao, valor_centavos, parametros_globais(con, versao))
        return taxa_do_valor(config, valor_centavos)
