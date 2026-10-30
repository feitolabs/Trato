"""Repositório do serviço de notificações (interface + versão em memória).

A versão Postgres está em `postgres.py`. A chave de idempotência (`chave`) identifica "este
fato para esta pessoa neste canal": repetir o mesmo evento não cria outra notificação.
"""

from __future__ import annotations

import itertools
from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any, Protocol

from trato.persistencia.erros import NaoEncontrado

PLATAFORMAS = ("android", "ios", "web")


@dataclass(frozen=True)
class Registro:
    id: str
    usuario_id: str
    tipo: str
    canal: str
    titulo: str
    corpo: str | None
    dados: dict[str, Any]
    criada_em: datetime
    enviada_em: datetime | None
    lida_em: datetime | None


Preferencias = dict[str, dict[str, bool]]  # categoria -> canal -> ligado


class RepositorioServicoNotificacoes(Protocol):
    def criar(
        self,
        usuario_id: str,
        tipo: str,
        canal: str,
        titulo: str,
        corpo: str | None,
        dados: dict[str, Any],
        chave: str,
        agora: datetime,
        enviada: bool,
    ) -> tuple[Registro, bool]:
        """Cria a linha. Devolve (registro, criada): repetir a `chave` devolve a antiga e False."""

    def listar(self, usuario_id: str, apenas_nao_lidas: bool, limite: int) -> Sequence[Registro]:
        """Caixa de entrada (canal `app`), a mais nova primeiro."""

    def marcar_lida(self, notificacao_id: str, usuario_id: str, agora: datetime) -> Registro:
        """Idempotente: marcar de novo devolve a mesma `lida_em`. Outra pessoa = NaoEncontrado."""

    def pendentes(self, desde: datetime, limite: int) -> Sequence[Registro]:
        """Canais externos criados desde `desde` e ainda sem `enviada_em`."""

    def marcar_enviada(self, notificacao_id: str, agora: datetime) -> None: ...

    def preferencias(self, usuario_id: str) -> Preferencias: ...

    def salvar_preferencias(
        self, usuario_id: str, prefs: Preferencias, agora: datetime
    ) -> None: ...

    def registrar_dispositivo(
        self, usuario_id: str, token: str, plataforma: str, agora: datetime
    ) -> None:
        """O token pertence a UMA pessoa: registrar de novo move para quem registrou."""

    def tokens(self, usuario_id: str) -> Sequence[str]: ...

    def desativar_dispositivo(self, token: str) -> None: ...


class RepositorioEmMemoria:
    def __init__(self) -> None:
        self._linhas: list[Registro] = []
        self._chaves: dict[tuple[str, str, str], str] = {}
        self._prefs: dict[str, Preferencias] = {}
        self._dispositivos: dict[str, tuple[str, str]] = {}  # token -> (usuario, plataforma)
        self._ids = itertools.count(1)

    def criar(
        self,
        usuario_id,
        tipo,
        canal,
        titulo,
        corpo,
        dados,
        chave,
        agora,
        enviada,  # noqa: ANN001
    ) -> tuple[Registro, bool]:
        existente = self._chaves.get((usuario_id, canal, chave))
        if existente is not None:
            return next(r for r in self._linhas if r.id == existente), False
        novo = Registro(
            f"n-{next(self._ids)}", usuario_id, tipo, canal, titulo, corpo,
            {**dados, "chave": chave}, agora, agora if enviada else None, None,
        )  # fmt: skip
        self._linhas.append(novo)
        self._chaves[(usuario_id, canal, chave)] = novo.id
        return novo, True

    def listar(self, usuario_id: str, apenas_nao_lidas: bool, limite: int) -> Sequence[Registro]:
        achadas = [
            r
            for r in reversed(self._linhas)
            if r.usuario_id == usuario_id
            and r.canal == "app"
            and (not apenas_nao_lidas or r.lida_em is None)
        ]
        return tuple(achadas[:limite])

    def _trocar(self, registro: Registro) -> None:
        self._linhas = [registro if r.id == registro.id else r for r in self._linhas]

    def marcar_lida(self, notificacao_id: str, usuario_id: str, agora: datetime) -> Registro:
        atual = next(
            (r for r in self._linhas if r.id == notificacao_id and r.usuario_id == usuario_id),
            None,
        )
        if atual is None:
            raise NaoEncontrado("Notificação não encontrada.")
        if atual.lida_em is None:
            atual = replace(atual, lida_em=agora)
            self._trocar(atual)
        return atual

    def pendentes(self, desde: datetime, limite: int) -> Sequence[Registro]:
        return tuple(
            r
            for r in self._linhas
            if r.canal != "app" and r.enviada_em is None and r.criada_em >= desde
        )[:limite]

    def marcar_enviada(self, notificacao_id: str, agora: datetime) -> None:
        for r in self._linhas:
            if r.id == notificacao_id and r.enviada_em is None:
                self._trocar(replace(r, enviada_em=agora))

    def preferencias(self, usuario_id: str) -> Preferencias:
        return {c: dict(v) for c, v in self._prefs.get(usuario_id, {}).items()}

    def salvar_preferencias(self, usuario_id: str, prefs: Preferencias, agora: datetime) -> None:
        self._prefs[usuario_id] = {c: dict(v) for c, v in prefs.items()}

    def registrar_dispositivo(
        self, usuario_id: str, token: str, plataforma: str, agora: datetime
    ) -> None:
        self._dispositivos[token] = (usuario_id, plataforma)

    def tokens(self, usuario_id: str) -> Sequence[str]:
        return tuple(t for t, (u, _) in self._dispositivos.items() if u == usuario_id)

    def desativar_dispositivo(self, token: str) -> None:
        self._dispositivos.pop(token, None)
