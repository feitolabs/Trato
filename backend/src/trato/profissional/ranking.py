"""Ranking de profissionais na busca: média ponderada (bayesiana) e nota composta.

Só o backend calcula; o app apenas mostra a ordem. Os pesos vêm de tabela de configuração
(`ranking_config`), nunca do código. Só entram dados que existem e são confiáveis hoje:
nota e quantidade de avaliações, serviços concluídos, nível de verificação e disponibilidade
agora. Pontualidade, taxa de aceite e tempo de resposta ficam de fora até haver dado confiável.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

_LOG = logging.getLogger(__name__)

# Quanto cada nível de verificação vale, de 0 a 1.
_VALOR_VERIFICACAO = {"verificado_plus": 1.0, "verificado": 0.6}


@dataclass(frozen=True)
class ConfigRanking:
    nota_prior: float = 4.0  # nota assumida para quem tem poucas avaliações
    prior_avaliacoes: int = 5  # "peso" da nota-prior, em número de avaliações
    volume_referencia: int = 20  # serviços concluídos que dão a pontuação máxima de volume
    peso_nota: int = 60
    peso_volume: int = 20
    peso_verificacao: int = 10
    peso_disponivel: int = 10


def nota_ponderada(nota: float | None, avaliacoes: int, cfg: ConfigRanking) -> float:
    """Média bayesiana: poucas avaliações puxam a nota para `nota_prior`.

    Quem tem 1 avaliação 5,0 não passa na frente de quem tem 200 avaliações 4,8. Sem avaliação
    vale a nota-prior: profissional novo não fica sempre no fim da fila.
    """
    if nota is None:
        return cfg.nota_prior
    # Com nota existe pelo menos 1 avaliação (a nota é a média delas): protege de contagem a 0.
    n = max(avaliacoes, 1)
    peso = max(cfg.prior_avaliacoes, 0)
    return (n * nota + peso * cfg.nota_prior) / (n + peso)


def pontuacao(
    *,
    nota: float | None,
    avaliacoes: int,
    concluidos: int,
    nivel_verificacao: str | None,
    disponivel_agora: bool,
    cfg: ConfigRanking,
) -> float:
    """Nota composta de 0 a 1 (quanto maior, mais alto na busca)."""
    volume = (
        min(max(concluidos, 0) / cfg.volume_referencia, 1.0) if cfg.volume_referencia > 0 else 0.0
    )
    componentes = (
        (cfg.peso_nota, nota_ponderada(nota, avaliacoes, cfg) / 5),
        (cfg.peso_volume, volume),
        (cfg.peso_verificacao, _VALOR_VERIFICACAO.get(nivel_verificacao or "", 0.0)),
        (cfg.peso_disponivel, 1.0 if disponivel_agora else 0.0),
    )
    soma = sum(max(peso, 0) for peso, _ in componentes)
    if soma <= 0:  # pesos zerados: cai para a média ponderada pura
        return nota_ponderada(nota, avaliacoes, cfg) / 5
    return sum(max(peso, 0) * valor for peso, valor in componentes) / soma


class RankingEmMemoria:
    """Configuração do ranking em memória (testes e demonstração local)."""

    def __init__(self, config: ConfigRanking | None = None) -> None:
        self._config = config or ConfigRanking()

    def config(self) -> ConfigRanking:
        return self._config

    def salvar_config(self, config: ConfigRanking) -> None:
        self._config = config


class RankingPostgres:
    """Lê e grava a linha única de `public.ranking_config`."""

    def __init__(self, banco: Any) -> None:
        self._banco = banco

    def config(self) -> ConfigRanking:
        try:
            with self._banco.transacao() as con:
                l = con.execute(  # noqa: E741
                    "select nota_prior, prior_avaliacoes, volume_referencia, peso_nota, "
                    "peso_volume, peso_verificacao, peso_disponivel from public.ranking_config "
                    "where id"
                ).fetchone()
        except Exception:  # noqa: BLE001 - a busca nunca cai por causa da configuração do ranking
            _LOG.warning("ranking_config ilegível; usando os pesos padrão", exc_info=True)
            return ConfigRanking()
        if l is None:
            return ConfigRanking()
        return ConfigRanking(
            nota_prior=float(l["nota_prior"]),
            prior_avaliacoes=int(l["prior_avaliacoes"]),
            volume_referencia=int(l["volume_referencia"]),
            peso_nota=int(l["peso_nota"]),
            peso_volume=int(l["peso_volume"]),
            peso_verificacao=int(l["peso_verificacao"]),
            peso_disponivel=int(l["peso_disponivel"]),
        )

    def salvar_config(self, config: ConfigRanking) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "update public.ranking_config set nota_prior = %s, prior_avaliacoes = %s, "
                "volume_referencia = %s, peso_nota = %s, peso_volume = %s, "
                "peso_verificacao = %s, peso_disponivel = %s, atualizado_em = now() where id",
                (
                    config.nota_prior,
                    config.prior_avaliacoes,
                    config.volume_referencia,
                    config.peso_nota,
                    config.peso_volume,
                    config.peso_verificacao,
                    config.peso_disponivel,
                ),
            )
