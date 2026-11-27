"""Incidentes de segurança (Termos 9.3 a 9.6; `incidentes_seguranca` e `incidente_medidas`,
migration 20261125225500). Só registram: não movem dinheiro nem cancelam pedido. Enquanto o
incidente de um pedido não é encerrado, o saldo dele fica retido (`api/liberacao.py`).
Sem as tabelas, `disponivel()` é falso e as rotas respondem 503."""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import Any, Protocol

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

ENCERRADO = "encerrado"
# Toque repetido do mesmo registro dentro desta janela devolve o incidente já aberto.
JANELA_REPETIDO = timedelta(minutes=5)


@dataclass(frozen=True)
class Medida:
    tipo: str
    descricao: str
    origem: str
    aplicada_em: datetime
    id: str | None = None


@dataclass(frozen=True)
class Incidente:
    tipo: str
    descricao: str
    canal: str
    aberto_em: datetime
    cautela_ate: datetime
    contato: str | None = None
    pedido_id: str | None = None
    status: str = "aberto"
    cautela_adotada_em: datetime | None = None
    responsavel_id: str | None = None
    desfecho: str | None = None
    encerrado_em: datetime | None = None
    medidas: tuple[Medida, ...] = ()
    protocolo: str | None = None
    id: str | None = None


class RepositorioIncidentes(Protocol):
    def disponivel(self) -> bool: ...

    def abrir(self, incidente: Incidente) -> tuple[Incidente, bool]:
        """(incidente, é novo). Repetição recente do mesmo registro devolve o existente."""

    def obter(self, incidente_id: str) -> Incidente | None: ...

    def pedidos_sob_medida(self, tipo: str) -> list[str]:
        """Pedidos de incidentes NÃO encerrados que têm a medida `tipo`."""

    def equipe_de_seguranca(self) -> list[str]:
        """Quem recebe o aviso do prazo de cautela (9.6)."""

    def listar(
        self, status: str | None, pedido_id: str | None, limite: int, deslocamento: int
    ) -> tuple[list[Incidente], int]: ...

    def registrar_medida(
        self, incidente_id: str, tipo: str, descricao: str, operador_id: str, agora: datetime
    ) -> str:
        """ok | repetido | encerrado | nao_encontrado"""

    def mudar_status(
        self, incidente_id: str, status: str, operador_id: str, agora: datetime
    ) -> str:
        """ok | repetido | sem_medida | encerrado | nao_encontrado"""

    def encerrar(self, incidente_id: str, desfecho: str, operador_id: str, agora: datetime) -> str:
        """ok | repetido (mesmo desfecho) | encerrado (outro desfecho) | nao_encontrado"""


def _mesmo_registro(a: Incidente, b: Incidente) -> bool:
    campos = ("tipo", "descricao", "canal", "contato", "pedido_id")
    return all(getattr(a, n) == getattr(b, n) for n in campos)


def _status_possivel(atual: Incidente, novo: str) -> str:
    if atual.status == ENCERRADO:
        return "encerrado"
    if atual.status == novo:
        return "repetido"
    if novo == "cautela_adotada" and not atual.medidas:
        return "sem_medida"
    return "ok"


