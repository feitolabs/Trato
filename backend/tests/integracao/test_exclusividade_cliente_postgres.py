"""TERMOS-ET5 no Postgres local (migrations 20261125150000 e 20261125223000): exclusividade paga
pelo cliente, estorno com validade, contratação, prazo e o app sem as funções."""

from __future__ import annotations

import threading
import uuid
from datetime import UTC, datetime, timedelta

from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Acao

from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_fluxo_postgres import abrir_pedido, enviar_orcamento
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    cobrar_ok,
    estado_pedido,
    linhas,
    migrations_novas,
    pg,
    webhook,
)

SALDO = "select public.moedas_saldo(%s, 'cliente', now())"


def _post(c, quem, url, corpo=None):
    return c.pagto[0].post(url, json=corpo, headers=c.token(quem))


def dar_moedas(c, quantidade=300, dias=90):
    with c.local.admin() as con:
        quem = c.ids["profissional"]
        con.execute(  # o profissional precisa atender a categoria e a região do pedido
            "insert into public.profissional_categorias (profissional_id, categoria_id) "
            "values (%s, %s) on conflict do nothing",
            (quem, c.categoria_id),
        )
        con.execute(
            "insert into public.profissional_regioes (profissional_id, cidade_id) "
            "select %s, %s where not exists (select 1 from public.profissional_regioes "
            "where profissional_id = %s and cidade_id = %s)",
            (quem, c.cidade_id, quem, c.cidade_id),
        )
        con.execute(
            "update public.perfis_profissional set atende_presencial = true where usuario_id = %s",
            (quem,),
        )
        con.execute(
            "insert into public.moedas_lancamentos (usuario_id, tipo, quantidade, "
            "chave_idempotencia, carteira, expira_em, criada_em) "
            "values (%s, 'bonus_avaliacao', %s, %s, 'cliente', %s, now())",
            (
                c.ids["cliente"],
                quantidade,
                f"teste:{uuid.uuid4()}",
                datetime.now(UTC) + timedelta(days=dias),
            ),
        )


def saldo(c) -> int:
    return int(linhas(c, SALDO, (c.ids["cliente"],))[0][0])


def pedir(c, pid, chave=None, quem="cliente"):
    corpo = {
        "profissional_id": c.ids["profissional"],
        "chave_idempotencia": chave or f"chave-{uuid.uuid4().hex}",
    }
    return _post(c, quem, f"/v1/pedidos/{pid}/exclusividade-cliente", corpo)


def situacao(c, pid):
    url = f"/v1/pedidos/{pid}/exclusividade-cliente"
    return c.pagto[0].get(url, headers=c.token("cliente")).json()


def pagar_aceitando(c, pid):
    orcamento = enviar_orcamento(c, pid)
    url = f"/v1/pedidos/{pid}/acoes/aceitar_orcamento"
    r = _post(c, "cliente", url, {"prova": {"orcamento_id": orcamento}})
    assert r.status_code == 200, r.text
    c.pagto[1].usuarios.registrar_dados_privados(c.ids["cliente"], "52998224725", None)
    cobranca = cobrar_ok(c, pid)["id"]
    c.pagto[2].provedor.marcar_paga(cobranca)
    r = webhook(c, TipoEvento.PAGAMENTO_CONFIRMADO, cobranca, evento_id=f"evt_{uuid.uuid4().hex}")
    assert r.status_code == 200, r.text


def test_pede_debita_reserva_e_conclui_so_no_pagamento(pg):  # noqa: F811
    dar_moedas(pg)
    antes = saldo(pg)
    pid = abrir_pedido(pg)
    chave = f"chave-{uuid.uuid4().hex}"
    r = pedir(pg, pid, chave)
    assert r.status_code == 201, r.text
    assert pedir(pg, pid, chave).status_code == 200
    assert saldo(pg) == antes - 100 and estado_pedido(pg, pid) == "reservado"
    dados = situacao(pg, pid)
    assert dados["disponivel"] and dados["saldo_livre"] == antes - 100
    assert dados["exclusividade"]["status"] == "ativa" and dados["creditos"]
    pagar_aceitando(pg, pid)
    assert situacao(pg, pid)["exclusividade"]["status"] == "concluida"
    assert saldo(pg) == antes - 100 and estado_pedido(pg, pid) == "pago_e_retido"


