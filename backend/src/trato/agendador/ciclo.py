"""O ciclo do agendador: pega a trava, pergunta às regras o que fazer agora e executa.

- Uma instância por vez (`Trava`); a outra desiste e tenta no próximo ciclo.
- Idempotente por chave (`RegistroExecucoes`) e o `Executor` também é idempotente.
- Relógio injetável: nada aqui lê a hora do sistema.
- Um erro numa ação não derruba as outras; ela fica sem marca e roda de novo no próximo ciclo.
"""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from trato.agendador.executor import Executor, Fonte
from trato.agendador.registro import RegistroExecucoes
from trato.agendador.trava import Trava
from trato.notificacoes.eventos import Evento
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado
from trato.rotinas.regras import PedidoMonitorado, rotinas_do_instante

log = logging.getLogger("trato.agendador")
NOME_DA_TRAVA = "trato-agendador"


@dataclass(frozen=True)
class ResultadoCiclo:
    travado: bool = False  # outra instância estava rodando
    executadas: int = 0
    repetidas: int = 0  # a chave já tinha sido executada por outro ciclo/instância
    falhas: int = 0
    reenviadas: int = 0  # notificações que estavam pendentes e saíram agora
    lembretes_agenda: int = 0


class Agendador:
    def __init__(
        self,
        fonte: Fonte,
        executor: Executor,
        registro: RegistroExecucoes,
        trava: Trava,
        relogio: Callable[[], datetime] = lambda: datetime.now(UTC),
        notificacoes: ServicoNotificacoes | None = None,
        antecedencia_lembrete_agenda: timedelta | None = None,
    ) -> None:
        self._fonte = fonte
        self._executor = executor
        self._registro = registro
        self._trava = trava
        self._relogio = relogio
        self._notif = notificacoes
        self._antecedencia = antecedencia_lembrete_agenda  # None = sem lembrete de agenda

    def rodar_uma_vez(self) -> ResultadoCiclo:
        with self._trava.adquirir(NOME_DA_TRAVA) as livre:
            if not livre:
                return ResultadoCiclo(travado=True)
            return self._ciclo()

    def _ciclo(self) -> ResultadoCiclo:
        agora = self._relogio()
        itens, config, feriados = self._fonte.carregar(agora)
        acoes = rotinas_do_instante(agora, itens, config, feriados, self._registro.ja_executadas())
        feitas = repetidas = falhas = 0
        for acao in acoes:
            try:
                self._executor.executar(acao, agora)
            except Exception:
                log.exception("Rotina falhou: %s", acao.chave)
                falhas += 1
                continue
            if self._registro.marcar(acao.chave, acao.tipo.value, acao.pedido_id, agora):
                feitas += 1
            else:
                repetidas += 1
        agenda = self._lembretes_de_agenda(itens, agora)
        reenviadas = self._notif.reenviar_pendentes() if self._notif else 0
        return ResultadoCiclo(False, feitas, repetidas, falhas, reenviadas, agenda)

    def _lembretes_de_agenda(self, itens: list[PedidoMonitorado], agora: datetime) -> int:
        """Avisa quem tem serviço agendado quando falta menos que a antecedência configurada."""
        if self._notif is None or self._antecedencia is None:
            return 0
        n = 0
        for item in itens:
            p = item.pedido
            if p.estado is not Estado.AGENDADO or p.janela is None:
                continue
            if not (p.janela.inicio - self._antecedencia <= agora < p.janela.inicio):
                continue
            for usuario in filter(None, (p.cliente_id, p.profissional_id)):
                novas = self._notif.notificar(
                    Evento.LEMBRETE_AGENDAMENTO,
                    usuario,
                    chave=f"{p.id}:{p.janela.inicio.isoformat()}",
                    pedido_id=p.id,
                )
                n += len(novas)
        return n

    def rodar_sempre(self, parar: threading.Event, intervalo_segundos: float) -> None:
        """Repete até `parar`. Erro inesperado no ciclo é registrado e o laço continua."""
        while not parar.is_set():
            try:
                resultado = self.rodar_uma_vez()
                log.info("Ciclo do agendador: %s", resultado)
            except Exception:
                log.exception("Ciclo do agendador falhou")
            parar.wait(intervalo_segundos)
