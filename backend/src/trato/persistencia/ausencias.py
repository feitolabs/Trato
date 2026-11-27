"""Cliente ausente (Termos 7.6): chegada, espera, justificativa e decisão do analista.

Tabela `ausencias_cliente` (migration 20261125141500), uma por agendamento. Sem ela no banco
`disponivel()` é falso e o app segue como antes.
"""

# ruff: noqa: S608 - só as colunas fixas de _COLUNAS entram na f-string; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any, Protocol

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

AGUARDANDO_ESPERA = "aguardando_espera"
AGUARDANDO_JUSTIFICATIVA = "aguardando_justificativa"
EM_ANALISE = "em_analise"
ACEITA = "justificativa_aceita"
RECUSADA = "justificativa_recusada"
EXPIRADA = "expirada_sem_justificativa"
# Enquanto o caso está aqui, o cancelamento do cliente fora dos 7 dias espera o analista.
PENDENTES = (AGUARDANDO_JUSTIFICATIVA, EM_ANALISE, RECUSADA, EXPIRADA)


@dataclass(frozen=True)
class Ausencia:
    pedido_id: str
    cliente_id: str
    profissional_id: str
    janela_inicio: datetime
    chegada_em: datetime
    espera_minutos: int = 20
    status: str = AGUARDANDO_ESPERA
    registrada_em: datetime | None = None
    avisado_em: datetime | None = None
    prazo_horas: int = 24
    justificativa_ate: datetime | None = None
    texto: str | None = None
    anexos: tuple[str, ...] = ()
    justificativa_em: datetime | None = None
    analista_id: str | None = None
    decisao: str | None = None
    decidido_em: datetime | None = None
    id: str | None = None
    foto_chegada: str | None = None  # mídia de check-in já conferida (null em serviço remoto)


class RepositorioAusencias(Protocol):
    def disponivel(self) -> bool: ...

    def obter(self, pedido_id: str, janela_inicio: datetime) -> Ausencia | None:
        """O registro do agendamento atual (remarcar começa outro)."""

    def abrir(self, item: Ausencia) -> Ausencia:
        """Registra a chegada; repetir devolve a primeira."""

    def mudar(self, item: Ausencia, de: tuple[str, ...]) -> bool:
        """Grava o novo estado só se o atual estiver em `de` (compare-and-set)."""

    def fila(self, status: tuple[str, ...]) -> list[Ausencia]: ...


class AusenciasEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[tuple[str, datetime], Ausencia] = {}
        self._trava = threading.Lock()

    def disponivel(self) -> bool:
        return True

    def obter(self, pedido_id: str, janela_inicio: datetime) -> Ausencia | None:
        return self._itens.get((pedido_id, janela_inicio))

    def abrir(self, item: Ausencia) -> Ausencia:
        with self._trava:
            chave = (item.pedido_id, item.janela_inicio)
            return self._itens.setdefault(chave, replace(item, id=uuid.uuid4().hex))

    def mudar(self, item: Ausencia, de: tuple[str, ...]) -> bool:
        with self._trava:
            chave = (item.pedido_id, item.janela_inicio)
            atual = self._itens.get(chave)
            if atual is None or atual.status not in de:
                return False
            self._itens[chave] = item
            return True

    def fila(self, status: tuple[str, ...]) -> list[Ausencia]:
        return [a for a in self._itens.values() if a.status in status]


_COLUNAS = (
    "a.id, a.pedido_id, a.cliente_id, a.profissional_id, ag.janela_inicio, a.chegada_em, "
    "a.espera_minutos, a.status, a.ausencia_registrada_em, a.cliente_avisado_em, "
    "a.justificativa_prazo_horas, a.justificativa_ate, a.justificativa_texto, "
    "a.justificativa_comprovantes, a.justificativa_enviada_em, a.analista_id, "
    "a.decisao_analista, a.decidido_em, "
    # via jsonb: funciona também antes da coluna existir
    "to_jsonb(a) ->> 'foto_chegada_midia_id' as foto_chegada"
)
_DE = "public.ausencias_cliente a join public.agendamentos ag on ag.id = a.agendamento_id"


