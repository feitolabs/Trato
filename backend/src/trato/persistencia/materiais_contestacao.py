"""Contestação de nota de material (Termos 6.9).

Tabela: `public.nota_material_contestacoes`
(migration 20261125225400_nota_material_contestacoes.sql).
Esta tabela não move dinheiro sozinha: a aprovação financeira por segunda pessoa (4 olhos)
avança `efeito_financeiro` para `pendente_financeiro`. A execução (migration 20261128030000,
`nota_material_executar_estorno`) grava `executado`; só existe no Postgres. Sem a tabela,
`disponivel()` é False e as rotas respondem 503 limpo.
"""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any, Protocol

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import RegraDoBanco

STATUS_FINAIS = ("procedente", "parcial", "improcedente")


@dataclass(frozen=True)
class ContestacaoNotaMaterial:
    id: str
    protocolo: str
    pedido_id: str
    nota_id: str
    item_id: str | None
    cliente_id: str
    motivo: str  # nao_comprovado | diferente_do_combinado
    descricao: str
    anexos: tuple[str, ...]
    valor_contestado_centavos: int
    aberta_em: datetime
    responder_ate: datetime
    status: str = "aberta"  # aberta | em_analise | procedente | parcial | improcedente
    analista_id: str | None = None
    resposta: str | None = None
    valor_reconhecido_centavos: int | None = None
    decidida_em: datetime | None = None
    aprovada_por: str | None = None
    efeito_financeiro: str = "nenhum"  # nenhum | pendente_financeiro | executado


@dataclass(frozen=True)
class ExecucaoEstornoMaterial:
    valor_reconhecido_centavos: int
    valor_divida_centavos: int
    custo_parcelamento_centavos: int
    total_estornado_centavos: int
    divida_id: str | None = None


def valor_coerente(status_final: str, reconhecido: int | None, contestado: int) -> bool:
    """`procedente` reconhece tudo, `parcial` uma parte, `improcedente` nada."""
    if status_final == "procedente":
        return reconhecido == contestado
    if status_final == "parcial":
        return reconhecido is not None and 0 < reconhecido < contestado
    return reconhecido in (None, 0)


