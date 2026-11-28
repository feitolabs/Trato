"""Janelas de indisponibilidade (Termos 22.3; `janelas_indisponibilidade`, migration
20261127205000). Só registram e só se encerram uma vez; nada se apaga. Sem a tabela, a leitura
devolve vazio e `disponivel()` é falso."""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

ORIGENS = ("app", "pagamento")


class JanelaSobreposta(Exception):
    """Já há janela da mesma origem nesse período (inclusive uma ainda aberta)."""


@dataclass(frozen=True)
class Janela:
    origem: str
    inicio_em: datetime
    motivo: str
    criada_por: str
    fim_em: datetime | None = None
    encerrada_por: str | None = None
    criada_em: datetime | None = None
    id: str | None = None


def _sobrepoe(a: Janela, b: Janela) -> bool:
    return (b.fim_em is None or a.inicio_em < b.fim_em) and (
        a.fim_em is None or b.inicio_em < a.fim_em
    )


def _repetida(a: Janela, b: Janela) -> bool:
    return (a.origem, a.inicio_em, a.fim_em, a.motivo) == (
        b.origem,
        b.inicio_em,
        b.fim_em,
        b.motivo,
    )


class IndisponibilidadesEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Janela] = {}
        self._trava = threading.RLock()

    def disponivel(self) -> bool:
        return True

    def criar(self, janela: Janela) -> tuple[Janela, bool]:
        """(janela, criada). Repetir o mesmo registro devolve o que já existe."""
        with self._trava:
            for item in self._itens.values():
                if item.origem == janela.origem and _sobrepoe(janela, item):
                    if _repetida(janela, item):
                        return item, False
                    raise JanelaSobreposta
            nova = replace(janela, id=str(uuid.uuid4()))
            self._itens[nova.id] = nova
            return nova, True

    def obter(self, janela_id: str) -> Janela | None:
        return self._itens.get(janela_id)

    def listar(
        self,
        origem: str | None = None,
        abertas: bool = False,
        desde: datetime | None = None,
    ) -> list[Janela]:
        """Da mais recente para a mais antiga. `desde`: só as que terminam depois disso."""
        with self._trava:
            achadas = [
                j
                for j in self._itens.values()
                if (origem is None or j.origem == origem)
                and (not abertas or j.fim_em is None)
                and (desde is None or j.fim_em is None or j.fim_em > desde)
            ]
        return sorted(achadas, key=lambda j: j.inicio_em, reverse=True)

    def encerrar(self, janela_id: str, fim_em: datetime, por: str) -> Janela | None:
        """Só janela aberta, uma vez. `None`: já encerrada ou inexistente."""
        with self._trava:
            atual = self._itens.get(janela_id)
            if atual is None or atual.fim_em is not None:
                return None
            self._itens[janela_id] = replace(atual, fim_em=fim_em, encerrada_por=por)
            return self._itens[janela_id]


_COLUNAS = "id, origem, inicio_em, fim_em, motivo, criada_por, encerrada_por, criada_em"


def _janela(linha: Any) -> Janela:
    return Janela(**{**linha, "id": str(linha["id"])})


class IndisponibilidadesPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def _existe(self, con: Any) -> bool:
        # Consulta que não falha sem a tabela: um erro aqui abortaria a transação de fora.
        return con.execute(
            "select to_regclass('public.janelas_indisponibilidade') is not null as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._existe(con)

    def criar(self, janela: Janela) -> tuple[Janela, bool]:
        with self._banco.transacao() as con:
            # O banco não impede sobreposição: a trava por origem serializa conferir e gravar.
            con.execute(
                "select pg_advisory_xact_lock(hashtext(%s))",
                (f"janelas_indisponibilidade:{janela.origem}",),
            )
            linhas = con.execute(
                f"select {_COLUNAS} from public.janelas_indisponibilidade where origem = %s "
                "and (fim_em is null or fim_em > %s)",
                (janela.origem, janela.inicio_em),
            ).fetchall()
            for item in map(_janela, linhas):
                if _sobrepoe(janela, item):
                    if _repetida(janela, item):
                        return item, False
                    raise JanelaSobreposta
            linha = con.execute(
                "insert into public.janelas_indisponibilidade "
                "(origem, inicio_em, fim_em, motivo, criada_por, encerrada_por) "
                f"values (%s, %s, %s, %s, %s, %s) returning {_COLUNAS}",
                (
                    janela.origem,
                    janela.inicio_em,
                    janela.fim_em,
                    janela.motivo,
                    janela.criada_por,
                    janela.encerrada_por,
                ),
            ).fetchone()
        return _janela(linha), True

    def obter(self, janela_id: str) -> Janela | None:
        achado = como_uuid(janela_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            if not self._existe(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from public.janelas_indisponibilidade where id = %s",
                (achado,),
            ).fetchone()
        return _janela(linha) if linha else None

    def listar(
        self,
        origem: str | None = None,
        abertas: bool = False,
        desde: datetime | None = None,
    ) -> list[Janela]:
        filtros, valores = ["true"], []
        if origem is not None:
            filtros.append("origem = %s")
            valores.append(origem)
        if abertas:
            filtros.append("fim_em is null")
        if desde is not None:
            filtros.append("(fim_em is null or fim_em > %s)")
            valores.append(desde)
        with self._banco.transacao() as con:
            if not self._existe(con):
                return []
            linhas = con.execute(
                f"select {_COLUNAS} from public.janelas_indisponibilidade "
                f"where {' and '.join(filtros)} order by inicio_em desc",
                valores,
            ).fetchall()
        return [_janela(x) for x in linhas]

    def encerrar(self, janela_id: str, fim_em: datetime, por: str) -> Janela | None:
        achado = como_uuid(janela_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.janelas_indisponibilidade set fim_em = %s, encerrada_por = %s "
                f"where id = %s and fim_em is null returning {_COLUNAS}",
                (fim_em, por, achado),
            ).fetchone()
        return _janela(linha) if linha else None
