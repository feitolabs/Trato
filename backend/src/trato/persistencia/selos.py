"""Selo do profissional (Termos 10.3; `selo_eventos`, migration 20261127223000). Quem grava é o
banco, pelas três funções: histórico imutável e, com retirada aberta, o nível não sobe."""

# ruff: noqa: S608 - só nomes de função fixos entram no SQL; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco

# operação -> (tipo do evento, função SQL)
OPERACOES = {
    "retirar": ("retirada", "selo_retirar"),
    "reconferencia": ("reconferencia_pedida", "selo_pedir_reconferencia"),
    "regularizar": ("regularizacao", "selo_regularizar"),
}


class ChaveDeOutroEvento(Exception):
    """A chave de idempotência já foi usada em outro evento ou em outro profissional."""


@dataclass(frozen=True)
class ResultadoSelo:
    # ok | ja_existe | sem_selo | sem_retirada_aberta | operador_invalido |
    # profissional_nao_encontrado
    resultado: str
    evento_id: str | None = None
    nivel: str | None = None


@dataclass(frozen=True)
class _Evento:
    id: str
    profissional_id: str
    tipo: str
    nivel_anterior: str
    chave: str
    retirada_id: str | None = None


class SelosEmMemoria:
    """Mesmas regras das funções SQL. Quem liga diz como ler e gravar o nível do perfil. A
    permissão do operador é conferida na rota."""

    def __init__(self) -> None:
        self.ler_nivel: Callable[[str], str | None] = lambda _id: None
        self.gravar_nivel: Callable[[str, str], None] = lambda _id, _nivel: None
        self._eventos: list[_Evento] = []
        self._trava = threading.RLock()

    def disponivel(self) -> bool:
        return True

    def _aberta(self, profissional_id: str) -> _Evento | None:
        fechadas = {e.retirada_id for e in self._eventos if e.retirada_id}
        return next(
            (
                e
                for e in self._eventos
                if e.profissional_id == profissional_id
                and e.tipo == "retirada"
                and e.id not in fechadas
            ),
            None,
        )

    def retirada_aberta(self, profissional_id: str) -> bool:
        with self._trava:
            return self._aberta(profissional_id) is not None

    def aplicar(
        self,
        operacao: str,
        profissional_id: str,
        operador_id: str,
        motivo: str,
        chave: str,
        agora: datetime,
    ) -> ResultadoSelo:
        tipo = OPERACOES[operacao][0]
        with self._trava:
            atual = self.ler_nivel(profissional_id)
            if atual is None:
                return ResultadoSelo("profissional_nao_encontrado")
            anterior = next((e for e in self._eventos if e.chave == chave), None)
            if anterior is not None:
                if (anterior.profissional_id, anterior.tipo) != (profissional_id, tipo):
                    raise ChaveDeOutroEvento
                return ResultadoSelo("ja_existe", anterior.id, atual)
            aberta = self._aberta(profissional_id)
            if operacao == "retirar" and atual == "basico":
                return ResultadoSelo("sem_selo", nivel=atual)
            if operacao == "regularizar" and aberta is None:
                return ResultadoSelo("sem_retirada_aberta", nivel=atual)
            novo = _Evento(
                str(uuid.uuid4()),
                profissional_id,
                tipo,
                atual,
                chave,
                aberta.id if operacao == "regularizar" and aberta else None,
            )
            self._eventos.append(novo)
            nivel = atual
            if operacao == "retirar":
                nivel = "basico"
            elif operacao == "regularizar" and aberta:
                nivel = aberta.nivel_anterior
            if nivel != atual:
                self.gravar_nivel(profissional_id, nivel)
            return ResultadoSelo("ok", novo.id, nivel)


class SelosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _tem(con: Any) -> bool:
        return con.execute(
            "select to_regprocedure('public.selo_regularizar(uuid,uuid,text,text,timestamptz)') "
            "is not null as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem(con)

    def retirada_aberta(self, profissional_id: str) -> bool:
        pid = como_uuid(profissional_id)
        if pid is None:
            return False
        with self._banco.transacao() as con:
            if not self._tem(con):
                return False
            return con.execute(
                "select exists (select 1 from public.selo_eventos e where e.profissional_id = %s "
                "and e.tipo = 'retirada' and not exists (select 1 from public.selo_eventos r "
                "where r.retirada_id = e.id)) as aberta",
                (pid,),
            ).fetchone()["aberta"]

    def aplicar(
        self,
        operacao: str,
        profissional_id: str,
        operador_id: str,
        motivo: str,
        chave: str,
        agora: datetime,
    ) -> ResultadoSelo:
        tipo, funcao = OPERACOES[operacao]
        pid = como_uuid(profissional_id)
        if pid is None:
            return ResultadoSelo("profissional_nao_encontrado")
        with self._banco.transacao() as con:
            antes = con.execute(
                "select profissional_id, tipo from public.selo_eventos "
                "where chave_idempotencia = %s",
                (chave,),
            ).fetchone()
            if antes is not None and (str(antes["profissional_id"]), antes["tipo"]) != (
                str(pid),
                tipo,
            ):
                raise ChaveDeOutroEvento
            linha = con.execute(
                f"select resultado, evento_id, nivel from public.{funcao}(%s, %s, %s, %s, %s)",
                (pid, exigir_uuid(operador_id, "operador"), motivo, chave, agora),
            ).fetchone()
        return ResultadoSelo(
            linha["resultado"],
            str(linha["evento_id"]) if linha["evento_id"] else None,
            linha["nivel"],
        )