class RepositorioContestacaoMaterial(Protocol):
    def disponivel(self) -> bool: ...

    def abrir(
        self,
        *,
        pedido_id: str,
        nota_id: str,
        nota_total_centavos: int,
        item_id: str | None,
        item_total_centavos: int | None,
        cliente_id: str,
        motivo: str,
        descricao: str,
        anexos: tuple[str, ...],
        valor_contestado_centavos: int,
        aberta_em: datetime,
        responder_ate: datetime,
    ) -> tuple[ContestacaoNotaMaterial | None, bool, str]:
        """(contestacao, eh_nova, codigo): ok | ja_aberta | excede_valor | sobreposicao.

        `ja_aberta` devolve a que está em aberto para a mesma nota (ou item)."""

    def obter(self, contestacao_id: str) -> ContestacaoNotaMaterial | None: ...

    def listar_do_pedido(self, pedido_id: str) -> list[ContestacaoNotaMaterial]: ...

    def listar_admin(
        self,
        status: str | None,
        pedido_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[ContestacaoNotaMaterial], int]: ...

    def iniciar_analise(
        self, contestacao_id: str, analista_id: str
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        """(contestacao, codigo): ok | repetido | ja_decidida | nao_encontrada"""

    def decidir(
        self,
        contestacao_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        valor_reconhecido_centavos: int | None,
        agora: datetime,
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        """(contestacao, codigo): ok | repetido | ja_decidida | valor_invalido | nao_encontrada"""

    def aprovar_financeiro(
        self, contestacao_id: str, aprovador_id: str
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        """(contestacao, codigo): ok | repetido | nao_elegivel | mesma_pessoa | nao_encontrada"""


class ContestacaoMaterialEmMemoria:
    def execucao_disponivel(self) -> bool:
        return False  # a regra de execução vive no banco

    def __init__(self, *, disponivel: bool = True) -> None:
        self._disponivel = disponivel
        self._itens: dict[str, ContestacaoNotaMaterial] = {}
        self._seq = 0
        self._trava = threading.Lock()

    def disponivel(self) -> bool:
        return self._disponivel

    def abrir(
        self,
        *,
        pedido_id: str,
        nota_id: str,
        nota_total_centavos: int,
        item_id: str | None,
        item_total_centavos: int | None,
        cliente_id: str,
        motivo: str,
        descricao: str,
        anexos: tuple[str, ...],
        valor_contestado_centavos: int,
        aberta_em: datetime,
        responder_ate: datetime,
    ) -> tuple[ContestacaoNotaMaterial | None, bool, str]:
        with self._trava:
            existente = next(
                (
                    c
                    for c in self._itens.values()
                    if c.nota_id == nota_id
                    and c.item_id == item_id
                    and c.status in ("aberta", "em_analise")
                ),
                None,
            )
            if existente is not None:
                return existente, False, "ja_aberta"
            if valor_contestado_centavos > nota_total_centavos:
                return None, False, "excede_valor"
            if any(
                c.nota_id == nota_id
                and (c.item_id is None) != (item_id is None)
                and c.status in ("aberta", "em_analise", "procedente", "parcial")
                for c in self._itens.values()
            ):
                return None, False, "sobreposicao"
            usado = sum(
                c.valor_contestado_centavos
                if c.status in ("aberta", "em_analise")
                else (c.valor_reconhecido_centavos or 0)
                for c in self._itens.values()
                if c.nota_id == nota_id and c.status != "improcedente"
            )
            if usado + valor_contestado_centavos > nota_total_centavos:
                return None, False, "excede_valor"
            if item_id is not None:
                usado_item = sum(
                    c.valor_contestado_centavos
                    if c.status in ("aberta", "em_analise")
                    else (c.valor_reconhecido_centavos or 0)
                    for c in self._itens.values()
                    if c.nota_id == nota_id and c.item_id == item_id and c.status != "improcedente"
                )
                if usado_item + valor_contestado_centavos > (item_total_centavos or 0):
                    return None, False, "excede_valor"
            self._seq += 1
            nova = ContestacaoNotaMaterial(
                id=f"cnm-{self._seq}",
                protocolo=f"CNM-{aberta_em.year}-{self._seq:06d}",
                pedido_id=pedido_id,
                nota_id=nota_id,
                item_id=item_id,
                cliente_id=cliente_id,
                motivo=motivo,
                descricao=descricao,
                anexos=tuple(anexos),
                valor_contestado_centavos=valor_contestado_centavos,
                aberta_em=aberta_em,
                responder_ate=responder_ate,
            )
            self._itens[nova.id] = nova
            return nova, True, "ok"

    def obter(self, contestacao_id: str) -> ContestacaoNotaMaterial | None:
        with self._trava:
            return self._itens.get(contestacao_id)

    def listar_do_pedido(self, pedido_id: str) -> list[ContestacaoNotaMaterial]:
        with self._trava:
            return sorted(
                (c for c in self._itens.values() if c.pedido_id == pedido_id),
                key=lambda c: (c.aberta_em, c.id),
                reverse=True,
            )

    def listar_admin(
        self,
        status: str | None,
        pedido_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[ContestacaoNotaMaterial], int]:
        with self._trava:
            itens = [
                c
                for c in self._itens.values()
                if (status is None or c.status == status)
                and (pedido_id is None or c.pedido_id == pedido_id)
            ]
            itens.sort(key=lambda c: (c.responder_ate, c.id))
            return itens[deslocamento : deslocamento + limite], len(itens)

    def iniciar_analise(
        self, contestacao_id: str, analista_id: str
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        with self._trava:
            atual = self._itens.get(contestacao_id)
            if atual is None:
                return None, "nao_encontrada"
            if atual.status in STATUS_FINAIS:
                return atual, "ja_decidida"
            if atual.status == "em_analise":
                return atual, "repetido"
            nova = replace(atual, status="em_analise", analista_id=analista_id)
            self._itens[contestacao_id] = nova
            return nova, "ok"

    def decidir(
        self,
        contestacao_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        valor_reconhecido_centavos: int | None,
        agora: datetime,
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        with self._trava:
            atual = self._itens.get(contestacao_id)
            if atual is None:
                return None, "nao_encontrada"
            if atual.status in STATUS_FINAIS:
                if (
                    atual.status == status_final
                    and atual.resposta == resposta
                    and atual.valor_reconhecido_centavos == valor_reconhecido_centavos
                ):
                    return atual, "repetido"
                return atual, "ja_decidida"
            if not valor_coerente(
                status_final, valor_reconhecido_centavos, atual.valor_contestado_centavos
            ):
                return atual, "valor_invalido"
            nova = replace(
                atual,
                status=status_final,
                analista_id=analista_id,
                resposta=resposta,
                valor_reconhecido_centavos=valor_reconhecido_centavos,
                decidida_em=agora,
            )
            self._itens[contestacao_id] = nova
            return nova, "ok"

    def aprovar_financeiro(
        self, contestacao_id: str, aprovador_id: str
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        with self._trava:
            atual = self._itens.get(contestacao_id)
            if atual is None:
                return None, "nao_encontrada"
            if atual.status not in ("procedente", "parcial"):
                return atual, "nao_elegivel"
            if atual.aprovada_por is not None:
                return atual, "repetido"
            if atual.analista_id == aprovador_id:
                return atual, "mesma_pessoa"
            nova = replace(
                atual,
                aprovada_por=aprovador_id,
                efeito_financeiro="pendente_financeiro",
            )
            self._itens[contestacao_id] = nova
            return nova, "ok"


class ContestacaoMaterialPostgres:
    _COLS = (
        "x.id, x.protocolo, c.pedido_id, x.nota_id, x.item_id, x.cliente_id, x.motivo, "
        "x.descricao, x.anexos, x.valor_contestado_centavos, x.aberta_em, x.responder_ate, "
        "x.status, x.analista_id, x.resposta, x.valor_reconhecido_centavos, x.decidida_em, "
        "x.aprovada_por, x.efeito_financeiro"
    )
    _FROM = (
        "from public.nota_material_contestacoes x "
        "join public.notas_material n on n.id = x.nota_id "
        "join public.contratos c on c.id = n.contrato_id"
    )

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _de_linha(l: dict[str, Any]) -> ContestacaoNotaMaterial:  # noqa: E741
        bruto = l["anexos"] or []
        anexos = tuple(str(i) for i in bruto) if isinstance(bruto, list) else ()
        vr = l["valor_reconhecido_centavos"]
        return ContestacaoNotaMaterial(
            id=str(l["id"]),
            protocolo=l["protocolo"],
            pedido_id=str(l["pedido_id"]),
            nota_id=str(l["nota_id"]),
            item_id=str(l["item_id"]) if l["item_id"] else None,
            cliente_id=str(l["cliente_id"]),
            motivo=l["motivo"],
            descricao=l["descricao"],
            anexos=anexos,
            valor_contestado_centavos=int(l["valor_contestado_centavos"]),
            aberta_em=l["aberta_em"],
            responder_ate=l["responder_ate"],
            status=l["status"],
            analista_id=str(l["analista_id"]) if l["analista_id"] else None,
            resposta=l["resposta"],
            valor_reconhecido_centavos=int(vr) if vr is not None else None,
            decidida_em=l["decidida_em"],
            aprovada_por=str(l["aprovada_por"]) if l["aprovada_por"] else None,
            efeito_financeiro=l["efeito_financeiro"],
        )

    def disponivel(self) -> bool:
        try:
            with self._banco.transacao() as con:
                l = con.execute(  # noqa: E741
                    "select to_regclass('public.nota_material_contestacoes') as t"
                ).fetchone()
            return bool(l and l["t"])
        except Exception:  # noqa: BLE001
            return False

    def abrir(
        self,
        *,
        pedido_id: str,
        nota_id: str,
        nota_total_centavos: int,
        item_id: str | None,
        item_total_centavos: int | None,
        cliente_id: str,
        motivo: str,
        descricao: str,
        anexos: tuple[str, ...],
        valor_contestado_centavos: int,
        aberta_em: datetime,
        responder_ate: datetime,
    ) -> tuple[ContestacaoNotaMaterial | None, bool, str]:
        _ = pedido_id, item_total_centavos  # o gatilho confere dono, item e tetos
        nid = exigir_uuid(nota_id, "nota")
        cid = exigir_uuid(cliente_id, "cliente")
        iid = exigir_uuid(item_id, "item") if item_id else None
        if valor_contestado_centavos > nota_total_centavos:
            return None, False, "excede_valor"
        try:
            with self._banco.transacao() as con:
                # Serializa por nota: no duplo toque, o segundo já enxerga a contestação.
                con.execute(
                    "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
                    (f"nota-contestacao:{nid}",),
                )
                existente = con.execute(
                    f"select {self._COLS} {self._FROM} "
                    "where x.nota_id = %s and x.item_id is not distinct from %s "
                    "and x.status in ('aberta', 'em_analise') limit 1",
                    (nid, iid),
                ).fetchone()
                if existente is not None:
                    return self._de_linha(existente), False, "ja_aberta"
                novo_id = uuid.uuid4()
                con.execute(
                    "insert into public.nota_material_contestacoes "
                    "(id, nota_id, item_id, cliente_id, motivo, descricao, anexos, "
                    "valor_contestado_centavos, aberta_em, responder_ate) "
                    "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                    (
                        novo_id,
                        nid,
                        iid,
                        cid,
                        motivo,
                        descricao,
                        Jsonb(list(anexos)),
                        valor_contestado_centavos,
                        aberta_em,
                        responder_ate,
                    ),
                )
                linha = con.execute(
                    f"select {self._COLS} {self._FROM} where x.id = %s", (novo_id,)
                ).fetchone()
            return self._de_linha(linha), True, "ok"
        except RegraDoBanco as erro:  # outras falhas (banco fora etc.) sobem como estão
            msg = str(erro).lower()
            if "sobrep" in msg:
                return None, False, "sobreposicao"
            if "passaria" in msg or "maior que" in msg:
                return None, False, "excede_valor"
            raise

    def obter(self, contestacao_id: str) -> ContestacaoNotaMaterial | None:
        cid = como_uuid(contestacao_id)
        if cid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {self._COLS} {self._FROM} where x.id = %s", (cid,)
            ).fetchone()
        return self._de_linha(l) if l else None

    def listar_do_pedido(self, pedido_id: str) -> list[ContestacaoNotaMaterial]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {self._COLS} {self._FROM} "
                "where c.pedido_id = %s order by x.aberta_em desc, x.id desc",
                (pid,),
            ).fetchall()
        return [self._de_linha(l) for l in linhas]  # noqa: E741

    def listar_admin(
        self,
        status: str | None,
        pedido_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[ContestacaoNotaMaterial], int]:
        filtros: list[str] = []
        params: list[Any] = []
        if status is not None:
            filtros.append("x.status = %s")
            params.append(status)
        if pedido_id is not None:
            pid = como_uuid(pedido_id)
            if pid is None:
                return [], 0
            filtros.append("c.pedido_id = %s")
            params.append(pid)
        where = f"where {' and '.join(filtros)}" if filtros else ""
        with self._banco.transacao() as con:
            tot = con.execute(
                f"select count(*) as n {self._FROM} {where}", tuple(params)
            ).fetchone()
            linhas = con.execute(
                f"select {self._COLS} {self._FROM} {where} "
                "order by x.responder_ate asc, x.id asc limit %s offset %s",
                (*params, limite, deslocamento),
            ).fetchall()
        return [self._de_linha(l) for l in linhas], int(tot["n"]) if tot else 0  # noqa: E741

    def iniciar_analise(
        self, contestacao_id: str, analista_id: str
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        cid = como_uuid(contestacao_id)
        if cid is None:
            return None, "nao_encontrada"
        op_id = exigir_uuid(analista_id, "analista")
        with self._banco.transacao() as con:
            atual = con.execute(
                "select status from public.nota_material_contestacoes where id = %s for update",
                (cid,),
            ).fetchone()
            if atual is None:
                return None, "nao_encontrada"
            if atual["status"] in STATUS_FINAIS:
                return self.obter(contestacao_id), "ja_decidida"
            if atual["status"] == "em_analise":
                return self.obter(contestacao_id), "repetido"
            con.execute(
                "update public.nota_material_contestacoes set status = 'em_analise', "
                "analista_id = %s where id = %s",
                (op_id, cid),
            )
            linha = con.execute(
                f"select {self._COLS} {self._FROM} where x.id = %s", (cid,)
            ).fetchone()
        return self._de_linha(linha), "ok"

    def decidir(
        self,
        contestacao_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        valor_reconhecido_centavos: int | None,
        agora: datetime,
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        cid = como_uuid(contestacao_id)
        if cid is None:
            return None, "nao_encontrada"
        op_id = exigir_uuid(analista_id, "analista")
        with self._banco.transacao() as con:
            atual = con.execute(
                "select status, resposta, valor_contestado_centavos, valor_reconhecido_centavos "
                "from public.nota_material_contestacoes where id = %s for update",
                (cid,),
            ).fetchone()
            if atual is None:
                return None, "nao_encontrada"
            if atual["status"] in STATUS_FINAIS:
                vr_atual = (
                    int(atual["valor_reconhecido_centavos"])
                    if atual["valor_reconhecido_centavos"] is not None
                    else None
                )
                if (
                    atual["status"] == status_final
                    and atual["resposta"] == resposta
                    and vr_atual == valor_reconhecido_centavos
                ):
                    return self.obter(contestacao_id), "repetido"
                return self.obter(contestacao_id), "ja_decidida"
            contestado = int(atual["valor_contestado_centavos"])
            if not valor_coerente(status_final, valor_reconhecido_centavos, contestado):
                return self.obter(contestacao_id), "valor_invalido"
            con.execute(
                "update public.nota_material_contestacoes "
                "set status = %s, analista_id = %s, resposta = %s, "
                "valor_reconhecido_centavos = %s, decidida_em = %s where id = %s",
                (status_final, op_id, resposta, valor_reconhecido_centavos, agora, cid),
            )
            linha = con.execute(
                f"select {self._COLS} {self._FROM} where x.id = %s", (cid,)
            ).fetchone()
        return self._de_linha(linha), "ok"

    def aprovar_financeiro(
        self, contestacao_id: str, aprovador_id: str
    ) -> tuple[ContestacaoNotaMaterial | None, str]:
        cid = como_uuid(contestacao_id)
        if cid is None:
            return None, "nao_encontrada"
        ap_id = exigir_uuid(aprovador_id, "aprovador")
        with self._banco.transacao() as con:
            atual = con.execute(
                "select status, analista_id, aprovada_por "
                "from public.nota_material_contestacoes where id = %s for update",
                (cid,),
            ).fetchone()
            if atual is None:
                return None, "nao_encontrada"
            if atual["status"] not in ("procedente", "parcial"):
                return self.obter(contestacao_id), "nao_elegivel"
            if atual["aprovada_por"] is not None:
                return self.obter(contestacao_id), "repetido"
            if str(atual["analista_id"]) == str(ap_id):
                return self.obter(contestacao_id), "mesma_pessoa"
            con.execute(
                "update public.nota_material_contestacoes "
                "set aprovada_por = %s, efeito_financeiro = 'pendente_financeiro' where id = %s",
                (ap_id, cid),
            )
            linha = con.execute(
                f"select {self._COLS} {self._FROM} where x.id = %s", (cid,)
            ).fetchone()
        return self._de_linha(linha), "ok"

    # --- execução do estorno (migration 20261128030000) --------------------------------------

    def execucao_disponivel(self) -> bool:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select to_regprocedure('public.nota_material_executar_estorno("
                "uuid,bigint,bigint,text,uuid)') is not null as tem"
            ).fetchone()
        return bool(l and l["tem"])

    def travar_contrato(self, pedido_id: str) -> None:
        """Mesma trava do livro e da compensação; chamar na transação da execução."""
        with self._banco.transacao() as con:
            con.execute(
                "select id from public.contratos where pedido_id = %s "
                "and status <> 'cancelado' for update",
                (exigir_uuid(pedido_id, "pedido"),),
            )

    def execucao(self, contestacao_id: str) -> ExecucaoEstornoMaterial | None:
        cid = como_uuid(contestacao_id)
        if cid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select valor_reconhecido_centavos, valor_divida_centavos, "
                "custo_parcelamento_centavos, total_estornado_centavos, divida_id "
                "from public.nota_material_execucoes where contestacao_id = %s",
                (cid,),
            ).fetchone()
        if l is None:
            return None
        return ExecucaoEstornoMaterial(
            int(l["valor_reconhecido_centavos"]),
            int(l["valor_divida_centavos"]),
            int(l["custo_parcelamento_centavos"]),
            int(l["total_estornado_centavos"]),
            str(l["divida_id"]) if l["divida_id"] else None,
        )

    def executar_estorno(
        self, contestacao_id: str, divida: int, custo: int, motivo: str, operador_id: str
    ) -> str:
        """Confere, cria a dívida e marca `executado`. Resultado fora de ok/ja_executada: quem
        chama desfaz a transação (o livro e as ordens já gravados nela)."""
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select resultado from public.nota_material_executar_estorno(%s, %s, %s, %s, %s)",
                (
                    exigir_uuid(contestacao_id, "contestação"),
                    divida,
                    custo,
                    motivo,
                    exigir_uuid(operador_id, "operador"),
                ),
            ).fetchone()
        return str(l["resultado"])
