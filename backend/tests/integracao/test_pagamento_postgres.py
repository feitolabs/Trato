"""Pagamento ligado ao Postgres (local, descartável): cobrança, webhook assinado, ledger espelhado e
idempotência do mesmo evento. Provedor FALSO: nenhum dinheiro nem rede. Nunca toca no Supabase."""

from __future__ import annotations

import secrets
import uuid
from dataclasses import replace
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from trato.api import criar_app
from trato.api.fabrica import criar_contexto_postgres, montar_servico_pagamento
from trato.api.rotas_pagamento import instalar_pagamento
from trato.config import Config
from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import (
    Aditivo,
    CobrancaLocal,
    EstadoAditivo,
    EstadoCobranca,
    OrdemEstorno,
)
from trato.pagamentos.provedor import TipoEvento

from .pg_local import RAIZ
from .test_fluxo_postgres import abrir_pedido, enviar_orcamento

pytestmark = pytest.mark.integracao

VALOR_ORCAMENTO = 80_000 + 10_000  # 8 x 10.000 + 2,5 x 4.000, como em `enviar_orcamento`
# A taxa é SOMADA ao orçamento (João, 31/10/2026): 7,5% (750 bps, faixa até 100.000) de 90.000.
TAXA_ORCAMENTO = 6_750
COBRADO = VALOR_ORCAMENTO + TAXA_ORCAMENTO


def _aplicar(con, subir: str, descer: str, pronto: str) -> list[str]:
    """Aplica uma migration NOVA (não aplicada no Supabase) só neste banco descartável."""
    if con.execute(pronto).fetchone()[0]:
        return []
    con.execute((RAIZ / "supabase/migrations" / subir).read_text("utf-8"))
    return [(RAIZ / "supabase/rollback" / descer).read_text("utf-8")]


@pytest.fixture(scope="module")
def migrations_novas(cenario):
    desfazer: list[str] = []
    with cenario.local.admin() as con:
        desfazer += _aplicar(
            con,
            "20261030120000_ordens_estorno.sql",
            "ordens_estorno_rollback.sql",
            "select to_regclass('public.ordens_estorno') is not null",
        )
        desfazer += _aplicar(
            con,
            "20261031000000_pagamentos_instrucao.sql",
            "pagamentos_instrucao_rollback.sql",
            "select exists (select 1 from information_schema.columns where "
            "table_name = 'pagamentos' and column_name = 'instrucao')",
        )
    yield
    with cenario.local.admin() as con:  # devolve o banco da sessão ao estado de antes
        for sql in reversed(desfazer):
            con.execute(sql)


@pytest.fixture(scope="module")
def pg(cenario, migrations_novas):
    """App PRÓPRIO com o pagamento instalado (o contexto da sessão não é alterado)."""
    config = Config(
        _env_file=None,
        trato_codigo_segredo=SecretStr(secrets.token_hex(16)),
        supabase_jwt_secret=SecretStr(cenario.segredo_jwt),
    )
    contexto = criar_contexto_postgres(cenario.banco, config)
    app = criar_app(contexto)
    servico = montar_servico_pagamento(cenario.banco, config)
    instalar_pagamento(app, contexto, servico)
    cenario.pagto = (TestClient(app), contexto, servico)
    return cenario


def cobrar(c, pedido_id, meio="pix", quem="cliente"):
    http, _, _ = c.pagto
    return http.post(
        f"/v1/pedidos/{pedido_id}/cobranca", json={"meio": meio}, headers=c.token(quem)
    )


def cobrar_ok(c, pedido_id, meio="pix") -> dict:
    r = cobrar(c, pedido_id, meio)
    assert r.status_code == 201, r.text
    return r.json()


def pedido_aceito(c) -> str:
    http, _, _ = c.pagto
    pedido_id = abrir_pedido(c)
    orcamento_id = enviar_orcamento(c, pedido_id)
    r = http.post(
        f"/v1/pedidos/{pedido_id}/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": orcamento_id}},
        headers=c.token("cliente"),
    )
    if r.status_code != 200:  # o corpo do aceite é {"orcamento_id": ...} (ver test_fluxo_postgres)
        r = http.post(
            f"/v1/pedidos/{pedido_id}/acoes/aceitar_orcamento",
            json={"orcamento_id": orcamento_id},
            headers=c.token("cliente"),
        )
    assert r.status_code == 200, r.text
    return pedido_id


def webhook(c, tipo, cobranca_id, **kw):
    http, contexto, servico = c.pagto
    kw.setdefault("instante", int(datetime.now(UTC).timestamp()))
    corpo, cab = servico.provedor.evento_assinado(tipo, cobranca_id, **kw)
    return http.post("/v1/webhooks/stripe", content=corpo, headers=cab)


def linhas(c, sql, args=()):
    with c.local.admin() as con:
        return con.execute(sql, args).fetchall()


def estado_pedido(c, pedido_id) -> str:
    http, _, _ = c.pagto
    r = http.get(f"/v1/pedidos/{pedido_id}", headers=c.token("cliente"))
    assert r.status_code == 200, r.text
    return r.json()["estado"]


