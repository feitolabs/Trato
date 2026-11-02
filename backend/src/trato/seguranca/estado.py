"""Reúne os serviços de segurança de um app. Fica em `app.state.seguranca`."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import threading
import time
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

from trato.seguranca.auditoria import AuditoriaEmMemoria, DestinoAuditoria, emitir
from trato.seguranca.config import ConfigSeguranca
from trato.seguranca.contadores import Contadores
from trato.seguranca.flags import Flag, FlagsEmMemoria, RepositorioFlags
from trato.seguranca.limite_taxa import LimitadorTaxa


class Seguranca:
    def __init__(
        self,
        config: ConfigSeguranca,
        *,
        contadores: Contadores | None = None,
        flags: RepositorioFlags | None = None,
        destino_auditoria: Callable[[], DestinoAuditoria | None] | None = None,
        agora: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self.config = config
        self.contadores = contadores or Contadores()
        self.limitador = LimitadorTaxa(config.limites, self.contadores)
        self.flags: RepositorioFlags = flags or FlagsEmMemoria()
        self.agora = agora
        self.identificadores: Any = None  # RepositorioIdentificadores, ligado na instalação
        self._destino = destino_auditoria or (lambda: None)
        self._auditoria_memoria = AuditoriaEmMemoria()
        self._idempotencia: dict[str, tuple[int, list[tuple[bytes, bytes]], bytes, float]] = {}
        self._idempotencia_em_voo: set[str] = set()
        self._idempotencia_trava = threading.Lock()
        pimenta = config.pimenta_identificadores.get_secret_value()
        # Sem pimenta no .env, cada processo usa uma aleatória: o hash vale só até reiniciar.
        self._pimenta = pimenta.encode() or secrets.token_bytes(32)

    @property
    def auditoria(self) -> DestinoAuditoria:
        return self._destino() or self._auditoria_memoria

    @property
    def auditoria_em_memoria(self) -> AuditoriaEmMemoria:
        return self._auditoria_memoria

    def hash_opaco(self, valor: str) -> str:
        """Identificador que não revela o dado (HMAC com pimenta): serve para comparar."""
        return hmac.new(self._pimenta, valor.encode(), hashlib.sha256).hexdigest()[:32]

    def auditar(self, acao: str, **campos: Any) -> None:
        emitir(self.auditoria, acao, **campos)

    def abrir_flag(
        self,
        tipo: str,
        severidade: str,
        motivos: tuple[str, ...],
        *,
        usuario_id: str | None = None,
        detalhes: dict[str, Any] | None = None,
        ator_tipo: str = "sistema",
    ) -> Flag:
        """Só abre a flag para revisão humana. Nenhuma conta é suspensa por aqui."""
        flag = self.flags.criar(
            Flag(
                id=self.flags.novo_id(),
                tipo=tipo,
                severidade=severidade,
                usuario_id=usuario_id,
                motivos=motivos,
                detalhes=detalhes or {},
                criada_em=self.agora(),
            )
        )
        self.auditar(
            "antifraude.flag_aberta",
            ator_tipo=ator_tipo,
            ator_id=usuario_id,
            depois={"flag": flag.id, "tipo": tipo, "severidade": severidade, "motivos": motivos},
        )
        return flag

    def checar_idempotencia(
        self, chave: str
    ) -> tuple[int, list[tuple[bytes, bytes]], bytes] | None:
        with self._idempotencia_trava:
            agora = time.time()
            if len(self._idempotencia) > 500:
                expiradas = [k for k, v in self._idempotencia.items() if agora - v[3] > 86400]
                for k in expiradas:
                    del self._idempotencia[k]
            item = self._idempotencia.get(chave)
            if item is not None and agora - item[3] <= 86400:
                return (item[0], item[1], item[2])
            return None

    def iniciar_idempotencia(self, chave: str) -> bool:
        """Registra início de operação idempotente em voo. Devolve False se já havia uma em voo."""
        with self._idempotencia_trava:
            if chave in self._idempotencia_em_voo:
                return False
            self._idempotencia_em_voo.add(chave)
            return True

    def concluir_idempotencia(
        self,
        chave: str,
        status: int,
        cabecalhos: list[tuple[bytes, bytes]],
        corpo: bytes,
    ) -> None:
        with self._idempotencia_trava:
            self._idempotencia_em_voo.discard(chave)
            if 200 <= status < 500:
                # Salva apenas cabeçalhos essenciais para reenvio fiel
                cabs_salvar = [
                    (k, v)
                    for k, v in cabecalhos
                    if k.lower() in (b"content-type", b"x-request-id", b"location")
                ]
                self._idempotencia[chave] = (status, cabs_salvar, corpo, time.time())

    def cancelar_idempotencia(self, chave: str) -> None:
        with self._idempotencia_trava:
            self._idempotencia_em_voo.discard(chave)
