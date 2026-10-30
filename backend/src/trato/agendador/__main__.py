"""`python -m trato.agendador`: roda o agendador como serviço (ver docs/backend-notificacoes.md).

  python -m trato.agendador            # laço contínuo (Ctrl+C ou SIGTERM para parar)
  python -m trato.agendador --uma-vez  # um ciclo e sai (bom para cron)

Precisa de TRATO_PERSISTENCIA=postgres e DATABASE_URL no .env. Em modo memória ele recusa:
não há o que agendar sem banco.
"""

from __future__ import annotations

import argparse
import logging
import signal
import threading
from datetime import timedelta

from trato.agendador.ciclo import Agendador
from trato.agendador.config import obter_config_agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_postgres
from trato.agendador.registro import RegistroPostgres
from trato.agendador.trava import TravaAdvisoryPostgres
from trato.api.fabrica import criar_contexto_postgres
from trato.config import obter_config
from trato.notificacoes.canais import canais_da_config
from trato.notificacoes.config import obter_config_notificacoes
from trato.notificacoes.postgres import NotificacoesServicoPostgres
from trato.notificacoes.servico import ServicoNotificacoes
from trato.persistencia.conexao import Banco


def montar() -> tuple[Agendador, Banco, float]:
    config = obter_config()
    if config.trato_persistencia.strip().lower() != "postgres":
        raise SystemExit("O agendador precisa de TRATO_PERSISTENCIA=postgres e DATABASE_URL.")
    dsn = config.database_url.get_secret_value()
    if not dsn:
        raise SystemExit("Defina DATABASE_URL no .env.")
    cfg = obter_config_agendador()
    banco = Banco(dsn, papel=config.trato_banco_papel)
    contexto = criar_contexto_postgres(banco, config)
    cn = obter_config_notificacoes()
    notif = ServicoNotificacoes(
        NotificacoesServicoPostgres(banco), canais_da_config(cn), cn, contexto.agora
    )
    agendador = Agendador(
        FonteContexto(contexto, ids_ativos_postgres(banco, cfg.dias_concluidos_monitorados)),
        ExecutorContexto(contexto, notif),
        RegistroPostgres(banco),
        TravaAdvisoryPostgres(dsn),
        contexto.agora,
        notif,
        timedelta(hours=cfg.lembrete_agenda_horas) if cfg.lembrete_agenda_horas else None,
    )
    return agendador, banco, cfg.intervalo_segundos


def principal() -> None:
    parser = argparse.ArgumentParser(prog="python -m trato.agendador")
    parser.add_argument("--uma-vez", action="store_true", help="roda um ciclo e sai")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    agendador, banco, intervalo = montar()
    parar = threading.Event()
    for sinal in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sinal, lambda *_: parar.set())
    try:
        if args.uma_vez:
            print(agendador.rodar_uma_vez())
        else:
            agendador.rodar_sempre(parar, intervalo)
    finally:
        banco.fechar()


if __name__ == "__main__":
    principal()