def test_app_da_config_liga_o_pagamento_no_modo_postgres(cenario, migrations_novas):
    """A fábrica de produção instala as rotas e os manipuladores (antes: 503 e nada registrado)."""
    from trato.api.fabrica import criar_app_da_config

    config = Config(
        _env_file=None,
        trato_persistencia="postgres",
        database_url=SecretStr(cenario.local.uri),
        trato_banco_papel="service_role",
        trato_codigo_segredo=SecretStr("x" * 32),
        supabase_jwt_secret=SecretStr(cenario.segredo_jwt),
    )
    app = criar_app_da_config(config)
    assert app.state.servico_pagamento is not None
    assert "/v1/pedidos/{pedido_id}/cobranca" in app.openapi()["paths"]
    contexto = app.state.contexto
    assert {"payment_intent.succeeded", "charge.refunded", "payout.paid"} <= set(
        contexto.manipuladores_webhook
    )


def test_cobranca_webhook_ledger_e_idempotencia(pg):
    c = pg
    http, contexto, _ = c.pagto
    pedido_id = pedido_aceito(c)

    # só o cliente do pedido cobra
    assert cobrar(c, pedido_id, quem="cliente2").status_code in (403, 404)

    r = cobrar(c, pedido_id)
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] == COBRADO and cob["status"] == "aguardando"
    assert cob["instrucao"]
    # repetir devolve a MESMA cobrança pendente, com a instrução
    outra = cobrar(c, pedido_id).json()
    assert outra["id"] == cob["id"] and outra["instrucao"] == cob["instrucao"]

    (linha,) = linhas(
        c,
        "select status, valor_centavos, tipo, meio, confirmado_em, instrucao "
        "from public.pagamentos where stripe_payment_intent_id = %s",
        (cob["id"],),
    )
    assert linha[0] == "pendente" and linha[1] == COBRADO and linha[2] == "saldo"
    assert linha[3] == "pix" and linha[4] is None and linha[5] == cob["instrucao"]

    # D13: criar a cobrança NÃO paga o pedido
    assert estado_pedido(c, pedido_id) == "orcamento_aceito"
    assert not contexto.ledger.lancamentos(pedido_id)

    # webhook sem assinatura: 400 e nada muda
    sem = http.post("/v1/webhooks/stripe", content=b"{}", headers={"Stripe-Signature": "t=1,v1=00"})
    assert sem.status_code == 400
    assert estado_pedido(c, pedido_id) == "orcamento_aceito"

    # webhook assinado de pagamento confirmado
    http_, _, servico = c.pagto
    servico.provedor.marcar_paga(cob["id"])
    evento = f"evt_{uuid.uuid4().hex}"
    r = webhook(c, TipoEvento.PAGAMENTO_CONFIRMADO, cob["id"], evento_id=evento)
    assert r.status_code == 200 and r.json()["duplicado"] is False, r.text
    assert estado_pedido(c, pedido_id) != "orcamento_aceito"
    (linha,) = linhas(
        c,
        "select status, confirmado_em from public.pagamentos where stripe_payment_intent_id = %s",
        (cob["id"],),
    )
    assert linha[0] == "confirmado" and linha[1] is not None

    # ledger espelha o pagamento: partidas fecham e o lançamento aponta o evento do webhook
    lanc = linhas(
        c,
        "select l.id, l.evento_webhook_id, e.evento_id from public.lancamentos l "
        "join public.contratos k on k.id = l.contrato_id "
        "left join public.eventos_webhook e on e.id = l.evento_webhook_id "
        "where k.pedido_id = %s",
        (pedido_id,),
    )
    assert len(lanc) >= 1 and all(x[2] == evento for x in lanc)
    (soma,) = linhas(
        c,
        "select sum(case when p.sentido = 'debito' then p.valor_centavos "
        "else -p.valor_centavos end) from public.partidas p "
        "join public.lancamentos l on l.id = p.lancamento_id "
        "join public.contratos k on k.id = l.contrato_id where k.pedido_id = %s",
        (pedido_id,),
    )
    assert soma[0] == 0
    antes = (len(lanc), len(contexto.ledger.lancamentos(pedido_id)))
    # a taxa sai da custódia na confirmação: fica retido só o serviço
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pedido_id) == VALOR_ORCAMENTO
    assert contexto.ledger.saldos_pedido(pedido_id).taxa_trato == TAXA_ORCAMENTO

    # o MESMO evento de novo: 200, duplicado, nada novo no ledger nem no pedido
    r = webhook(c, TipoEvento.PAGAMENTO_CONFIRMADO, cob["id"], evento_id=evento)
    assert r.status_code == 200 and r.json()["duplicado"] is True
    # e outro evento (id novo) para a mesma cobrança também não duplica o lançamento
    r = webhook(c, TipoEvento.PAGAMENTO_CONFIRMADO, cob["id"], evento_id=f"evt_{uuid.uuid4().hex}")
    assert r.status_code == 200
    depois = linhas(
        c,
        "select count(*) from public.lancamentos l join public.contratos k on k.id = l.contrato_id "
        "where k.pedido_id = %s",
        (pedido_id,),
    )
    assert depois[0][0] == antes[0]
    assert len(contexto.ledger.lancamentos(pedido_id)) == antes[1]
    assert (
        linhas(c, "select count(*) from public.eventos_webhook where evento_id = %s", (evento,))[0][
            0
        ]
        == 1
    )

    # já pago: nova cobrança é recusada
    assert cobrar(c, pedido_id).status_code == 409

    # listagem do pedido vem do banco
    lista = http.get(f"/v1/pedidos/{pedido_id}/cobrancas", headers=c.token("cliente")).json()
    assert [x["status"] for x in lista] == ["paga"]


