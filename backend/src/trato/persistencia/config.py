"""Configuração versionada no Postgres (`config_versoes`, `config_parametros`, faixas de taxa).

Nenhum número de negócio mora no código: prazos, taxa e adiantamento vêm da versão VIGENTE.
Se a versão ou o parâmetro não existe, a regra que precisa dele responde 503 (`ConfigNaoPublicada`).
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import psycopg

from trato.api.repositorios import ConfigApi
from trato.disputas import ConfigDisputa
from trato.garantias import ConfigGarantia
from trato.pagamentos.taxa import ConfigTaxa, calcular_taxa
from trato.pedidos.estados import PrazosPedido
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import ConfigNaoPublicada

# Chaves de `config_definicoes` (docs/modelo-de-dados.md, seção 4.3).
CHAVES_DISPUTA = (
    "prazo_resposta_disputa_horas",
    "prazo_decisao_disputa_dias_uteis",
    "prazo_congelar_disputa_horas",
)


def versao_vigente(con: psycopg.Connection[Any]) -> str:
    linha = con.execute("select id from public.config_versoes where status = 'vigente'").fetchone()
    if linha is None:
        raise ConfigNaoPublicada("Ainda não há versão de configuração vigente.")
    return str(linha["id"])


def parametros_globais(con: psycopg.Connection[Any], versao_id: str) -> dict[str, int]:
    linhas = con.execute(
        "select chave, valor from public.config_parametros "
        "where versao_id = %s and escopo_tipo = 'global'",
        (versao_id,),
    ).fetchall()
    return {linha["chave"]: int(linha["valor"]) for linha in linhas}


def exigir(parametros: dict[str, int], chave: str) -> int:
    if chave not in parametros:
        raise ConfigNaoPublicada(f"A configuração '{chave}' ainda não foi publicada.")
    return parametros[chave]


def taxa_bps_da_faixa(con: psycopg.Connection[Any], versao_id: str, valor_centavos: int) -> int:
    """Taxa (bps) da faixa em que o valor cai. Faixa: de <= valor < ate (ate vazio = sem teto).

    ATENÇÃO: o texto "taxa progressiva" ainda tem a interpretação em aberto (P2): aqui a taxa da
    faixa vale para o valor INTEIRO, não por degrau. Trocar aqui quando o João decidir.
    """
    linha = con.execute(
        "select taxa_bps from public.config_faixas_taxa "
        "where versao_id = %s and escopo_tipo = 'global' and de_centavos <= %s "
        "and (ate_centavos is null or %s < ate_centavos) order by de_centavos desc limit 1",
        (versao_id, valor_centavos, valor_centavos),
    ).fetchone()
    if linha is None:
        raise ConfigNaoPublicada("As faixas de taxa (P2) ainda não foram publicadas.")
    return int(linha["taxa_bps"])


def taxa_da_versao(
    con: psycopg.Connection[Any], versao_id: str, valor_centavos: int, parametros: dict[str, int]
) -> ConfigTaxa:
    """A taxa da versão (faixa + mínimo): a única fonte, usada no contrato, na calculadora e na
    liquidação. O mínimo é o parâmetro `taxa_minima_centavos` (ausente = sem mínimo)."""
    return ConfigTaxa(
        taxa_bps=taxa_bps_da_faixa(con, versao_id, valor_centavos),
        taxa_minima_centavos=parametros.get("taxa_minima_centavos", 0),
    )


def taxa_do_valor(config: ConfigTaxa, valor_centavos: int) -> int:
    """Taxa em centavos: percentual ou mínimo, nunca acima do valor (mesma conta do Python)."""
    return calcular_taxa(valor_centavos, config) if valor_centavos > 0 else 0


def _horas(parametros: dict[str, int], chave: str) -> timedelta | None:
    return timedelta(hours=parametros[chave]) if chave in parametros else None


class ConfigPostgres:
    """`ProvedorConfig` lendo a versão vigente. Lê a cada chamada (são 3 consultas pequenas)."""

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def carregar(self) -> ConfigApi:
        with self._banco.transacao() as con:
            versao = versao_vigente(con)
            p = parametros_globais(con, versao)
            por_categoria = {
                str(linha["id"]): int(linha["garantia_retrabalho_dias"])
                for linha in con.execute(
                    "select id, garantia_retrabalho_dias from public.categorias "
                    "where garantia_retrabalho_dias is not null"
                ).fetchall()
            }
        padrao = ConfigGarantia()
        return ConfigApi(
            prazos_pedido=PrazosPedido(
                receber_orcamentos=_horas(p, "validade_pedido_horas"),
                pagamento=_horas(p, "prazo_pagamento_pendente_horas"),
                tolerancia_comparecimento=_horas(p, "tolerancia_comparecimento_horas"),
                confirmacao_cliente=_horas(p, "prazo_confirmacao_cliente_horas"),
            ),
            disputas=ConfigDisputa(
                prazo_resposta_horas=exigir(p, "prazo_resposta_disputa_horas"),
                prazo_decisao_dias_uteis=exigir(p, "prazo_decisao_disputa_dias_uteis"),
                prazo_congelar_repasse_horas=exigir(p, "prazo_congelar_disputa_horas"),
            ),
            garantias=ConfigGarantia(
                garantia_dias_padrao=p.get(
                    "garantia_retrabalho_dias_padrao", padrao.garantia_dias_padrao
                ),
                prazo_atendimento_dias=p.get(
                    "prazo_retrabalho_atendimento_dias", padrao.prazo_atendimento_dias
                ),
                garantia_dias_por_categoria=por_categoria,
            ),
        )
