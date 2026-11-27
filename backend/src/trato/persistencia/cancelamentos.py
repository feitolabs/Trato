"""Desistência e consentimento de execução imediata (Termos 7.2 e 7.3).

Tabelas da migration 20261125141500 (`cancelamentos_pedido` e duas colunas em `contratos`).
Sem elas no banco nada quebra: não há registro nem consentimento, e o cancelamento segue.
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

EM_ANALISE = "aguardando_analise"
PROPOSTA = "proposta_retencao_enviada"


@dataclass(frozen=True)
class Cancelamento:
    pedido_id: str
    solicitado_por: str
    tipo: str  # desistencia_arrependimento | cancelamento_cliente
    status: str  # cancelado_sem_retencao | aguardando_analise | confirmado | recusado
    recebido_em: datetime
    motivo: str = ""
    servico_iniciado: bool = False
    dentro_do_arrependimento: bool = False
    reembolso_centavos: int | None = None
    id: str | None = None
    papel: str = "cliente"
    retencao_centavos: int = 0
    retencao_base_centavos: int | None = None
    retencao_justificativa: str | None = None
    retencao_comprovantes: tuple[str, ...] = ()
    retencao_mostrada_em: datetime | None = None


class RepositorioCancelamentos(Protocol):
    def contestar_retencao(self, pedido_id: str, agora: datetime) -> None:
        """O cliente não aceitou a retenção mostrada."""

    def ajustar_retencao(self, pedido_id: str, valor_centavos: int) -> None:
        """A revisão da contestação baixou ou retirou a retenção proposta."""

    def descartar_proposta(self, pedido_id: str) -> None:
        """Proposta de retenção abandonada (ex.: o serviço foi remarcado) vira recusada, para
        não ser confirmada depois nem ocupar o lugar do cancelamento do pedido."""

    def consentimento_disponivel(self) -> bool:
        """Dá para saber se o cliente pediu a execução? Sem a coluna, nada sai automático."""

    def confirmar_retencao(
        self, pedido_id: str, reembolso_centavos: int, retirar: bool = False
    ) -> None:
        """A proposta mostrada ao cliente vira cancelamento (`retirar`: sem retenção)."""

    def registrar_consentimento(self, pedido_id: str, agora: datetime) -> None:
        """Consentimento expresso de execução antes dos 7 dias: gravado uma vez só."""

    def consentimento_em(self, pedido_id: str) -> datetime | None: ...

    def do_pedido(self, pedido_id: str) -> Cancelamento | None:
        """O registro mais recente (o recusado também aparece, para o cliente ver o resultado)."""

    def registrar(self, item: Cancelamento) -> Cancelamento | None:
        """Um por pedido: repetir devolve o que já existe. None sem a tabela."""

    def decidir(
        self,
        pedido_id: str,
        status: str,
        analista_id: str,
        decisao: str,
        reembolso_centavos: int,
        agora: datetime,
    ) -> None:
        """Fecha o caso que aguardava análise (nada acontece se não houver)."""


class CancelamentosEmMemoria:
    def __init__(self) -> None:
        self._itens: list[Cancelamento] = []
        self._consentimentos: dict[str, datetime] = {}
        self.decisoes: dict[str, tuple[str, str, datetime]] = {}  # pedido -> quem, o quê, quando
        self._trava = threading.Lock()

    def descartar_proposta(self, pedido_id: str) -> None:
        with self._trava:
            for i, c in enumerate(self._itens):
                if c.pedido_id == pedido_id and c.status == PROPOSTA:
                    self._itens[i] = replace(c, status="recusado")

    def contestar_retencao(self, pedido_id: str, agora: datetime) -> None:
        return None

    def ajustar_retencao(self, pedido_id: str, valor_centavos: int) -> None:
        with self._trava:
            for i, c in enumerate(self._itens):
                if c.pedido_id == pedido_id and c.status == PROPOSTA:
                    self._itens[i] = replace(c, retencao_centavos=valor_centavos)

    def consentimento_disponivel(self) -> bool:
        return True

    def confirmar_retencao(
        self, pedido_id: str, reembolso_centavos: int, retirar: bool = False
    ) -> None:
        with self._trava:
            for i, c in enumerate(self._itens):
                if c.pedido_id == pedido_id and c.status == PROPOSTA:
                    self._itens[i] = replace(
                        c,
                        status="cancelado_sem_retencao" if retirar else "confirmado",
                        retencao_centavos=0 if retirar else c.retencao_centavos,
                        reembolso_centavos=reembolso_centavos,
                    )

    def registrar_consentimento(self, pedido_id: str, agora: datetime) -> None:
        with self._trava:
            self._consentimentos.setdefault(pedido_id, agora)

    def consentimento_em(self, pedido_id: str) -> datetime | None:
        return self._consentimentos.get(pedido_id)

    def do_pedido(self, pedido_id: str) -> Cancelamento | None:
        do_pedido = [c for c in self._itens if c.pedido_id == pedido_id]
        return do_pedido[-1] if do_pedido else None

    def registrar(self, item: Cancelamento) -> Cancelamento | None:
        with self._trava:
            atual = self.do_pedido(item.pedido_id)
            if atual is not None and atual.status != "recusado":
                return atual
            novo = replace(item, id=uuid.uuid4().hex)
            self._itens.append(novo)
            return novo

    def decidir(
        self,
        pedido_id: str,
        status: str,
        analista_id: str,
        decisao: str,
        reembolso_centavos: int,
        agora: datetime,
    ) -> None:
        with self._trava:
            for i, c in enumerate(self._itens):
                if c.pedido_id == pedido_id and c.status == EM_ANALISE:
                    self._itens[i] = replace(
                        c, status=status, reembolso_centavos=reembolso_centavos
                    )
                    self.decisoes[pedido_id] = (analista_id, decisao, agora)


_COLUNAS = (
    "id, pedido_id, solicitado_por, tipo, status, recebimento_confirmado_em, motivo, "
    "servico_iniciado, dentro_arrependimento_7d, reembolso_centavos, papel_solicitante, "
    "retencao_valor_centavos, retencao_valor_base_centavos, retencao_justificativa, "
    "retencao_comprovantes, retencao_mostrada_cliente_em"
)


def _montar(linha: dict[str, Any]) -> Cancelamento:
    reembolso = linha["reembolso_centavos"]
    return Cancelamento(
        pedido_id=str(linha["pedido_id"]),
        solicitado_por=str(linha["solicitado_por"]),
        tipo=linha["tipo"],
        status=linha["status"],
        recebido_em=linha["recebimento_confirmado_em"],
        motivo=linha["motivo"],
        servico_iniciado=linha["servico_iniciado"],
        dentro_do_arrependimento=linha["dentro_arrependimento_7d"],
        reembolso_centavos=None if reembolso is None else int(reembolso),
        id=str(linha["id"]),
        papel=linha["papel_solicitante"],
        retencao_centavos=int(linha["retencao_valor_centavos"]),
        retencao_base_centavos=linha["retencao_valor_base_centavos"],
        retencao_justificativa=linha["retencao_justificativa"],
        retencao_comprovantes=tuple(linha["retencao_comprovantes"]),
        retencao_mostrada_em=linha["retencao_mostrada_cliente_em"],
    )


class CancelamentosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    # Conferir ANTES de consultar: uma consulta que falha estragaria a transação em curso.
    @staticmethod
    def _tem_tabela(con: Any) -> bool:
        return con.execute(
            "select to_regclass('public.cancelamentos_pedido') is not null as tem"
        ).fetchone()["tem"]

    @staticmethod
    def _tem_consentimento(con: Any) -> bool:
        return con.execute(
            "select exists (select 1 from information_schema.columns where table_schema = 'public' "
            "and table_name = 'contratos' and column_name = 'consentimento_execucao_imediata') "
            "as tem"
        ).fetchone()["tem"]

    def descartar_proposta(self, pedido_id: str) -> None:
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return
            con.execute(
                "update public.cancelamentos_pedido set status = 'recusado' "
                "where pedido_id = %s and status = %s",
                (como_uuid(pedido_id), PROPOSTA),
            )

    def contestar_retencao(self, pedido_id: str, agora: datetime) -> None:
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return
            con.execute(
                "update public.cancelamentos_pedido set retencao_aceita_cliente = false, "
                "retencao_respondida_em = %s where pedido_id = %s and status = %s",
                (agora, como_uuid(pedido_id), PROPOSTA),
            )

    def ajustar_retencao(self, pedido_id: str, valor_centavos: int) -> None:
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return
            con.execute(
                "update public.cancelamentos_pedido set retencao_valor_centavos = %s "
                "where pedido_id = %s and status = %s",
                (valor_centavos, como_uuid(pedido_id), PROPOSTA),
            )

    def consentimento_disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem_consentimento(con)

    def confirmar_retencao(
        self, pedido_id: str, reembolso_centavos: int, retirar: bool = False
    ) -> None:
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return
            con.execute(
                "update public.cancelamentos_pedido set status = %s, "
                "retencao_valor_centavos = case when %s then 0 else retencao_valor_centavos end, "
                "reembolso_centavos = %s where pedido_id = %s and status = %s",
                (
                    "cancelado_sem_retencao" if retirar else "confirmado",
                    retirar,
                    reembolso_centavos,
                    como_uuid(pedido_id),
                    PROPOSTA,
                ),
            )

    def registrar_consentimento(self, pedido_id: str, agora: datetime) -> None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return
        with self._banco.transacao() as con:
            if not self._tem_consentimento(con):
                return
            con.execute(  # a data é do banco (gatilho): a aplicação não envia
                "update public.contratos set consentimento_execucao_imediata = true "
                "where pedido_id = %s and status <> 'cancelado' "
                "and not consentimento_execucao_imediata",
                (pid,),
            )

    def consentimento_em(self, pedido_id: str) -> datetime | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            if not self._tem_consentimento(con):
                return None
            linha = con.execute(
                "select consentimento_execucao_imediata_em as em from public.contratos "
                "where pedido_id = %s and status <> 'cancelado'",
                (pid,),
            ).fetchone()
        return linha["em"] if linha else None

    def do_pedido(self, pedido_id: str) -> Cancelamento | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from public.cancelamentos_pedido where pedido_id = %s "
                "order by criado_em desc limit 1",
                (pid,),
            ).fetchone()
        return _montar(linha) if linha else None

    def registrar(self, item: Cancelamento) -> Cancelamento | None:
        pid, quem = como_uuid(item.pedido_id), como_uuid(item.solicitado_por)
        if pid is None or quem is None:
            return None
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return None
            con.execute(  # `dentro_arrependimento_7d` é calculado pelo banco: não vai daqui
                "insert into public.cancelamentos_pedido (pedido_id, contrato_id, "
                "solicitado_por, papel_solicitante, tipo, motivo, status, "
                "recebimento_confirmado_em, servico_iniciado, reembolso_centavos, "
                "retencao_valor_centavos, retencao_valor_base_centavos, retencao_justificativa, "
                "retencao_comprovantes, retencao_mostrada_cliente_em) values (%s, "
                "(select id from public.contratos where pedido_id = %s "
                " and status <> 'cancelado'), "
                "%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) on conflict do nothing",
                (pid, pid, quem, item.papel, item.tipo, item.motivo, item.status,
                 item.recebido_em, item.servico_iniciado, item.reembolso_centavos,
                 item.retencao_centavos, item.retencao_base_centavos,
                 item.retencao_justificativa, Jsonb(list(item.retencao_comprovantes)),
                 item.retencao_mostrada_em),
            )  # fmt: skip
        return self.do_pedido(item.pedido_id)

    def decidir(
        self,
        pedido_id: str,
        status: str,
        analista_id: str,
        decisao: str,
        reembolso_centavos: int,
        agora: datetime,
    ) -> None:
        pid, analista = como_uuid(pedido_id), como_uuid(analista_id)
        if pid is None or analista is None:
            return
        with self._banco.transacao() as con:
            if not self._tem_tabela(con):
                return
            # Quem decide pela rota do pedido pode não estar em `equipe`: sem essa linha o
            # registro fecha sem analista (a auditoria da disputa guarda quem foi).
            con.execute(
                "update public.cancelamentos_pedido c set status = %s, analista_id = e.id, "
                "decisao_analista = %s, "
                "decidido_em = case when e.id is null then null else %s::timestamptz end, "
                "reembolso_centavos = %s "
                "from (select (select usuario_id from public.equipe where usuario_id = %s) "
                "as id) e where c.pedido_id = %s and c.status = 'aguardando_analise'",
                (status, decisao, agora, reembolso_centavos, analista, pid),
            )