def test_valor_divergente_nao_paga_e_fica_para_revisao(pg):
    c = pg
    http, _, servico = c.pagto
    pedido_id = pedido_aceito(c)
    cob = cobrar_ok(c, pedido_id)
    r = webhook(
        c,
        TipoEvento.PAGAMENTO_CONFIRMADO,
        cob["id"],
        valor_centavos=COBRADO - 1,
        evento_id=f"evt_{uuid.uuid4().hex}",
    )
    assert r.status_code == 200
    assert estado_pedido(c, pedido_id) == "orcamento_aceito"
    (status,) = linhas(
        c,
        "select status from public.pagamentos where stripe_payment_intent_id = %s",
        (cob["id"],),
    )
    assert status[0] == "pendente"


def test_falha_do_pagamento_marca_falhou(pg):
    c = pg
    pedido_id = pedido_aceito(c)
    cob = cobrar_ok(c, pedido_id)
    r = webhook(c, TipoEvento.PAGAMENTO_FALHOU, cob["id"], evento_id=f"evt_{uuid.uuid4().hex}")
    assert r.status_code == 200
    (status,) = linhas(
        c,
        "select status from public.pagamentos where stripe_payment_intent_id = %s",
        (cob["id"],),
    )
    assert status[0] == "falhou"
    # depois da falha dá para cobrar de novo (nova cobrança, nova chave)
    nova = cobrar(c, pedido_id).json()
    assert nova["id"] != cob["id"]


def test_repositorios_aditivo_e_ordem_de_estorno(pg):
    """Aditivo (proposto->aprovado->pago), cobrança do aditivo e ordem de estorno no banco."""
    c = pg
    _, contexto, servico = c.pagto
    pedido_id = pedido_aceito(c)
    cob = cobrar_ok(c, pedido_id)
    webhook(c, TipoEvento.PAGAMENTO_CONFIRMADO, cob["id"], evento_id=f"evt_{uuid.uuid4().hex}")
    agora = datetime.now(UTC)

    proposto = Aditivo(
        uuid.uuid4().hex, pedido_id, "Trocar o ralo", 5_000, EstadoAditivo.PROPOSTO, agora
    )
    servico.aditivos.salvar(proposto)
    servico.aditivos.salvar(proposto)  # repetir é inofensivo
    lido = servico.aditivos.obter(proposto.id)
    assert lido.estado is EstadoAditivo.PROPOSTO and lido.valor_centavos == 5_000

    aprovado = replace(lido, estado=EstadoAditivo.APROVADO, aprovado_em=agora)
    servico.aditivos.salvar(aprovado)
    servico.aditivos.salvar(aprovado)
    assert servico.aditivos.obter(proposto.id).estado is EstadoAditivo.APROVADO

    local = CobrancaLocal(
        f"pi_teste_{uuid.uuid4().hex[:12]}",
        pedido_id,
        5_000,
        MeioPagamento.CARTAO,
        EstadoCobranca.AGUARDANDO,
        agora,
        aditivo_id=proposto.id,
        instrucao="segredo-de-teste",
    )
    servico.cobrancas.salvar(local)
    lida = servico.cobrancas.obter(local.id)
    assert lida.meio is MeioPagamento.CARTAO and lida.aditivo_id == proposto.id
    servico.cobrancas.salvar(replace(lida, status=EstadoCobranca.PAGA, pago_em=agora))
    assert servico.aditivos.obter(proposto.id).estado is EstadoAditivo.PAGO
    servico.aditivos.salvar(replace(lido, estado=EstadoAditivo.PAGO))  # não escreve, não quebra

    # estorno parcial: a ordem nasce pendente, fica enviada, a cobrança lembra o devolvido
    servico.cobrancas.salvar(replace(servico.cobrancas.obter(local.id), estornado_centavos=2_000))
    ordem = OrdemEstorno(f"teste/{local.id}", pedido_id, local.id, 2_000, agora)
    servico.ordens.salvar(ordem)
    assert [o.chave for o in servico.ordens.pendentes(pedido_id)] == [ordem.chave]
    servico.ordens.salvar(replace(ordem, estado="enviada", provedor_estorno_id="re_teste"))
    assert servico.ordens.pendentes(pedido_id) == []
    (feita,) = servico.ordens.do_pedido(pedido_id)
    assert feita.estado == "enviada" and feita.provedor_estorno_id == "re_teste"
    assert servico.cobrancas.obter(local.id).estornado_centavos == 2_000
    assert [x.id for x in servico.cobrancas.do_pedido(pedido_id)][0] == cob["id"]
    assert contexto is not None
