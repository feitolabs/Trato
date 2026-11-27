"""BE-AUSENCIA-BLOQ no Postgres local: bloqueio e confirmação da retenção não se cruzam."""

from __future__ import annotations

import threading

from trato.financeiro.ledger import a_liberar

from .test_ausencia_cliente_postgres import (
    VALOR_ORCAMENTO,
    _no_passado,
    justificar,
    painel,
    registrado,
)
from .test_cliente_bloqueado_postgres import BLOQUEAR, liberar_conta
from .test_desistencia_postgres import ordens, registros
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    migrations_novas,
    pg,
)

CORPO = {
    "retencao_centavos": 1_000,
    "retencao_justificativa": "Deslocamento e material comprado.",
    "retencao_comprovantes": ["nota-1"],
}


def estado(c, pid) -> str:  # pelo repositório: o cliente bloqueado não vê o cancelado
    return c.pagto[1].pedidos.obter(pid).estado.value


def test_bloqueio_em_andamento_segura_a_confirmacao_e_nada_e_retido(pg, equipe):  # noqa: F811
    pid, _ = registrado(pg, fora_dos_7_dias=True)
    justificar(pg, pid)
    assert painel(pg, pid, **CORPO).status_code == 200
    _no_passado(
        pg,
        "update public.cancelamentos_pedido set retencao_mostrada_cliente_em = "
        "retencao_mostrada_cliente_em - interval '12 days' where pedido_id = %s",
        (pid,),
    )
    respostas = []
    try:
        tarefa = threading.Thread(target=lambda: respostas.append(painel(pg, pid, "confirmar")))
        with pg.local.admin() as con:
            with con.transaction():
                con.execute(BLOQUEAR, (pg.ids["cliente"],))  # ainda sem commit
                tarefa.start()
                tarefa.join(1.0)
                assert tarefa.is_alive()  # a decisão espera o bloqueio terminar
        tarefa.join(20)
        (r,) = respostas
        assert r.status_code == 409 and "bloqueada" in r.text, r.text
        assert estado(pg, pid) == "agendado" and ordens(pg, pid) == []
        retirar = {"retirar_retencao": True}
        codigos = []
        threads = [
            threading.Thread(
                target=lambda: codigos.append(painel(pg, pid, "confirmar", **retirar).status_code)
            )
            for _ in range(4)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert sorted(codigos) == [200] + [409] * 3, codigos
        assert estado(pg, pid) == "cancelado" and ordens(pg, pid) == [VALOR_ORCAMENTO]
        (linha,) = registros(pg, pid)
        assert linha["status"] == "cancelado_sem_retencao"
        contexto = pg.pagto[1]
        prof = contexto.pedidos.obter(pid).profissional_id
        assert contexto.ledger.saldo_da_conta(a_liberar(prof), pid) == 0
    finally:
        liberar_conta(pg)
