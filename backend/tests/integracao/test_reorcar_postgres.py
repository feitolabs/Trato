"""BE-REORCAR no Postgres local: um contrato vigente por pedido, novo aceite depois do prazo de
pagamento, dinheiro atrasado do contrato antigo e banco ainda sem a migration."""

from __future__ import annotations

import threading

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.provedor.base import TipoEvento
from trato.pedidos.estados import Acao
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

from .pg_local import RAIZ
from .test_ausencia_cliente_postgres import _no_passado
from .test_fluxo_postgres import abrir_pedido, enviar_orcamento
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    cobrar,
    cobrar_ok,
    estado_pedido,
    linhas,
    migrations_novas,
    pedido_aceito,
    pg,
    webhook,
)

NOME = "20261127004000_contrato_vigente_por_pedido"
ACEITE_ANTIGO = (
    "update public.contratos set aceito_em = now() - interval '3 days' where pedido_id = %s"
)
CONTRATOS = (
    "select c.status, o.status, c.profissional_id::text from public.contratos c "
    "join public.orcamentos o on o.id = c.orcamento_id where c.pedido_id = %s "
    "order by c.criado_em, c.id"
)
COBRANCA = "select status from public.pagamentos where stripe_payment_intent_id = %s"


def expirar(c, pid) -> None:
    _, contexto, servico = c.pagto
    executor = ExecutorContexto(contexto, None, servico.cobrancas, servico.provedor, servico)
    acao = AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"expira:{pid}", acao=Acao.EXPIRAR_PAGAMENTO
    )
    executor.executar(acao, contexto.agora())


def aceitar(c, pid, oid):
    return c.pagto[0].post(
        f"/v1/pedidos/{pid}/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": oid}},
        headers=c.token("cliente"),
    )


def vencer_prazo(c, pid) -> None:
    _no_passado(c, ACEITE_ANTIGO, (pid,))


def test_banco_sem_a_migration_segue_como_antes(pg):  # noqa: F811
    """Primeiro do módulo: o rollback só passa sem pedido com dois contratos."""
    with pg.local.admin() as con:
        con.execute((RAIZ / "supabase" / "rollback" / f"{NOME}_rollback.sql").read_text("utf-8"))
    try:
        pid = pedido_aceito(pg)
        velha = cobrar_ok(pg, pid)
        vencer_prazo(pg, pid)
        expirar(pg, pid)
        assert estado_pedido(pg, pid) == "aberto"
        ((contrato, orcamento, _),) = linhas(pg, CONTRATOS, (pid,))
        assert (contrato, orcamento) == ("aguardando_pagamento", "aceito")
        assert linhas(pg, COBRANCA, (velha["id"],)) == [("expirado",)]
        novo = enviar_orcamento(pg, pid)
        r = aceitar(pg, pid, novo)
        assert r.status_code == 409 and "já tem contrato" in r.text, r.text
        assert estado_pedido(pg, pid) == "aberto"
    finally:
        with pg.local.admin() as con:
            con.execute((RAIZ / "supabase" / "migrations" / f"{NOME}.sql").read_text("utf-8"))


