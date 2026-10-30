"""Reúne os serviços de segurança de um app. Fica em `app.state.seguranca`."""

from __future__ import annotations

import hashlib
import hmac
import secrets
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
