"""Dinheiro no Postgres LOCAL descartável: ledger, eventos de webhook, disputa, repasses,
concorrência e taxa (C1, A4, A5, A6, M4). Nunca toca no Supabase."""

from __future__ import annotations

import json
import threading
import uuid
from dataclasses import replace
from datetime import UTC, datetime

import pytest

from trato.financeiro.ledger import (
    CLIENTE,
    CUSTODIA,
    ChaveReutilizada,
    EstornoInvalido,
    Lancamento,
    Livro,
    TipoLancamento,
    estornar_pedido,
    repartir_custodia,
)
from trato.pagamentos.provedor import ProvedorFake
from trato.pagamentos.taxa import ConfigTaxa, calcular_taxa
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Papel
from trato.persistencia.config import parametros_globais, taxa_da_versao, versao_vigente
from trato.persistencia.erros import ConflitoDeEstado, RegraDoBanco

from .test_fluxo_postgres import abrir_pedido, acao, enviar_orcamento, foto

pytestmark = pytest.mark.integracao

VALOR = 90_000  # o orçamento de teste: 80.000 + 2,5 x 4.000
TAXA = 6_750  # 7,5% (faixa de teste), congelada no contrato


def agora() -> datetime:
    return datetime.now(UTC)


def contratar(c) -> str:
    """Pedido aberto -> orçamento -> aceite (nasce o contrato com a taxa congelada)."""
    pedido_id = abrir_pedido(c)
    orcamento_id = enviar_orcamento(c, pedido_id)
    r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orcamento_id})
    assert r.status_code == 200, r.text
    return pedido_id


def pagar_pelo_webhook(c, pedido_id: str, valor: int = VALOR, evento_id: str | None = None):
    """Webhook ASSINADO de pagamento (o único caminho para virar `pago_e_retido`)."""
    fake = ProvedorFake()
    c.contexto.segredo_webhook = fake.segredo_webhook
    instante = int(agora().timestamp())
    corpo = json.dumps(
        {
            "id": evento_id or f"evt_{uuid.uuid4().hex}",
            "type": "payment_intent.succeeded",
            "created": instante,
            "data": {
                "object": {
                    "id": f"pi_{pedido_id[:8]}",
                    "amount": valor,
                    "amount_received": valor,
                    "metadata": {"pedido_id": pedido_id},
                }
            },
        },
        separators=(",", ":"),
    ).encode()
    return c.cliente.post(
        "/v1/webhooks/stripe",
        content=corpo,
        headers={"Stripe-Signature": fake.assinar(corpo, instante)},
    )


def ate_em_confirmacao(c) -> str:
    pedido_id = contratar(c)
    assert pagar_pelo_webhook(c, pedido_id).status_code == 200
    inicio = agora().replace(microsecond=0)
    janela = {
        "inicio": (inicio + (estados_dias(2))).isoformat(),
        "fim": (inicio + estados_dias(2) + estados_horas(3)).isoformat(),
    }
    assert (
        acao(c, "profissional", pedido_id, "confirmar_agenda", {"janela": janela}).status_code
        == 200
    )
    codigo = c.cliente.get(f"/v1/pedidos/{pedido_id}", headers=c.token("cliente")).json()[
        "codigo_inicio"
    ]
    entrada = {
        "foto": foto(),
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
        "codigo_inicio": codigo,
    }
    assert acao(c, "profissional", pedido_id, "fazer_check_in", entrada).status_code == 200
    saida = c.cliente.get(f"/v1/pedidos/{pedido_id}", headers=c.token("cliente")).json()[
        "codigo_conclusao"
    ]
    r = acao(
        c, "profissional", pedido_id, "fazer_check_out",
        {"foto_final": foto("fim"), "codigo_conclusao": saida},
    )  # fmt: skip
    assert r.status_code == 200, r.text
    return pedido_id


def estados_dias(n: int):
    from datetime import timedelta

    return timedelta(days=n)


def estados_horas(n: int):
    from datetime import timedelta

    return timedelta(hours=n)


# --- C1: o dinheiro mora no banco ---------------------------------------------------------------


