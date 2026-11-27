"""BE-52 no Postgres local: o banco não grava contrato de orçamento vencido e avisos de
pagamento ao mesmo tempo, depois da validade, geram um estorno só."""

from __future__ import annotations

import threading
from datetime import UTC, datetime

import pytest

from trato.api.repositorios import Contrato
from trato.pagamentos.provedor.base import TipoEvento
from trato.persistencia.erros import RegraDoBanco

from .test_ausencia_cliente_postgres import _no_passado
from .test_fluxo_postgres import abrir_pedido, enviar_orcamento
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    cobrar,
    cobrar_ok,
    estado_pedido,
    migrations_novas,
    pedido_aceito,
    pg,
    webhook,
)

VENCER = (
    "update public.orcamentos set validade_ate = now() - interval '1 minute' where pedido_id = %s"
)


def test_banco_recusa_contrato_de_orcamento_vencido(pg):  # noqa: F811
    pid = abrir_pedido(pg)
    oid = enviar_orcamento(pg, pid)
    _no_passado(pg, VENCER, (pid,))
    url = f"/v1/pedidos/{pid}/acoes/aceitar_orcamento"
    r = pg.pagto[0].post(url, json={"prova": {"orcamento_id": oid}}, headers=pg.token("cliente"))
    assert r.status_code == 409 and r.json()["codigo"] == "orcamento_vencido", r.text
    contratos = pg.pagto[1].contratos
    novo = Contrato(pid, oid, pg.ids["profissional"], 1, aceito_em=datetime.now(UTC))
    with pytest.raises(RegraDoBanco, match="venceu"):
        contratos.salvar(novo)
    assert contratos.obter_do_pedido(pid) is None


def test_pago_depois_da_validade_um_estorno_so(pg):  # noqa: F811
    pid = pedido_aceito(pg)
    cobranca = cobrar_ok(pg, pid)
    _no_passado(pg, VENCER, (pid,))
    r = cobrar(pg, pid)
    assert r.status_code == 409 and r.json()["codigo"] == "orcamento_vencido", r.text
    fake = pg.pagto[2].provedor
    fake.marcar_paga(cobranca["id"])
    respostas = []
    threads = [
        threading.Thread(
            target=lambda n=n: respostas.append(
                webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"], evento_id=f"evt_v{n}")
            )
        )
        for n in range(4)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert {r.status_code for r in respostas} == {200}, [r.text for r in respostas]
    valores = [e.valor_centavos for e in fake.estornos_da_cobranca(cobranca["id"])]
    assert valores == [cobranca["valor_centavos"]]
    assert estado_pedido(pg, pid) == "orcamento_aceito"
    cliente = {"headers": pg.token("cliente")}
    r = pg.pagto[0].get(f"/v1/contratos/{pid}/pagamento", **cliente).json()
    assert (r["estado_pagamento"], r["pago"]) == ("devolvida", False)
    r = pg.pagto[0].get(f"/v1/pedidos/{pid}/pagamento", **cliente).json()
    assert datetime.fromisoformat(r["validade_ate"]) < datetime.now(UTC)
    assert r["cobranca_pendente_id"] is None and r["pagamento_confirmado"] is False
    assert not pg.pagto[1].ledger.lancamentos(pid)