class IncidentesEmMemoria:
    def pedidos_sob_medida(self, tipo: str) -> list[str]:
        return [
            i.pedido_id
            for i in list(self._itens.values())
            if i.pedido_id and i.status != ENCERRADO and any(m.tipo == tipo for m in i.medidas)
        ]

    def equipe_de_seguranca(self) -> list[str]:
        return list(self.equipe)

    def __init__(self) -> None:
        self.equipe: list[str] = []
        self._itens: dict[str, Incidente] = {}
        self._trava = threading.Lock()

    def disponivel(self) -> bool:
        return True

    def aberto_do_pedido(self, pedido_id: str) -> bool:
        return any(
            i.pedido_id == pedido_id and i.status != ENCERRADO for i in list(self._itens.values())
        )

    def abrir(self, incidente: Incidente) -> tuple[Incidente, bool]:
        with self._trava:
            for i in self._itens.values():
                if (
                    i.status != ENCERRADO
                    and incidente.aberto_em - i.aberto_em <= JANELA_REPETIDO
                    and _mesmo_registro(i, incidente)
                ):
                    return i, False
            numero = len(self._itens) + 1
            novo = replace(
                incidente,
                id=uuid.uuid4().hex,
                protocolo=f"INC-{incidente.aberto_em.year}-{numero:06d}",
            )
            self._itens[novo.id] = novo
            return novo, True

    def obter(self, incidente_id: str) -> Incidente | None:
        return self._itens.get(incidente_id)

    def listar(
        self, status: str | None, pedido_id: str | None, limite: int, deslocamento: int
    ) -> tuple[list[Incidente], int]:
        achados = [
            i
            for i in self._itens.values()
            if (status is None or i.status == status)
            and (pedido_id is None or i.pedido_id == pedido_id)
        ]
        # não encerrados primeiro, o prazo de cautela mais curto no topo
        achados.sort(key=lambda i: (i.status == ENCERRADO, i.cautela_ate, i.protocolo))
        return achados[deslocamento : deslocamento + limite], len(achados)

    def registrar_medida(
        self, incidente_id: str, tipo: str, descricao: str, operador_id: str, agora: datetime
    ) -> str:
        with self._trava:
            atual = self._itens.get(incidente_id)
            if atual is None:
                return "nao_encontrado"
            if atual.status == ENCERRADO:
                return "encerrado"
            if any((m.tipo, m.descricao) == (tipo, descricao) for m in atual.medidas):
                return "repetido"
            medida = Medida(tipo, descricao, "analista", agora, id=uuid.uuid4().hex)
            self._itens[incidente_id] = replace(atual, medidas=(*atual.medidas, medida))
            return "ok"

    def mudar_status(
        self, incidente_id: str, status: str, operador_id: str, agora: datetime
    ) -> str:
        with self._trava:
            atual = self._itens.get(incidente_id)
            if atual is None:
                return "nao_encontrado"
            resultado = _status_possivel(atual, status)
            if resultado == "ok":
                cautela = atual.cautela_adotada_em
                if status == "cautela_adotada":
                    cautela = cautela or agora
                self._itens[incidente_id] = replace(
                    atual, status=status, cautela_adotada_em=cautela, responsavel_id=operador_id
                )
            return resultado

    def encerrar(self, incidente_id: str, desfecho: str, operador_id: str, agora: datetime) -> str:
        with self._trava:
            atual = self._itens.get(incidente_id)
            if atual is None:
                return "nao_encontrado"
            if atual.status == ENCERRADO:
                return "repetido" if atual.desfecho == desfecho else "encerrado"
            self._itens[incidente_id] = replace(
                atual,
                status=ENCERRADO,
                desfecho=desfecho,
                encerrado_em=agora,
                responsavel_id=operador_id,
            )
            return "ok"


_COLUNAS = (
    "id, protocolo, tipo, descricao, canal, contato, pedido_id, status, aberto_em, cautela_ate, "
    "cautela_adotada_em, responsavel_id, desfecho, encerrado_em"
)


def _texto(valor: Any) -> str | None:
    return None if valor is None else str(valor)