def test_expira_novo_orcamento_aceita_paga_e_o_antigo_volta(pg):  # noqa: F811
    contexto, servico = pg.pagto[1], pg.pagto[2]
    pid = pedido_aceito(pg)
    velha = cobrar_ok(pg, pid)
    antigo = contexto.contratos.obter_do_pedido(pid).orcamento_id
    vencer_prazo(pg, pid)
    expirar(pg, pid)
    expirar(pg, pid)  # repetir não muda nada
    assert estado_pedido(pg, pid) == "aberto"
    assert contexto.contratos.obter_do_pedido(pid) is None
    assert contexto.pedidos.obter(pid).profissional_id is None
    assert not contexto._contato_liberado(pid, pg.ids["profissional"])
    assert linhas(pg, COBRANCA, (velha["id"],)) == [("expirado",)]
    assert ("cancelar_cobranca", velha["id"]) in servico.provedor.chamadas
    assert aceitar(pg, pid, antigo).status_code >= 400

    r = aceitar(pg, pid, enviar_orcamento(pg, pid))
    assert r.status_code == 200, r.text
    assert [x[:2] for x in linhas(pg, CONTRATOS, (pid,))] == [
        ("cancelado", "expirado"),
        ("aguardando_pagamento", "aceito"),
    ]
    cliente = {"headers": pg.token("cliente")}
    vista = pg.pagto[0].get(f"/v1/contratos/{pid}/pagamento", **cliente).json()
    assert vista["estado_pagamento"] == "sem_cobranca", vista

    # Dinheiro atrasado do contrato antigo, com o novo já aceito: volta e não contrata.
    servico.provedor.marcar_paga(velha["id"])
    for n in (1, 2):
        evento = f"evt_reo_{n}"
        r = webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, velha["id"], evento_id=evento)
        assert r.status_code == 200, r.text
    valores = [e.valor_centavos for e in servico.provedor.estornos_da_cobranca(velha["id"])]
    assert valores == [velha["valor_centavos"]]
    assert estado_pedido(pg, pid) == "orcamento_aceito"
    assert not contexto.ledger.lancamentos(pid)

    nova = cobrar_ok(pg, pid)
    assert nova["id"] != velha["id"]
    servico.provedor.marcar_paga(nova["id"])
    r = webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, nova["id"], evento_id="evt_reo_novo")
    assert r.status_code == 200, r.text
    assert estado_pedido(pg, pid) == "pago_e_retido"
    retido = contexto.ledger.saldo_da_conta(CUSTODIA, pid)
    assert retido > 0
    r = webhook(pg, TipoEvento.ESTORNO_CONFIRMADO, velha["id"], evento_id="evt_reo_est")
    assert r.status_code == 200, r.text
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == retido
    # um lançamento no contrato novo e nenhum no antigo
    assert linhas(
        pg,
        "select distinct c.status from public.lancamentos l "
        "join public.contratos c on c.id = l.contrato_id where c.pedido_id = %s",
        (pid,),
    ) == [("aguardando_pagamento",)]
    assert contexto.pedidos.obter(pid).profissional_id == pg.ids["profissional"]


def test_contrato_pago_nunca_e_cancelado(pg):  # noqa: F811
    contexto, servico = pg.pagto[1], pg.pagto[2]
    pid = pedido_aceito(pg)
    cobranca = cobrar_ok(pg, pid)
    servico.provedor.marcar_paga(cobranca["id"])
    assert webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"]).status_code == 200
    vencer_prazo(pg, pid)
    try:
        expirar(pg, pid)
    except Adiada:
        pass
    assert contexto.contratos.encerrar_por_pagamento_expirado(pid) is False
    assert [x[:2] for x in linhas(pg, CONTRATOS, (pid,))] == [("aguardando_pagamento", "aceito")]
    assert estado_pedido(pg, pid) == "pago_e_retido"


def test_prazo_e_pagamento_ao_mesmo_tempo(pg):  # noqa: F811
    """Ou contrata (contrato intacto, dinheiro retido) ou cai (devolvido): nunca os dois."""
    contexto, servico = pg.pagto[1], pg.pagto[2]
    for volta in range(4):
        pid = pedido_aceito(pg)
        cobranca = cobrar_ok(pg, pid)
        vencer_prazo(pg, pid)
        servico.provedor.marcar_paga(cobranca["id"])
        erros: list[Exception] = []

        def prazo(pid=pid, erros=erros):
            try:
                expirar(pg, pid)
            except Adiada:
                pass
            except Exception as erro:  # noqa: BLE001 - o teste mostra o que veio
                erros.append(erro)

        respostas = []

        def aviso(cid=cobranca["id"], n=volta, respostas=respostas):
            respostas.append(
                webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, cid, evento_id=f"evt_corrida_{n}")
            )

        threads = [threading.Thread(target=prazo), threading.Thread(target=aviso)]
        for t in threads if volta % 2 else threads[::-1]:
            t.start()
        for t in threads:
            t.join()
        assert not erros, erros
        assert respostas[0].status_code == 200, respostas[0].text
        ((contrato, orcamento, _),) = linhas(pg, CONTRATOS, (pid,))
        devolvido = [
            e.valor_centavos for e in servico.provedor.estornos_da_cobranca(cobranca["id"])
        ]
        if estado_pedido(pg, pid) == "pago_e_retido":
            assert (contrato, orcamento, devolvido) == ("aguardando_pagamento", "aceito", [])
            assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) > 0
        else:
            assert estado_pedido(pg, pid) == "aberto"
            assert (contrato, orcamento) == ("cancelado", "expirado")
            assert devolvido == [cobranca["valor_centavos"]]
            assert not contexto.ledger.lancamentos(pid)


def test_cobranca_nova_depois_de_expirado_e_recusada(pg):  # noqa: F811
    pid = pedido_aceito(pg)
    vencer_prazo(pg, pid)
    expirar(pg, pid)
    assert cobrar(pg, pid).status_code == 409
    assert abrir_pedido(pg) != pid