def test_webhook_grava_ledger_e_evento_no_banco_e_reenvio_nao_repete(cenario):
    c = cenario
    pedido_id = contratar(c)
    evento = f"evt_{uuid.uuid4().hex}"

    primeiro = pagar_pelo_webhook(c, pedido_id, evento_id=evento)
    reenvio = pagar_pelo_webhook(c, pedido_id, evento_id=evento)

    assert primeiro.json()["duplicado"] is False and reenvio.json()["duplicado"] is True
    # "Reiniciar o servidor": um repositório novo lê o mesmo dinheiro do banco.
    from trato.persistencia.ledger import LedgerPostgres

    ledger_novo = LedgerPostgres(c.banco)
    (cobranca,) = ledger_novo.lancamentos(pedido_id)
    assert cobranca.tipo is TipoLancamento.COBRANCA and cobranca.valor == VALOR
    assert cobranca.evento_webhook_id == evento  # o lançamento aponta o evento (espelho)
    assert ledger_novo.saldos_pedido(pedido_id, None).retido == VALOR
    with c.local.admin() as con:
        linha = con.execute(
            "select processado_em, assinatura_valida from public.eventos_webhook "
            "where evento_id = %s",
            (evento,),
        ).fetchall()
        assert len(linha) == 1 and linha[0][0] is not None and linha[0][1] is True
        # o pedido mudou NO BANCO na mesma transação
        assert (
            con.execute("select status from public.pedidos where id = %s", (pedido_id,)).fetchone()[
                0
            ]
            == "pago_retido"
        )


def test_operacao_financeira_e_uma_transacao_so(cenario):
    c = cenario
    pedido_id = contratar(c)
    cobranca = Lancamento(
        "cob-atomica", pedido_id, TipoLancamento.COBRANCA, CLIENTE, CUSTODIA, 500, agora()
    )

    with pytest.raises(RuntimeError), c.contexto.transacao():
        c.contexto.ledger.lancar_varios([cobranca])
        assert c.contexto.ledger.saldo_da_conta(CUSTODIA, pedido_id) == 500  # visto dentro dela
        raise RuntimeError("falhou no meio")

    assert c.contexto.ledger.lancamentos(pedido_id) == ()  # nada ficou


def test_pedido_sem_contrato_nao_recebe_lancamento(cenario):
    c = cenario
    pedido_id = abrir_pedido(c)  # aberto, sem contrato
    solto = Lancamento(
        "sem-contrato", pedido_id, TipoLancamento.COBRANCA, CLIENTE, CUSTODIA, 1, agora()
    )
    with pytest.raises(RegraDoBanco):
        c.contexto.ledger.lancar_varios([solto])


# --- A4: o ledger do Python cabe no do banco ----------------------------------------------------


def test_estorno_parcial_do_pedido_passa_pelos_gatilhos_do_banco(cenario):
    c = cenario
    pedido_id = contratar(c)
    pagar_pelo_webhook(c, pedido_id)
    ledger = c.contexto.ledger
    profissional = c.ids["profissional"]

    livro = Livro()
    livro.lancar_varios(ledger.lancamentos(pedido_id))
    repartir_custodia(livro, pedido_id, profissional, TAXA, "t-rep", agora())
    ledger.lancar_varios(livro.lancamentos[1:])  # retenção + taxa

    livro2 = Livro()
    livro2.lancar_varios(ledger.lancamentos(pedido_id))
    estornar_pedido(livro2, pedido_id, 22_500, "t-est", agora())  # 25%: parcial
    ledger.lancar_varios(livro2.lancamentos[len(ledger.lancamentos(pedido_id)) :])

    saldo = ledger.saldos_pedido(pedido_id, profissional)
    assert saldo.cliente_pagou == VALOR - 22_500
    assert saldo.retido == 0
    assert saldo.taxa_trato + saldo.a_liberar == saldo.cliente_pagou
    todos = ledger.lancamentos(pedido_id)
    estornos = [i for i in todos if i.tipo is TipoLancamento.ESTORNO]
    originais = {i.id: i for i in todos}
    for e in estornos:  # cada estorno inverte o original inteiro (o banco confere no COMMIT)
        assert e.valor == originais[e.estorno_de].valor
    # reenviar o mesmo lote não duplica
    ledger.lancar_varios(todos)
    assert len(ledger.lancamentos(pedido_id)) == len(todos)