def _montar(linha: dict[str, Any]) -> Ausencia:
    analista = linha["analista_id"]
    return Ausencia(
        pedido_id=str(linha["pedido_id"]),
        cliente_id=str(linha["cliente_id"]),
        profissional_id=str(linha["profissional_id"]),
        janela_inicio=linha["janela_inicio"],
        chegada_em=linha["chegada_em"],
        espera_minutos=linha["espera_minutos"],
        status=linha["status"],
        registrada_em=linha["ausencia_registrada_em"],
        avisado_em=linha["cliente_avisado_em"],
        prazo_horas=linha["justificativa_prazo_horas"],
        justificativa_ate=linha["justificativa_ate"],
        texto=linha["justificativa_texto"],
        anexos=tuple(linha["justificativa_comprovantes"]),
        justificativa_em=linha["justificativa_enviada_em"],
        analista_id=None if analista is None else str(analista),
        decisao=linha["decisao_analista"],
        decidido_em=linha["decidido_em"],
        id=str(linha["id"]),
        foto_chegada=linha["foto_chegada"],
    )


class AusenciasPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _tem_tabela(con: Any) -> bool:
        return con.execute(
            "select to_regclass('public.ausencias_cliente') is not null as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem_tabela(con)

    def obter(self, pedido_id: str, janela_inicio: datetime) -> Ausencia | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from {_DE} where a.pedido_id = %s and ag.janela_inicio = %s "
                "and ag.status <> 'remarcado' order by a.criado_em desc limit 1",
                (pid, janela_inicio),
            ).fetchone()
        return _montar(linha) if linha else None

    def abrir(self, item: Ausencia) -> Ausencia:
        pid = como_uuid(item.pedido_id)
        with self._banco.transacao() as con:
            con.execute(
                "insert into public.ausencias_cliente (agendamento_id, contrato_id, pedido_id, "
                "profissional_id, cliente_id, chegada_em, espera_minutos, status, "
                "justificativa_prazo_horas) "
                "select ag.id, c.id, c.pedido_id, %s, %s, %s, %s, %s, %s "
                "from public.agendamentos ag join public.contratos c on c.id = ag.contrato_id "
                "where c.pedido_id = %s and c.status <> 'cancelado' "
                "and ag.janela_inicio = %s and ag.status <> 'remarcado' "
                "order by ag.criado_em desc limit 1 on conflict (agendamento_id) do nothing",
                (como_uuid(item.profissional_id), como_uuid(item.cliente_id), item.chegada_em,
                 item.espera_minutos, item.status, item.prazo_horas, pid, item.janela_inicio),
            )  # fmt: skip
        foto = como_uuid(item.foto_chegada) if item.foto_chegada else None
        if foto is not None:
            with self._banco.transacao() as con:
                if con.execute(
                    "select 1 from information_schema.columns where table_schema = 'public' "
                    "and table_name = 'ausencias_cliente' "
                    "and column_name = 'foto_chegada_midia_id'"
                ).fetchone():
                    con.execute(  # uma vez, durante a espera (o gatilho confere a mídia)
                        "update public.ausencias_cliente a set foto_chegada_midia_id = %s "
                        "from public.agendamentos ag where ag.id = a.agendamento_id "
                        "and a.pedido_id = %s and ag.janela_inicio = %s "
                        "and a.foto_chegada_midia_id is null and a.status = 'aguardando_espera'",
                        (foto, pid, item.janela_inicio),
                    )
        gravado = self.obter(item.pedido_id, item.janela_inicio)
        if gravado is None:
            raise LookupError("Agendamento do pedido não encontrado.")
        return gravado

    def mudar(self, item: Ausencia, de: tuple[str, ...]) -> bool:
        analista = como_uuid(item.analista_id) if item.analista_id else None
        with self._banco.transacao() as con:
            cursor = con.execute(
                "update public.ausencias_cliente set status = %s, ausencia_registrada_em = %s, "
                "cliente_avisado_em = %s, justificativa_ate = %s, justificativa_texto = %s, "
                "justificativa_comprovantes = %s, justificativa_enviada_em = %s, "
                "analista_id = %s, decisao_analista = %s, decidido_em = %s "
                "where id = %s and status = any(%s)",
                (item.status, item.registrada_em, item.avisado_em, item.justificativa_ate,
                 item.texto, Jsonb(list(item.anexos)), item.justificativa_em, analista,
                 item.decisao, item.decidido_em if analista else None, como_uuid(item.id or ""),
                 list(de)),
            )  # fmt: skip
            return cursor.rowcount == 1

    def fila(self, status: tuple[str, ...]) -> list[Ausencia]:
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return []
            linhas = con.execute(
                f"select {_COLUNAS} from {_DE} where a.status = any(%s) "
                "and ag.status <> 'remarcado' order by a.criado_em limit 200",
                (list(status),),
            ).fetchall()
        return [_montar(linha) for linha in linhas]
