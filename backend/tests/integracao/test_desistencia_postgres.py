"""TERMOS-ET4a no Postgres local com a migration 20261125141500: desistência, consentimento,
decisão do analista, 8 toques juntos e o app sem a tabela."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.provedor import TipoEvento

from .test_disputa_painel_postgres import decidir, equipe  # noqa: F401 - `equipe` é fixture
from .test_fluxo_postgres import foto
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    CPF_SINTETICO,
    VALOR_ORCAMENTO,
    estado_pedido,
    linhas,
    migrations_novas,
    pedido_aceito,
    pg,
    webhook,
)

REGISTRO = (
    "select tipo, status, servico_iniciado, dentro_arrependimento_7d, reembolso_centavos, "
    "analista_id::text, decidido_em, motivo from public.cancelamentos_pedido where pedido_id = %s"
)


def _post(c, quem, url, corpo=None):
    return c.pagto[0].post(url, json=corpo, headers=c.token(quem))


def desistir(c, pid, corpo=None):
    return _post(c, "cliente", f"/v1/pedidos/{pid}/desistir", corpo)


def situacao(c, pid):
    return c.pagto[0].get(f"/v1/pedidos/{pid}/desistencia", headers=c.token("cliente")).json()


def agendado(c, consentimento=False) -> tuple[str, str]:
    pid = pedido_aceito(c)
    c.pagto[1].usuarios.registrar_dados_privados(c.ids["cliente"], CPF_SINTETICO, None)
    corpo = {"meio": "pix", "consentimento_execucao_imediata": consentimento}
    r = _post(c, "cliente", f"/v1/pedidos/{pid}/cobranca", corpo)
    assert r.status_code == 201, r.text
    cobranca = r.json()["id"]
    c.pagto[2].provedor.marcar_paga(cobranca)
    assert webhook(c, TipoEvento.PAGAMENTO_CONFIRMADO, cobranca).status_code == 200
    inicio = datetime.now(UTC).replace(microsecond=0) + timedelta(days=2)
    janela = {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
    url = f"/v1/pedidos/{pid}/acoes/confirmar_agenda"
    r = _post(c, "profissional", url, {"prova": {"janela": janela}})
    assert r.status_code == 200, r.text
    return pid, cobranca


def check_in(c, pid):
    codigo = c.pagto[0].get(f"/v1/pedidos/{pid}", headers=c.token("cliente")).json()
    prova = {
        "foto": foto(),
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
        "codigo_inicio": codigo["codigo_inicio"],
    }
    url = f"/v1/pedidos/{pid}/acoes/fazer_check_in"
    r = _post(c, "profissional", url, {"prova": prova})
    assert r.status_code == 200, r.text


def ordens(c, pid) -> list[int]:
    return [o.valor_centavos for o in c.pagto[2].ordens.do_pedido(pid)]


def registros(c, pid) -> list[dict]:
    nomes = ("tipo", "status", "iniciado", "dentro", "reembolso", "analista", "em", "motivo")
    return [dict(zip(nomes, linha, strict=True)) for linha in linhas(c, REGISTRO, (pid,))]


def test_sem_check_in_cancela_devolve_tudo_e_registra_uma_vez(pg):  # noqa: F811
    pid, _ = agendado(pg)
    antes = situacao(pg, pid)
    assert antes["efeito"] == "reembolso_integral" and antes["dentro_do_arrependimento"]
    r = desistir(pg, pid)
    assert r.status_code == 200, r.text
    assert r.json()["reembolso_centavos"] == VALOR_ORCAMENTO and r.json()["protocolo"]
    assert desistir(pg, pid, {"motivo": "outra vez"}).json() == r.json()
    (linha,) = registros(pg, pid)
    assert linha["tipo"] == "desistencia_arrependimento"
    assert linha["status"] == "cancelado_sem_retencao" and linha["dentro"]
    assert linha["reembolso"] == VALOR_ORCAMENTO and linha["motivo"] == ""
    assert len(ordens(pg, pid)) == 1 and estado_pedido(pg, pid) == "cancelado"
    assert pg.pagto[1].ledger.saldo_da_conta(CUSTODIA, pid) == 0


def test_oito_toques_juntos(pg):  # noqa: F811
    pid, _ = agendado(pg)
    respostas = []
    threads = [
        threading.Thread(target=lambda: respostas.append(desistir(pg, pid))) for _ in range(8)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert [r.status_code for r in respostas] == [200] * 8, [r.text for r in respostas]
    assert len({r.json()["protocolo"] for r in respostas}) == 1
    assert len(registros(pg, pid)) == 1 and len(ordens(pg, pid)) == 1


def test_consentimento_caso_com_servico_iniciado_e_decisao_do_analista(pg, equipe):  # noqa: F811
    pid, _ = agendado(pg, consentimento=True)
    sql = (
        "select consentimento_execucao_imediata as sim, consentimento_execucao_imediata_em as em "
        "from public.contratos where pedido_id = %s"
    )
    (contrato,) = linhas(pg, sql, (pid,))
    assert contrato[0] and contrato[1] is not None
    check_in(pg, pid)
    assert situacao(pg, pid)["efeito"] == "analise"
    r = desistir(pg, pid)
    assert r.status_code == 200, r.text
    assert r.json()["situacao"] == "em_analise" and ordens(pg, pid) == []
    (linha,) = registros(pg, pid)
    assert linha["status"] == "aguardando_analise" and linha["iniciado"]
    assert estado_pedido(pg, pid) == "em_disputa"
    resposta = _post(pg, "profissional", f"/v1/pedidos/{pid}/disputa/resposta")
    assert resposta.status_code == 200, resposta.text
    parte = VALOR_ORCAMENTO // 2
    negado = decidir(pg, pid, "cliente", "reembolso_parcial", valor_cliente_centavos=parte)
    assert negado.status_code == 403
    r = decidir(pg, pid, "med_a", "reembolso_parcial", valor_cliente_centavos=parte)
    assert r.status_code == 200, r.text
    (linha,) = registros(pg, pid)
    assert linha["status"] == "confirmado" and linha["reembolso"] == parte
    assert linha["analista"] == pg.ids["med_a"] and linha["em"] is not None
    assert ordens(pg, pid) == [parte]
    assert desistir(pg, pid).json()["situacao"] == "analisado"


def test_sem_a_tabela_o_app_continua_funcionando(pg):  # noqa: F811
    pid, _ = agendado(pg)
    outro, _ = agendado(pg)
    mudar = "alter table public.{} rename to {}"
    with pg.local.admin() as con:
        con.execute(mudar.format("cancelamentos_pedido", "cancelamentos_fora"))
    try:
        assert situacao(pg, pid)["registro"] is None
        r = desistir(pg, pid)
        assert r.status_code == 200, r.text
        assert r.json()["protocolo"] is None
        assert r.json()["reembolso_centavos"] == VALOR_ORCAMENTO
        assert desistir(pg, pid).status_code == 409  # sem registro: já está cancelado
        assert len(ordens(pg, pid)) == 1
        url = f"/v1/pedidos/{outro}/acoes/cancelar"
        r = _post(pg, "cliente", url, {"prova": {"motivo": "Desisti"}})
        assert r.status_code == 200, r.text
    finally:
        with pg.local.admin() as con:
            con.execute(mudar.format("cancelamentos_fora", "cancelamentos_pedido"))