def test_banco_recusa_estorno_parcial_de_um_lancamento(cenario):
    c = cenario
    pedido_id = contratar(c)
    pagar_pelo_webhook(c, pedido_id)
    (cobranca,) = c.contexto.ledger.lancamentos(pedido_id)
    parcial = replace(
        Lancamento(
            "estorno-torto", pedido_id, TipoLancamento.ESTORNO, CUSTODIA, CLIENTE, 100, agora(),
            estorno_de=cobranca.id,
        ),
    )  # fmt: skip
    with pytest.raises(EstornoInvalido):  # a regra do Python já recusa antes de chegar ao banco
        c.contexto.ledger.lancar_varios([parcial])


def test_mesma_chave_com_dados_diferentes_e_recusada(cenario):
    c = cenario
    pedido_id = contratar(c)
    pagar_pelo_webhook(c, pedido_id)
    (cobranca,) = c.contexto.ledger.lancamentos(pedido_id)
    outro = replace(cobranca, valor=cobranca.valor + 1, id=uuid.uuid4().hex)
    with pytest.raises(ChaveReutilizada):
        c.contexto.ledger.lancar_varios([outro])


# --- A6: concorrência -----------------------------------------------------------------------------


def _em_paralelo(*tarefas):
    barreira = threading.Barrier(len(tarefas))
    resultados: list[object] = [None] * len(tarefas)

    def rodar(i, tarefa):
        barreira.wait()
        try:
            resultados[i] = tarefa()
        except Exception as erro:  # noqa: BLE001 - o teste confere o tipo
            resultados[i] = erro

    fios = [threading.Thread(target=rodar, args=(i, t)) for i, t in enumerate(tarefas)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    return resultados


def test_duas_transicoes_simultaneas_do_pedido_uma_so_vence(cenario):
    c = cenario
    pedido_id = contratar(c)
    lido = c.contexto.pedidos.obter(pedido_id)  # as duas requisições leram o MESMO estado
    sistema = Ator(Papel.SISTEMA, "webhook")
    cliente = Ator(Papel.CLIENTE, c.ids["cliente"])
    pagar = estados.transicionar(
        lido, Acao.CONFIRMAR_PAGAMENTO, sistema, agora(), estados.ProvaPagamento("pi_concorrente")
    )
    cancelar = estados.transicionar(
        lido, Acao.CANCELAR, cliente, agora(), estados.ProvaCancelamento("desisti")
    )

    r1, r2 = _em_paralelo(
        lambda: c.contexto.pedidos.salvar(pagar.pedido, pagar.evento),
        lambda: c.contexto.pedidos.salvar(cancelar.pedido, cancelar.evento),
    )

    erros = [r for r in (r1, r2) if isinstance(r, Exception)]
    assert len(erros) == 1 and isinstance(erros[0], ConflitoDeEstado), (r1, r2)
    final = c.contexto.pedidos.obter(pedido_id)
    assert final.estado in (pagar.pedido.estado, cancelar.pedido.estado)
    eventos = [e.acao for e in c.contexto.pedidos.eventos(pedido_id)]
    assert eventos.count(Acao.CONFIRMAR_PAGAMENTO) + eventos.count(Acao.CANCELAR) == 1


def test_dois_estornos_simultaneos_do_mesmo_lancamento_so_um_grava(cenario):
    c = cenario
    pedido_id = contratar(c)
    pagar_pelo_webhook(c, pedido_id)
    (cobranca,) = c.contexto.ledger.lancamentos(pedido_id)
    ledger = c.contexto.ledger

    def estornar(chave):
        livro = Livro()
        livro.lancar_varios([cobranca])
        e = Lancamento(
            chave, pedido_id, TipoLancamento.ESTORNO, cobranca.credito, cobranca.debito,
            cobranca.valor, agora(), estorno_de=cobranca.id,
        )  # fmt: skip
        return ledger.lancar_varios([e])

    r1, r2 = _em_paralelo(lambda: estornar("est-a"), lambda: estornar("est-b"))

    erros = [r for r in (r1, r2) if isinstance(r, Exception)]
    assert len(erros) == 1 and isinstance(erros[0], EstornoInvalido), (r1, r2)
    assert sum(1 for i in ledger.lancamentos(pedido_id) if i.tipo is TipoLancamento.ESTORNO) == 1
    assert ledger.saldo_da_conta(CUSTODIA, pedido_id) == 0


def test_o_mesmo_lancamento_chegando_junto_grava_uma_vez(cenario):
    c = cenario
    pedido_id = contratar(c)
    item = Lancamento(
        "cob-junto", pedido_id, TipoLancamento.COBRANCA, CLIENTE, CUSTODIA, 700, agora()
    )

    r1, r2 = _em_paralelo(
        lambda: c.contexto.ledger.lancar_varios([item]),
        lambda: c.contexto.ledger.lancar_varios([replace(item, id=uuid.uuid4().hex)]),
    )

    assert not any(isinstance(r, Exception) for r in (r1, r2)), (r1, r2)
    assert len(c.contexto.ledger.lancamentos(pedido_id)) == 1


# --- Disputa ponta a ponta: A3 (taxa congelada) e A5 (idempotência) -----------------------------


def _mediador(c) -> None:
    if "mediador" in c.ids:
        return
    novo = str(uuid.uuid4())
    c.ids["mediador"] = novo
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (novo,))
        con.execute("insert into public.usuarios (id, nome) values (%s, 'Mediador')", (novo,))
        con.execute(
            "insert into public.equipe (usuario_id, papel, alcada_centavos) "
            "values (%s, 'mediador', 100000000)",
            (novo,),
        )