class IncidentesPostgres:
    def pedidos_sob_medida(self, tipo: str) -> list[str]:
        with self._banco.transacao() as con:
            if not con.execute(
                "select to_regclass('public.incidente_medidas') is not null as tem"
            ).fetchone()["tem"]:
                return []
            linhas = con.execute(
                "select distinct i.pedido_id from public.incidentes_seguranca i "
                "join public.incidente_medidas m on m.incidente_id = i.id "
                "where i.status <> 'encerrado' and i.pedido_id is not null and m.tipo = %s",
                (tipo,),
            ).fetchall()
        return [str(x["pedido_id"]) for x in linhas]

    def equipe_de_seguranca(self) -> list[str]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select usuario_id from public.equipe where ativo "
                "and papel in ('seguranca', 'administrador')"
            ).fetchall()
        return [str(x["usuario_id"]) for x in linhas]

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return con.execute(
                "select to_regclass('public.incidentes_seguranca') is not null "
                "and to_regclass('public.incidente_medidas') is not null as tem"
            ).fetchone()["tem"]

    @staticmethod
    def _montar(con: Any, linhas: list[dict[str, Any]]) -> list[Incidente]:
        medidas: dict[Any, list[Medida]] = {}
        if linhas:
            for m in con.execute(
                "select id, incidente_id, tipo, descricao, origem, aplicada_em "
                "from public.incidente_medidas where incidente_id = any(%s) "
                "order by aplicada_em, id",
                ([x["id"] for x in linhas],),
            ).fetchall():
                medidas.setdefault(m["incidente_id"], []).append(
                    Medida(m["tipo"], m["descricao"], m["origem"], m["aplicada_em"], str(m["id"]))
                )
        itens = []
        for linha in linhas:
            dados = dict(linha) | {"medidas": tuple(medidas.get(linha["id"], ()))}
            for nome in ("id", "pedido_id", "responsavel_id"):
                dados[nome] = _texto(dados[nome])
            itens.append(Incidente(**dados))
        return itens

    def abrir(self, incidente: Incidente) -> tuple[Incidente, bool]:
        pid = como_uuid(incidente.pedido_id) if incidente.pedido_id else None
        valores = (incidente.tipo, incidente.descricao, incidente.canal, incidente.contato, pid)
        with self._banco.transacao() as con:
            # dois toques juntos no mesmo registro entram em fila
            con.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s, 9))",
                ("|".join(str(v) for v in valores),),
            )
            repetido = con.execute(
                f"select {_COLUNAS} from public.incidentes_seguranca where tipo = %s "
                "and descricao = %s and canal = %s and contato is not distinct from %s "
                "and pedido_id is not distinct from %s and status <> 'encerrado' "
                "and aberto_em >= %s order by aberto_em desc limit 1",
                (*valores, incidente.aberto_em - JANELA_REPETIDO),
            ).fetchone()
            if repetido is not None:
                return self._montar(con, [repetido])[0], False
            linha = con.execute(
                "insert into public.incidentes_seguranca (tipo, descricao, canal, contato, "
                "pedido_id, aberto_em, cautela_ate) values (%s, %s, %s, %s, %s, %s, %s) "
                f"returning {_COLUNAS}",
                (*valores, incidente.aberto_em, incidente.cautela_ate),
            ).fetchone()
            return self._montar(con, [linha])[0], True

    def obter(self, incidente_id: str) -> Incidente | None:
        iid = como_uuid(incidente_id)
        if iid is None:
            return None
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.incidentes_seguranca where id = %s", (iid,)
            ).fetchall()
            return next(iter(self._montar(con, linhas)), None)

    def listar(
        self, status: str | None, pedido_id: str | None, limite: int, deslocamento: int
    ) -> tuple[list[Incidente], int]:
        condicoes, valores = ["true"], []
        if status is not None:
            condicoes.append("status = %s")
            valores.append(status)
        if pedido_id is not None:
            if como_uuid(pedido_id) is None:
                return [], 0
            condicoes.append("pedido_id = %s")
            valores.append(como_uuid(pedido_id))
        onde = " and ".join(condicoes)
        with self._banco.transacao() as con:
            total = con.execute(
                f"select count(*) as n from public.incidentes_seguranca where {onde}", valores
            ).fetchone()["n"]
            linhas = con.execute(
                f"select {_COLUNAS} from public.incidentes_seguranca where {onde} "
                "order by (status = 'encerrado'), cautela_ate, protocolo limit %s offset %s",
                [*valores, limite, deslocamento],
            ).fetchall()
            return self._montar(con, linhas), int(total)

    def _travado(self, con: Any, incidente_id: str) -> Incidente | None:
        iid = como_uuid(incidente_id)
        if iid is None:
            return None
        linhas = con.execute(
            f"select {_COLUNAS} from public.incidentes_seguranca where id = %s for update", (iid,)
        ).fetchall()
        return next(iter(self._montar(con, linhas)), None)

    def registrar_medida(
        self, incidente_id: str, tipo: str, descricao: str, operador_id: str, agora: datetime
    ) -> str:
        with self._banco.transacao() as con:
            atual = self._travado(con, incidente_id)
            if atual is None:
                return "nao_encontrado"
            if atual.status == ENCERRADO:
                return "encerrado"
            if any((m.tipo, m.descricao) == (tipo, descricao) for m in atual.medidas):
                return "repetido"
            con.execute(
                "insert into public.incidente_medidas (incidente_id, tipo, descricao, origem, "
                "aplicada_por, aplicada_em) values (%s, %s, %s, 'analista', %s, %s)",
                (como_uuid(incidente_id), tipo, descricao, como_uuid(operador_id), agora),
            )
            return "ok"

    def mudar_status(
        self, incidente_id: str, status: str, operador_id: str, agora: datetime
    ) -> str:
        with self._banco.transacao() as con:
            atual = self._travado(con, incidente_id)
            if atual is None:
                return "nao_encontrado"
            resultado = _status_possivel(atual, status)
            if resultado == "ok":
                con.execute(
                    "update public.incidentes_seguranca set status = %s, responsavel_id = %s, "
                    "cautela_adotada_em = coalesce(cautela_adotada_em, %s) where id = %s",
                    (
                        status,
                        como_uuid(operador_id),
                        agora if status == "cautela_adotada" else None,
                        como_uuid(incidente_id),
                    ),
                )
            return resultado

    def encerrar(self, incidente_id: str, desfecho: str, operador_id: str, agora: datetime) -> str:
        with self._banco.transacao() as con:
            atual = self._travado(con, incidente_id)
            if atual is None:
                return "nao_encontrado"
            if atual.status == ENCERRADO:
                return "repetido" if atual.desfecho == desfecho else "encerrado"
            con.execute(
                "update public.incidentes_seguranca set status = 'encerrado', desfecho = %s, "
                "encerrado_em = %s, responsavel_id = %s where id = %s",
                (desfecho, agora, como_uuid(operador_id), como_uuid(incidente_id)),
            )
            return "ok"
