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
from trato.agendador.config import ConfigAgendador, obter_config_agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_postgres
from trato.agendador.registro import RegistroPostgres
from trato.agendador.trava import TravaAdvisoryPostgres
from trato.api.fabrica import criar_contexto_postgres, montar_servico_pagamento
from trato.config import obter_config
from trato.notificacoes.canais import canais_da_config
from trato.notificacoes.config import obter_config_notificacoes
from trato.notificacoes.postgres import EmailsDaContaPostgres, NotificacoesServicoPostgres
from trato.notificacoes.servico import ServicoNotificacoes
from trato.persistencia.acessos import AcessosPostgres
from trato.persistencia.conexao import Banco


def rotina_de_expurgo(banco: Banco, cfg: ConfigAgendador):  # type: ignore[no-untyped-def]
    """None enquanto a configuração não ligar explicitamente (padrão)."""
    if not cfg.expurgo_acessos_ligado:
        return None
    repo = AcessosPostgres(banco)
    return lambda _agora: repo.expurgar(cfg.expurgo_acessos_limite)


def montar(banco: Banco | None = None) -> tuple[Agendador, Banco, float]:
    """Monta o agendador. `banco` = pool já aberto do processo (agendador embutido na API);
    sem ele (CLI `python -m trato.agendador`), abre o próprio."""
    config = obter_config()
    if config.trato_persistencia.strip().lower() != "postgres":
        raise SystemExit("O agendador precisa de TRATO_PERSISTENCIA=postgres e DATABASE_URL.")
    dsn = config.database_url.get_secret_value()
    if not dsn:
        raise SystemExit("Defina DATABASE_URL no .env.")
    cfg = obter_config_agendador()
    if banco is None:
        banco = Banco(
            dsn,
            papel=config.trato_banco_papel,
            tamanho_min=config.trato_banco_pool_min,
            tamanho_max=config.trato_banco_pool_max,
        )
    contexto = criar_contexto_postgres(banco, config)
    # O dinheiro das transições do agendador (estorno na ausência do profissional) é o mesmo
    # gancho da API: sem ligar aqui, o pedido seria cancelado com o valor preso em custódia.
    pagamento = montar_servico_pagamento(banco, config)
    pagamento.ligar(contexto)
    cn = obter_config_notificacoes()
    notif = ServicoNotificacoes(
        NotificacoesServicoPostgres(banco),
        canais_da_config(cn),
        cn,
        contexto.agora,
        emails=EmailsDaContaPostgres(banco),
        pedidos=contexto.pedidos.obter,
        convidado=lambda pid: (
            d.profissional_convidado_id if (d := contexto.pedidos.dados_do_pedido(pid)) else None
        ),
    )
    contexto.extras["notificador"] = notif  # avisos de estorno disparados pelo agendador
    executor = ExecutorContexto(
        contexto,
        notif,
        pagamento.cobrancas,
        pagamento.provedor,
        pagamento,
        timedelta(seconds=cfg.estorno_idade_minima_segundos),
    )
    agendador = Agendador(
        FonteContexto(contexto, ids_ativos_postgres(banco, cfg.dias_concluidos_monitorados)),
        executor,
        RegistroPostgres(banco),
        TravaAdvisoryPostgres(dsn),
        contexto.agora,
        notif,
        timedelta(hours=cfg.lembrete_agenda_horas) if cfg.lembrete_agenda_horas else None,
        executor.liberar_bonus_moedas,
        executor.expirar_reservas_moedas,
        executor.expirar_exclusividades,
        executor.liberar_indicacoes,
        executor.gerar_visitas_recorrentes,
        executor.reenviar_estornos,
        executor.encerrar_medidas,
        executor.avisar_tratinhos_vencendo,
        rotina_de_expurgo(banco, cfg),
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
