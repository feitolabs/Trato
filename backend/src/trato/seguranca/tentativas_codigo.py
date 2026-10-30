"""Limite de tentativas do código de 4 dígitos do check-in/check-out (A1).

São 10 mil combinações: sem limite, o profissional chuta até acertar e conclui o serviço sem o
cliente. Aqui: contador por agendamento e por IP, espera crescente entre tentativas (backoff) e
bloqueio temporário. Tudo vem de `ConfigSeguranca`; cada erro e cada bloqueio vão para a
auditoria. Contadores em memória (um processo): com várias instâncias, trocar `Contadores`.
"""

from __future__ import annotations

import hashlib
import math
from collections.abc import Callable
from typing import Any

from trato.seguranca.auditoria import AuditoriaEmMemoria, DestinoAuditoria, emitir
from trato.seguranca.config import ConfigSeguranca
from trato.seguranca.contadores import Contadores


class CodigoBloqueado(Exception):
    def __init__(self, retry_apos_s: int) -> None:
        super().__init__("Muitas tentativas de código. Aguarde e tente de novo.")
        self.retry_apos_s = retry_apos_s


class LimiteCodigo:
    def __init__(
        self,
        config: ConfigSeguranca,
        contadores: Contadores,
        destino_auditoria: Callable[[], DestinoAuditoria | None] | None = None,
    ) -> None:
        self._cfg = config
        self._c = contadores
        self._destino = destino_auditoria or (lambda: None)
        self.auditoria_em_memoria = AuditoriaEmMemoria()

    @staticmethod
    def _k_pedido(pedido_id: str) -> str:
        return f"codigo:ped:{pedido_id}"

    @staticmethod
    def _k_ip(ip: str) -> str:  # o IP vira hash curto: não fica em claro na memória
        return "codigo:ip:" + hashlib.sha256(ip.encode()).hexdigest()[:24]

    def _auditar(
        self,
        acao: str,
        pedido_id: str,
        ator_id: str | None,
        ip: str,
        dispositivo: str | None,
        depois: dict[str, Any],
    ) -> None:
        emitir(
            self._destino() or self.auditoria_em_memoria,
            acao,
            ator_id=ator_id,
            ator_tipo="profissional" if ator_id else "sistema",
            entidade="pedidos",
            entidade_id=pedido_id,
            depois=depois,
            ip=ip,
            dispositivo=dispositivo,
        )

    def checar(self, pedido_id: str, ip: str) -> None:
        """Levanta `CodigoBloqueado` se o agendamento ou o IP está bloqueado ou em espera."""
        cfg, c = self._cfg, self._c
        for chave in (self._k_pedido(pedido_id), self._k_ip(ip)):
            falta = c.bloqueado_por(chave)
            if falta:
                raise CodigoBloqueado(falta)
        chave = self._k_pedido(pedido_id)
        erros = c.quantos(chave, cfg.codigo_janela_s)
        if erros > cfg.codigo_erros_sem_espera:
            expoente = erros - cfg.codigo_erros_sem_espera - 1
            espera = min(
                cfg.codigo_backoff_base_s * cfg.codigo_backoff_fator**expoente,
                cfg.codigo_backoff_teto_s,
            )
            ultimo = c.ultimo(chave)
            if ultimo is not None:
                falta_s = espera - (c.agora() - ultimo)
                if falta_s > 0:
                    raise CodigoBloqueado(max(1, math.ceil(falta_s)))

    def errou(
        self, pedido_id: str, ip: str, *, acao: str, ator_id: str | None, dispositivo: str | None
    ) -> None:
        cfg, c = self._cfg, self._c
        k_ped, k_ip = self._k_pedido(pedido_id), self._k_ip(ip)
        c.adicionar(k_ped)
        c.adicionar(k_ip)
        erros = c.quantos(k_ped, cfg.codigo_janela_s)
        erros_ip = c.quantos(k_ip, cfg.codigo_janela_ip_s)
        restantes = max(0, cfg.codigo_max_erros_agendamento - erros)
        self._auditar(
            "checkin.codigo_incorreto",
            pedido_id,
            ator_id,
            ip,
            dispositivo,
            {"acao": acao, "erros_no_agendamento": erros, "tentativas_restantes": restantes},
        )
        if restantes == 0 and cfg.codigo_bloqueio_s and c.bloquear(k_ped, cfg.codigo_bloqueio_s):
            self._auditar(
                "checkin.codigo_bloqueado",
                pedido_id,
                ator_id,
                ip,
                dispositivo,
                {"acao": acao, "motivo": "agendamento", "bloqueio_s": cfg.codigo_bloqueio_s},
            )
        if (
            erros_ip >= cfg.codigo_max_erros_ip
            and cfg.codigo_bloqueio_ip_s
            and c.bloquear(k_ip, cfg.codigo_bloqueio_ip_s)
        ):
            self._auditar(
                "checkin.codigo_bloqueado",
                pedido_id,
                ator_id,
                ip,
                dispositivo,
                {"acao": acao, "motivo": "ip", "bloqueio_s": cfg.codigo_bloqueio_ip_s},
            )

    def acertou(self, pedido_id: str) -> None:
        """Código certo: zera os erros do agendamento (o contador de IP continua)."""
        self._c.zerar(self._k_pedido(pedido_id))
