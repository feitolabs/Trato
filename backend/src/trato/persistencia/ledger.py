"""Ledger no Postgres (F3.5): `lancamentos` + `partidas` + `contas_ledger`.

O ledger só ESPELHA o que o provedor liquida (D13/D15): não há saldo próprio, saldo é sempre a
soma das partidas. As regras (saldo, estorno, equilíbrio, idempotência) são as MESMAS do `Livro`
em memória (`financeiro/ledger.py`): aqui o histórico do contrato é lido, o `Livro` valida o lote
e só o que é novo é gravado. O banco confere de novo no COMMIT (gatilhos de equilíbrio e de
estorno que inverte exatamente as partidas).

Um lançamento sempre pertence a um contrato (`lancamentos.contrato_id`), por isso um pedido sem
contrato não recebe lançamento. O contrato é travado (`for update`) enquanto o lote é conferido
e gravado: dois lotes do mesmo contrato nunca se cruzam (A6).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from typing import Any

import psycopg

from trato.financeiro.ledger import (
    ChaveReutilizada,
    Conta,
    Lancamento,
    Livro,
    SaldoPedido,
    TipoConta,
    TipoLancamento,
)
from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import RegraDoBanco

# Natureza contábil de cada conta (contas_ledger.natureza).
_NATUREZA = {
    TipoConta.CLIENTE_EXTERNO: "ativo",
    TipoConta.PROFISSIONAL_EXTERNO: "ativo",
    TipoConta.CUSTODIA: "passivo",
    TipoConta.A_LIBERAR: "passivo",
    TipoConta.LIBERADO: "passivo",
    TipoConta.TAXA_TRATO: "receita",
}


def _hex(valor: object) -> str:
    return uuid.UUID(str(valor)).hex


class LedgerPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    # --- escrita ----------------------------------------------------------------------------
    def lancar_varios(self, lancamentos: Sequence[Lancamento]) -> Sequence[Lancamento]:
        """Grava todos ou nenhum. Chave repetida com os mesmos dados devolve o lançamento antigo."""
        lote = list(lancamentos)
        if not lote:
            return ()
        with self._banco.transacao() as con:
            contratos: dict[str, str] = {}
            livros: dict[str, Livro] = {}
            # Ordem fixa dos travamentos: dois lotes com os mesmos pedidos nunca se travam.
            for pedido in sorted({item.pedido_id for item in lote}):
                pid = como_uuid(pedido)
                linha = (
                    con.execute(
                        "select id from public.contratos where pedido_id = %s for update", (pid,)
                    ).fetchone()
                    if pid
                    else None
                )
                if linha is None:
                    raise RegraDoBanco("Este pedido ainda não tem contrato: sem onde lançar.")
                contratos[pedido] = str(linha["id"])
                livro = Livro()
                historico = self._carregar(con, contratos[pedido], pedido)
                if historico:
                    livro.lancar_varios(historico)
                livros[pedido] = livro

            resultado: list[Lancamento] = []
            novos: list[Lancamento] = []
            for item in lote:
                livro = livros[item.pedido_id]
                antes = len(livro.lancamentos)
                if self._chave_de_outro_contrato(con, item, contratos[item.pedido_id]):
                    raise ChaveReutilizada(f"A chave {item.chave!r} já foi usada em outro pedido.")
                gravado = livro.lancar_varios([item])[0]
                if len(livro.lancamentos) > antes:
                    novos.append(gravado)
                resultado.append(gravado)
            for novo in novos:
                self._inserir(con, contratos[novo.pedido_id], novo)
        return tuple(resultado)

    @staticmethod
    def _chave_de_outro_contrato(
        con: psycopg.Connection[Any], item: Lancamento, contrato_id: str
    ) -> bool:
        linha = con.execute(
            "select contrato_id from public.lancamentos where chave_idempotencia = %s",
            (item.chave,),
        ).fetchone()
        return linha is not None and str(linha["contrato_id"]) != contrato_id

    def _inserir(self, con: psycopg.Connection[Any], contrato_id: str, item: Lancamento) -> None:
        evento = None
        if item.evento_webhook_id:
            achado = con.execute(
                "select id from public.eventos_webhook where evento_id = %s",
                (item.evento_webhook_id,),
            ).fetchone()
            evento = achado["id"] if achado else None
        con.execute(
            "insert into public.lancamentos (id, contrato_id, evento_webhook_id, tipo, estorna_id, "
            "chave_idempotencia, ocorrido_em) values (%s, %s, %s, %s, %s, %s, %s)",
            (
                str(uuid.UUID(item.id)),
                contrato_id,
                evento,
                item.tipo.value,
                str(uuid.UUID(item.estorno_de)) if item.estorno_de else None,
                item.chave,
                item.data,
            ),
        )
        for conta, sentido in ((item.debito, "debito"), (item.credito, "credito")):
            con.execute(
                "insert into public.partidas (lancamento_id, conta_id, sentido, valor_centavos) "
                "values (%s, %s, %s, %s)",
                (str(uuid.UUID(item.id)), self._conta(con, conta), sentido, item.valor),
            )

    @staticmethod
    def _conta(con: psycopg.Connection[Any], conta: Conta) -> str:
        """A conta do ledger (criada na primeira vez que aparece; nunca muda nem se apaga)."""
        titular = conta.titular
        con.execute(
            "insert into public.contas_ledger (codigo, natureza, usuario_id) values (%s, %s, %s) "
            "on conflict (codigo, (coalesce(usuario_id, '00000000-0000-0000-0000-000000000000'"
            "::uuid))) do nothing",
            (conta.tipo.value, _NATUREZA[conta.tipo], titular),
        )
        linha = con.execute(
            "select id from public.contas_ledger where codigo = %s "
            "and usuario_id is not distinct from %s::uuid",
            (conta.tipo.value, titular),
        ).fetchone()
        return str(linha["id"])

    # --- leitura ----------------------------------------------------------------------------
    def _carregar(
        self, con: psycopg.Connection[Any], contrato_id: str, pedido_id: str
    ) -> list[Lancamento]:
        linhas = con.execute(
            "select l.id, l.tipo, l.estorna_id, l.chave_idempotencia, l.ocorrido_em, "
            "e.evento_id as evento, c.codigo, c.usuario_id, p.sentido, p.valor_centavos "
            "from public.lancamentos l "
            "join public.partidas p on p.lancamento_id = l.id "
            "join public.contas_ledger c on c.id = p.conta_id "
            "left join public.eventos_webhook e on e.id = l.evento_webhook_id "
            "where l.contrato_id = %s order by p.id",
            (contrato_id,),
        ).fetchall()
        return self._montar(linhas, pedido_id)

    @staticmethod
    def _montar(linhas: Sequence[dict[str, Any]], pedido_id: str) -> list[Lancamento]:
        por_id: dict[Any, dict[str, Any]] = {}
        for linha in linhas:  # a ordem de `partidas.id` é a ordem em que foram lançados
            item = por_id.setdefault(linha["id"], {"linha": linha})
            conta = Conta(
                TipoConta(linha["codigo"]),
                str(linha["usuario_id"]) if linha["usuario_id"] else None,
            )
            item[linha["sentido"]] = conta
            item["valor"] = int(linha["valor_centavos"])
        return [
            Lancamento(
                chave=i["linha"]["chave_idempotencia"],
                pedido_id=pedido_id,
                tipo=TipoLancamento(i["linha"]["tipo"]),
                debito=i["debito"],
                credito=i["credito"],
                valor=i["valor"],
                data=i["linha"]["ocorrido_em"],
                estorno_de=_hex(i["linha"]["estorna_id"]) if i["linha"]["estorna_id"] else None,
                id=_hex(i["linha"]["id"]),
                evento_webhook_id=i["linha"]["evento"],
            )
            for i in por_id.values()
        ]

    def lancamentos(self, pedido_id: str | None = None) -> Sequence[Lancamento]:
        with self._banco.transacao() as con:
            if pedido_id is None:
                contratos = con.execute(
                    "select id, pedido_id from public.contratos order by criado_em, id"
                ).fetchall()
            else:
                pid = como_uuid(pedido_id)
                contratos = (
                    con.execute(
                        "select id, pedido_id from public.contratos where pedido_id = %s", (pid,)
                    ).fetchall()
                    if pid
                    else []
                )
            saida: list[Lancamento] = []
            for contrato in contratos:
                saida += self._carregar(con, str(contrato["id"]), str(contrato["pedido_id"]))
        return tuple(saida)

    def saldo_da_conta(self, conta: Conta, pedido_id: str | None = None) -> int:
        """Créditos menos débitos da conta (a conta que ainda não existe tem saldo zero)."""
        pid = como_uuid(pedido_id) if pedido_id is not None else None
        if pedido_id is not None and pid is None:
            return 0
        with self._banco.transacao() as con:
            linha = con.execute(
                "select coalesce(sum(case p.sentido when 'credito' then p.valor_centavos "
                "else -p.valor_centavos end), 0)::bigint as saldo "
                "from public.partidas p join public.contas_ledger c on c.id = p.conta_id "
                "join public.lancamentos l on l.id = p.lancamento_id "
                "join public.contratos k on k.id = l.contrato_id "
                "where c.codigo = %s and c.usuario_id is not distinct from %s::uuid "
                "and (%s::uuid is null or k.pedido_id = %s::uuid)",
                (conta.tipo.value, conta.titular, pid, pid),
            ).fetchone()
        return int(linha["saldo"])

    def saldos_pedido(self, pedido_id: str, profissional_id: str | None) -> SaldoPedido:
        from trato.financeiro.ledger import (
            CLIENTE,
            CUSTODIA,
            TAXA_TRATO,
            a_liberar,
            liberado,
        )

        prof = profissional_id
        return SaldoPedido(
            cliente_pagou=-self.saldo_da_conta(CLIENTE, pedido_id),
            retido=self.saldo_da_conta(CUSTODIA, pedido_id),
            a_liberar=self.saldo_da_conta(a_liberar(prof), pedido_id) if prof else 0,
            liberado=self.saldo_da_conta(liberado(prof), pedido_id) if prof else 0,
            taxa_trato=self.saldo_da_conta(TAXA_TRATO, pedido_id),
        )
