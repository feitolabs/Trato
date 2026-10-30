"""Conta duplicada simples: mesmo CPF, telefone ou dispositivo em contas diferentes.

Guarda só o HMAC dos identificadores (nunca o CPF ou o telefone em claro). Achou: abre FLAG para a
equipe revisar; não bloqueia, não suspende. Em modo Postgres falta uma tabela para persistir os
hashes (proposta em `docs/backend-seguranca.md`); até lá o repositório é em memória.
"""

from __future__ import annotations

import re
import threading
from typing import Protocol

from trato.seguranca.estado import Seguranca
from trato.seguranca.flags import Flag


class RepositorioIdentificadores(Protocol):
    def registrar(self, tipo: str, hash_id: str, usuario_id: str) -> set[str]:
        """Grava e devolve os OUTROS usuários que já tinham esse identificador."""
        ...


class IdentificadoresEmMemoria:
    def __init__(self) -> None:
        self._por_hash: dict[tuple[str, str], set[str]] = {}
        self._trava = threading.Lock()

    def registrar(self, tipo: str, hash_id: str, usuario_id: str) -> set[str]:
        with self._trava:
            donos = self._por_hash.setdefault((tipo, hash_id), set())
            outros = donos - {usuario_id}
            donos.add(usuario_id)
            return outros

    def esquecer_usuario(self, usuario_id: str) -> None:
        with self._trava:
            for donos in self._por_hash.values():
                donos.discard(usuario_id)


def _so_digitos(valor: str) -> str:
    return re.sub(r"\D", "", valor or "")


class DetectorDuplicidade:
    def __init__(self, seg: Seguranca, repo: RepositorioIdentificadores) -> None:
        self._s = seg
        self._repo = repo

    def verificar(
        self,
        usuario_id: str,
        *,
        cpf: str | None = None,
        telefone: str | None = None,
        dispositivo: str | None = None,
    ) -> list[Flag]:
        abertas: list[Flag] = []
        h = self._s.hash_opaco
        cpf_n = _so_digitos(cpf or "")
        tel_n = _so_digitos(telefone or "")[-11:]  # ignora DDI e zero à esquerda
        achados: list[tuple[str, str, str]] = []  # (tipo, valor normalizado, severidade)
        if len(cpf_n) == 11:
            achados.append(("cpf", cpf_n, "alta"))
        if len(tel_n) >= 10:
            achados.append(("telefone", tel_n, "alta"))
        if dispositivo and dispositivo.strip():
            achados.append(("dispositivo", dispositivo.strip().lower(), "media"))

        for tipo, valor, severidade in achados:
            outros = self._repo.registrar(tipo, h(valor), usuario_id)
            if (
                tipo == "dispositivo"
                and len(outros) + 1 <= self._s.config.max_contas_por_dispositivo
            ):
                continue
            if not outros:
                continue
            if self._ja_aberta(usuario_id, tipo):
                continue
            abertas.append(
                self._s.abrir_flag(
                    "conta_duplicada",
                    severidade,
                    (f"{tipo}_repetido",),
                    usuario_id=usuario_id,
                    detalhes={"identificador": tipo, "outras_contas": sorted(outros)},
                )
            )
        return abertas

    def _ja_aberta(self, usuario_id: str, tipo: str) -> bool:
        return any(
            f.usuario_id == usuario_id
            and f.tipo == "conta_duplicada"
            and f.detalhes.get("identificador") == tipo
            for f in self._s.flags.listar("aberta")
        )
