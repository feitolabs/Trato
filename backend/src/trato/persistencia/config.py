"""Configuração versionada no Postgres (`config_versoes`, `config_parametros`, faixas de taxa).

Nenhum número de negócio mora no código: prazos, taxa e adiantamento vêm da versão VIGENTE.
Se a versão ou o parâmetro não existe, a regra que precisa dele responde 503 (`ConfigNaoPublicada`).
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import psycopg

from trato.api.repositorios import PRAZO_AVALIACAO_PADRAO_DIAS, ConfigApi
from trato.disputas import ConfigDisputa
from trato.garantias import ConfigGarantia
from trato.garantias.config import garantia_minima_do_slug
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


def _horas(parametros: dict[str, int], chave: str) -> timedelta | None:
    return timedelta(hours=parametros[chave]) if chave in parametros else None


class ConfigPostgres:
    """`ProvedorConfig` lendo a versão vigente. Lê a cada chamada (são 3 consultas pequenas)."""

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def parametro_inteiro(self, chave: str) -> int | None:
        """Valor publicado (global) na versão vigente; `None` sem versão ou sem o parâmetro,
        e quem chama usa o próprio padrão."""
        with self._banco.transacao() as con:
            linha = con.execute(
                "select p.valor from public.config_parametros p "
                "join public.config_versoes v on v.id = p.versao_id "
                "where v.status = 'vigente' and p.escopo_tipo = 'global' and p.chave = %s",
                (chave,),
            ).fetchone()
        return None if linha is None else int(linha["valor"])

    def carregar(self) -> ConfigApi:
        with self._banco.transacao() as con:
            versao = versao_vigente(con)
            p = parametros_globais(con, versao)
            categorias = con.execute(
                "select id, slug, garantia_retrabalho_dias from public.categorias"
            ).fetchall()
            por_categoria = {
                str(linha["id"]): int(linha["garantia_retrabalho_dias"])
                for linha in categorias
                if linha["garantia_retrabalho_dias"] is not None
            }
            minimos = {
                str(linha["id"]): garantia_minima_do_slug(linha["slug"]) for linha in categorias
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
                minimo_dias_por_categoria=minimos,
            ),
            valor_maximo_servico_centavos=p.get("valor_maximo_servico_centavos"),
            limite_orcamentos_por_pedido=p.get("limite_orcamentos_por_pedido"),
            prazo_liberacao_dias=p.get("prazo_liberacao_dias"),
            lembrete_confirmacao_antecedencia_horas=p.get(
                "lembrete_confirmacao_antecedencia_horas", 12
            ),
            lembrete_resposta_disputa_antecedencia_horas=p.get(
                "lembrete_resposta_disputa_antecedencia_horas", 12
            ),
            tratinhos_aviso_vencimento_dias=p.get("tratinhos_aviso_vencimento_dias", 7),
            prazo_avaliacao_dias=p.get("prazo_avaliacao_dias", PRAZO_AVALIACAO_PADRAO_DIAS),
            arrependimento_dias=max(7, p.get("arrependimento_dias", 7)),
            ausencia_espera_minutos=max(20, p.get("ausencia_espera_minutos", 20)),
            ausencia_justificativa_horas=max(24, p.get("ausencia_justificativa_horas", 24)),
            ausencia_retencao_max_bps=min(3000, p.get("ausencia_retencao_max_bps", 3000)),
            ausencia_exigir_chegada=bool(p.get("ausencia_exigir_chegada", False)),
            ausencia_contestacao_dias_uteis=max(5, p.get("ausencia_contestacao_dias_uteis", 5)),
            ausencia_revisao_dias_uteis=p.get("ausencia_revisao_dias_uteis", 10),
            sac_resposta_dias_uteis=min(5, p.get("sac_resposta_dias_uteis", 5)),
            incidente_seguranca_cautela_horas=max(
                1, min(24, p.get("incidente_seguranca_cautela_horas", 24))
            ),
            disputa_contestacao_prazo_dias_uteis=max(
                5, p.get("disputa_contestacao_prazo_dias_uteis", 5)
            ),
            disputa_contestacao_resposta_dias_uteis=max(
                1, min(10, p.get("disputa_contestacao_resposta_dias_uteis", 10))
            ),
            sac_dados_pessoais_dias=min(15, p.get("sac_dados_pessoais_dias", 15)),
            exclusividade_profissional_ofertada=bool(
                p.get("exclusividade_profissional_ofertada", False)
            ),
        )