def test_disputa_persiste_e_a_decisao_usa_a_taxa_congelada(cenario):
    c = cenario
    _mediador(c)
    pedido_id = ate_em_confirmacao(c)

    r = c.cliente.post(
        f"/v1/pedidos/{pedido_id}/disputa",
        json={
            "motivo": "mal_feito",
            "descricao": "Parede com mancha.",
            "fotos": [{"arquivo_id": "f2", "tirada_em": agora().isoformat()}],
        },
        headers=c.token("cliente"),
    )
    assert r.status_code == 201, r.text
    assert (
        c.cliente.post(
            f"/v1/pedidos/{pedido_id}/disputa/resposta", headers=c.token("profissional")
        ).status_code
        == 200
    )
    # a disputa mora no banco (um repositório novo a enxerga)
    from trato.persistencia.dinheiro import DisputasPostgres

    aberta = DisputasPostgres(c.banco).obter(pedido_id)
    assert aberta is not None and aberta.valor_congelado == VALOR
    with c.local.admin() as con:
        assert con.execute(
            "select descricao, status from public.disputas where pedido_id = %s", (pedido_id,)
        ).fetchone() == ("Parede com mancha.", "em_analise")

    # A3: a configuração muda DEPOIS do aceite; a disputa usa a taxa congelada do contrato (7,5%).
    # (A taxa vigente é lida do banco; aqui basta conferir que o contrato guardou a dele.)
    corpo = {
        "resultado": "reembolso_parcial",
        "justificativa": "Parte do serviço não foi feita.",
        "percentual_cliente_bps": 2_500,
    }
    url = f"/v1/admin/disputas/{pedido_id}/decisao"
    r = c.cliente.post(url, json=corpo, headers=c.token("mediador"))
    assert r.status_code == 200, r.text

    ledger = c.contexto.ledger
    saldo = ledger.saldos_pedido(pedido_id, c.ids["profissional"])
    parte_mantida = VALOR - VALOR * 2_500 // 10_000
    assert saldo.cliente_pagou == parte_mantida
    assert saldo.taxa_trato == calcular_taxa(parte_mantida, ConfigTaxa(750, 0))
    assert saldo.retido == 0
    assert c.contexto.pedidos.obter(pedido_id).estado is estados.Estado.CONCLUIDO
    with c.local.admin() as con:
        status, reembolso = con.execute(
            "select status, valor_reembolso_centavos from public.disputas where pedido_id = %s",
            (pedido_id,),
        ).fetchone()
        assert (status, reembolso) == ("decidida", VALOR * 2_500 // 10_000)
        (repasses,) = con.execute(
            "select count(*) from public.repasses r join public.contratos k on k.id = r.contrato_id "
            "where k.pedido_id = %s and r.status = 'agendado'",
            (pedido_id,),
        ).fetchone()
        assert repasses == 1
    assert c.contexto.garantias.obter_garantia(pedido_id) is not None  # a garantia abriu no banco

    # A5: refazer a decisão não mexe no dinheiro de novo (409) e nada duplica.
    antes = list(ledger.lancamentos(pedido_id))
    de_novo = c.cliente.post(url, json=corpo, headers=c.token("mediador"))
    assert de_novo.status_code == 409
    assert list(ledger.lancamentos(pedido_id)) == antes


# --- Repasses, garantias, retrabalho, avaliações -----------------------------------------------


def test_repasse_e_liberado_uma_vez_so(cenario):
    from trato.api.repositorios import Repasse

    c = cenario
    pedido_id = contratar(c)
    pagar_pelo_webhook(c, pedido_id)
    ledger = c.contexto.ledger
    livro = Livro()
    livro.lancar_varios(ledger.lancamentos(pedido_id))
    repartir_custodia(livro, pedido_id, c.ids["profissional"], TAXA, "rp-rep", agora())
    ledger.lancar_varios(livro.lancamentos[1:])

    repasse = Repasse(
        pedido_id, c.ids["profissional"], VALOR, TAXA, VALOR - TAXA, "confirmacao_cliente", "rp-1"
    )
    criado = c.contexto.repasses.criar(repasse)
    de_novo = c.contexto.repasses.criar(replace(repasse, id=uuid.uuid4().hex))
    assert de_novo.id == criado.id  # a mesma chave devolve a mesma ordem

    c.contexto.repasses.vincular_transferencia(criado.id, "tr_123")
    assert c.contexto.repasses.por_transferencia("tr_123").id == criado.id
    lanc = ledger.lancamentos(pedido_id)[-1]
    c.contexto.repasses.marcar_liberado(criado.id, lanc.id, agora())
    with pytest.raises(ConflitoDeEstado):
        c.contexto.repasses.marcar_liberado(criado.id, lanc.id, agora())
    assert c.contexto.repasses.obter(criado.id).status == "liberado"


def test_avaliacao_e_retrabalho_persistem(cenario):
    from trato.api.repositorios_app import Avaliacao
    from trato.garantias import ConfigGarantia, abrir_garantia, abrir_retrabalho

    c = cenario
    pedido_id = contratar(c)

    avaliacao = Avaliacao(
        pedido_id, "cliente_para_profissional", c.ids["cliente"], c.ids["profissional"], 5,
        "Ótimo", ("pontual",), agora(),
    )  # fmt: skip
    c.contexto.avaliacoes.salvar(avaliacao)
    lida = c.contexto.avaliacoes.obter(pedido_id, "cliente_para_profissional")
    assert lida is not None and lida.nota_geral == 5 and lida.etiquetas == ("pontual",)
    assert c.contexto.avaliacoes.obter(pedido_id, "profissional_para_cliente") is None

    garantia = abrir_garantia(agora(), None, ConfigGarantia())
    c.contexto.garantias.salvar_garantia(pedido_id, garantia)
    c.contexto.garantias.salvar_garantia(pedido_id, garantia)  # repetir é inofensivo
    assert c.contexto.garantias.obter_garantia(pedido_id).dias == garantia.dias
    retrabalho = abrir_retrabalho(garantia, "Mancha voltou", agora(), ConfigGarantia())
    c.contexto.garantias.salvar_retrabalho(pedido_id, retrabalho)
    (lido,) = c.contexto.garantias.retrabalhos(pedido_id)
    assert lido.descricao == "Mancha voltou" and lido.estado.value == "aberto"


# --- M4: uma fonte da taxa, com o mínimo ----------------------------------------------------------


def test_taxa_do_postgres_respeita_o_minimo_como_a_calculadora(cenario):
    c = cenario
    with c.banco.transacao() as con:
        versao = versao_vigente(con)
        base = parametros_globais(con, versao)
        com_minimo = {**base, "taxa_minima_centavos": 500}
        config = taxa_da_versao(con, versao, 1_000, com_minimo)
    assert config == ConfigTaxa(taxa_bps=750, taxa_minima_centavos=500)
    # 7,5% de 1.000 = 75, abaixo do mínimo: vale o mínimo (mesma conta do Python em todo lugar)
    assert calcular_taxa(1_000, config) == 500
    # a calculadora do app (TaxaPostgres) e o contrato usam a mesma função
    assert c.contexto.taxa.calcular(50_000) == calcular_taxa(50_000, ConfigTaxa(750, 0))


# --- Migration NOVA (não aplicada no Supabase): ordens de estorno --------------------------------


def test_migration_ordens_estorno_aplica_protege_e_desfaz(cenario):
    import psycopg

    c = cenario
    from .pg_local import RAIZ

    subir = (RAIZ / "supabase/migrations/20261030120000_ordens_estorno.sql").read_text("utf-8")
    descer = (RAIZ / "supabase/rollback/ordens_estorno_rollback.sql").read_text("utf-8")
    pedido_id = contratar(c)
    with c.local.admin() as con:
        con.execute(subir)
        contrato, cliente = con.execute(
            "select id, cliente_id from public.contratos where pedido_id = %s", (pedido_id,)
        ).fetchone()
        pagamento = con.execute(
            "insert into public.pagamentos (contrato_id, pagador_id, tipo, meio, valor_centavos, "
            "chave_idempotencia, status, confirmado_em) "
            "values (%s, %s, 'adiantamento', 'pix', 1000, %s, 'confirmado', now()) returning id",
            (contrato, cliente, f"pg-{uuid.uuid4().hex}"),
        ).fetchone()[0]

        def ordem(valor=500, chave=None, pag=pagamento):
            return con.execute(
                "insert into public.ordens_estorno (contrato_id, pagamento_id, valor_centavos, "
                "chave_idempotencia) values (%s, %s, %s, %s) returning id",
                (contrato, pag, valor, chave or f"o-{uuid.uuid4().hex}"),
            ).fetchone()[0]

        criada = ordem(chave="din/x/cancelamento/pi_1")
        with pytest.raises(psycopg.errors.UniqueViolation):  # a chave é a idempotência
            ordem(chave="din/x/cancelamento/pi_1")
        with pytest.raises(psycopg.errors.CheckViolation):
            ordem(valor=0)
        with pytest.raises(psycopg.errors.RestrictViolation):  # valor congelado
            con.execute(
                "update public.ordens_estorno set valor_centavos = 1 where id = %s", (criada,)
            )
        with pytest.raises(psycopg.errors.Error):  # nunca se apaga
            con.execute("delete from public.ordens_estorno where id = %s", (criada,))
        con.execute(  # só o andamento muda
            "update public.ordens_estorno set estado = 'enviada', enviada_em = now(), "
            "provedor_estorno_id = 're_1' where id = %s",
            (criada,),
        )
        with pytest.raises(psycopg.errors.CheckViolation):  # estornado não passa do valor pago
            con.execute(
                "update public.pagamentos set estornado_centavos = 1001 where id = %s", (pagamento,)
            )

        con.execute(descer)
        assert con.execute("select to_regclass('public.ordens_estorno')").fetchone()[0] is None
        colunas = con.execute(
            "select count(*) from information_schema.columns "
            "where table_name = 'pagamentos' and column_name = 'estornado_centavos'"
        ).fetchone()[0]
        assert colunas == 0