def test_seis_juntos_cobram_uma_vez(pg):  # noqa: F811
    dar_moedas(pg)
    antes = saldo(pg)
    pid = abrir_pedido(pg)
    codigos = []
    threads = [
        threading.Thread(target=lambda: codigos.append(pedir(pg, pid).status_code))
        for _ in range(6)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(codigos) == [201] + [409] * 5, codigos
    assert saldo(pg) == antes - 100


def test_desistencia_e_falha_do_trato_devolvem_uma_vez(pg, equipe):  # noqa: F811
    dar_moedas(pg)
    antes = saldo(pg)
    pid = abrir_pedido(pg)
    eid = pedir(pg, pid).json()["id"]
    url = f"/v1/profissional/exclusividades/{eid}/desistir"
    r = _post(pg, "profissional", url)
    assert r.status_code == 200, r.text
    assert r.json() == {"resultado": "ok", "moedas_devolvidas": 100}
    assert _post(pg, "profissional", url).json()["resultado"] == "ja_devolvida"
    assert saldo(pg) == antes and estado_pedido(pg, pid) == "aberto"
    outra = pedir(pg, pid).json()["id"]
    falha = f"/v1/admin/exclusividades/{outra}/falha-trato"
    corpo = {"motivo": "O aplicativo ficou fora do ar."}
    assert _post(pg, "cliente", falha, corpo).status_code == 403
    for _ in range(2):
        r = _post(pg, "med_a", falha, corpo)
        assert r.status_code == 200, r.text
    assert saldo(pg) == antes and estado_pedido(pg, pid) == "aberto"


def test_prazo_expira_reabre_sem_devolver(pg):  # noqa: F811
    dar_moedas(pg)
    antes = saldo(pg)
    pid = abrir_pedido(pg)
    eid = pedir(pg, pid).json()["id"]
    contexto = pg.pagto[1]
    depois = datetime.now(UTC) + timedelta(hours=49)
    expiradas = contexto.exclusividades.expirar_cliente(depois)
    assert uuid.UUID(eid).hex in [e.exclusividade_id for e in expiradas]
    assert saldo(pg) == antes - 100 and estado_pedido(pg, pid) == "aberto"
    assert Acao.EXPIRAR_EXCLUSIVIDADE in [e.acao for e in contexto.pedidos.eventos(pid)]


def test_cancelar_encerra_sem_devolver(pg):  # noqa: F811
    dar_moedas(pg)
    antes = saldo(pg)
    pid = abrir_pedido(pg)
    pedir(pg, pid)
    url = f"/v1/pedidos/{pid}/acoes/cancelar"
    r = _post(pg, "cliente", url, {"prova": {"motivo": "Desisti"}})
    assert r.status_code == 200, r.text
    assert situacao(pg, pid)["exclusividade"]["status"] == "cancelada"
    assert saldo(pg) == antes - 100


def test_medida_de_conta_ativa_barra(pg, equipe):  # noqa: F811
    dar_moedas(pg)
    pid = abrir_pedido(pg)
    with pg.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute(
            "insert into public.medidas_conta (protocolo, usuario_id, tipo, motivo_usuario, "
            "clausulas, efeito_pedidos_valores, como_contestar, origem, aplicada_por) values "
            "('MED-2026-990001', %s, 'restricao', 'Teste', '{20.1}', 'Nenhum', 'App', "
            "'analista', %s)",
            (pg.ids["cliente"], pg.ids["med_a"]),
        )
    try:
        assert pedir(pg, pid).json()["codigo"] == "conta_com_restricao"
    finally:
        with pg.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute("delete from public.medidas_conta where protocolo = 'MED-2026-990001'")


def test_sem_as_funcoes_o_app_continua(pg):  # noqa: F811
    dar_moedas(pg)
    pid = abrir_pedido(pg)
    assinatura = "(uuid,uuid,uuid,uuid,text,timestamptz,boolean)"
    mudar = "alter function public.{}" + assinatura + " rename to {}"
    with pg.local.admin() as con:
        con.execute(mudar.format("exclusividade_cliente_solicitar", "excl_fora"))
    try:
        assert pedir(pg, pid).status_code == 503
        assert situacao(pg, pid)["disponivel"] is False
        pagar_aceitando(pg, pid)
        assert estado_pedido(pg, pid) == "pago_e_retido"
    finally:
        with pg.local.admin() as con:
            con.execute(mudar.format("excl_fora", "exclusividade_cliente_solicitar"))
