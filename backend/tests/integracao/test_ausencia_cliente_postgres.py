"""TERMOS-ET4b no Postgres local: cliente ausente (7.6), retenção (7.4) e desistência sem o
pedido expresso (7.2). As datas passadas são montadas direto no banco (gatilhos desligados na
conexão de superusuário), porque a aplicação não as reescreve."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

from trato.financeiro.ledger import CUSTODIA, a_liberar

from .test_desistencia_postgres import agendado, check_in, desistir, ordens, registros, situacao
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_fluxo_postgres import foto
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    estado_pedido,
    linhas,
    migrations_novas,
    pg,
)

CASO = (
    "select status, analista_id::text, decidido_em, justificativa_texto "
    "from public.ausencias_cliente where pedido_id = %s"
)


def _post(c, quem, url, corpo=None):
    return c.pagto[0].post(url, json=corpo, headers=c.token(quem))


def _no_passado(c, sql, args):
    """Só para montar o cenário: move datas para trás sem os gatilhos de proteção."""
    with c.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute(sql, args)


def _prova():
    return {"foto": foto(), "localizacao": {"latitude": -19.9, "longitude": -43.9}}


def ausente(c, pid):
    url = f"/v1/pedidos/{pid}/acoes/registrar_cliente_ausente"
    return _post(c, "profissional", url, {"prova": _prova()})


def registrado(c, fora_dos_7_dias=False) -> tuple[str, str]:
    pid, cobranca = agendado(c)
    agora = datetime.now(UTC)
    _no_passado(
        c,
        "update public.agendamentos ag set janela_inicio = %s, janela_fim = %s, data = %s "
        "from public.contratos k where k.id = ag.contrato_id and k.pedido_id = %s",
        (agora - timedelta(minutes=30), agora + timedelta(hours=2), agora.date(), pid),
    )
    if fora_dos_7_dias:
        antes = timedelta(days=10)
        for tabela, coluna in (("contratos", "aceito_em"), ("pedido_historico", "ocorrida_em")):
            sql = f"update public.{tabela} set {coluna} = {coluna} - %s where pedido_id = %s"  # noqa: S608
            _no_passado(c, sql, (antes, pid))
    chegada = f"/v1/pedidos/{pid}/ausencia/chegada"
    r = _post(c, "profissional", chegada, _prova())
    assert r.status_code == 200, r.text
    assert _post(c, "profissional", chegada, _prova()).json() == r.json()
    assert ausente(c, pid).status_code == 409  # ainda não passaram os 20 minutos
    _no_passado(
        c,
        "update public.ausencias_cliente set chegada_em = chegada_em - interval '25 minutes' "
        "where pedido_id = %s",
        (pid,),
    )
    r = ausente(c, pid)
    assert r.status_code == 200, r.text
    return pid, cobranca


def justificar(c, pid):
    url = f"/v1/pedidos/{pid}/ausencia/justificativa"
    r = _post(c, "cliente", url, {"texto": "Fiquei preso no hospital."})
    assert r.status_code == 200, r.text


def painel(c, pid, rota="decisao", quem="med_a", **corpo):
    if rota == "decisao":
        corpo = {"aceitar_justificativa": False, "justificativa": "Conferido nas provas."} | corpo
    else:
        corpo = {"motivo": "Conferido o prazo de contestação."} | corpo
    return _post(c, quem, f"/v1/admin/ausencias/{pid}/{rota}", corpo)


def test_expirada_sem_justificativa_devolve_tudo_uma_vez(pg, equipe):  # noqa: F811
    pid, _ = registrado(pg)
    assert painel(pg, pid).status_code == 409
    _no_passado(
        pg,
        "update public.ausencias_cliente set cliente_avisado_em = cliente_avisado_em - "
        "interval '25 hours', justificativa_ate = justificativa_ate - interval '25 hours' "
        "where pedido_id = %s",
        (pid,),
    )
    assert painel(pg, pid, quem="cliente").status_code == 403
    codigos = []
    threads = [
        threading.Thread(target=lambda: codigos.append(painel(pg, pid).status_code))
        for _ in range(6)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(codigos) == [200] + [409] * 5, codigos
    ((status, analista, em, _),) = linhas(pg, CASO, (pid,))
    assert status == "expirada_sem_justificativa" and analista == pg.ids["med_a"] and em
    assert estado_pedido(pg, pid) == "cancelado" and ordens(pg, pid) == [VALOR_ORCAMENTO]
    (linha,) = registros(pg, pid)
    assert linha["tipo"] == "cliente_ausente" and linha["status"] == "cancelado_sem_retencao"
    assert linha["reembolso"] == VALOR_ORCAMENTO
    assert pg.pagto[1].ledger.saldo_da_conta(CUSTODIA, pid) == 0


def test_retencao_proposta_e_confirmada(pg, equipe):  # noqa: F811
    pid, _ = registrado(pg, fora_dos_7_dias=True)
    justificar(pg, pid)
    retencao = VALOR_ORCAMENTO * 3 // 10
    corpo = {
        "retencao_centavos": retencao,
        "retencao_justificativa": "Deslocamento e material comprado.",
        "retencao_comprovantes": ["nota-1"],
    }
    assert painel(pg, pid, **(corpo | {"retencao_centavos": retencao + 1})).status_code == 422
    r = painel(pg, pid, **corpo)
    assert r.status_code == 200, r.text
    assert r.json()["cancelamento_status"] == "proposta_retencao_enviada"
    assert estado_pedido(pg, pid) == "agendado" and ordens(pg, pid) == []
    cancelar = f"/v1/pedidos/{pid}/acoes/cancelar"
    assert _post(pg, "cliente", cancelar, {"prova": {"motivo": "x"}}).status_code == 409
    assert painel(pg, pid, "confirmar").status_code == 409  # dentro do prazo de contestação
    _no_passado(
        pg,
        "update public.cancelamentos_pedido set retencao_mostrada_cliente_em = "
        "retencao_mostrada_cliente_em - interval '12 days' where pedido_id = %s",
        (pid,),
    )
    r = painel(pg, pid, "confirmar")
    assert r.status_code == 200, r.text
    assert painel(pg, pid, "confirmar").status_code == 409
    assert ordens(pg, pid) == [VALOR_ORCAMENTO - retencao]
    ledger = pg.pagto[1].ledger
    assert ledger.saldo_da_conta(a_liberar(pg.ids["profissional"]), pid) == retencao
    (linha,) = registros(pg, pid)
    assert linha["status"] == "confirmado" and linha["reembolso"] == VALOR_ORCAMENTO - retencao


def test_desistencia_sem_pedido_expresso_devolve_tudo(pg):  # noqa: F811
    pid, _ = agendado(pg, consentimento=False)
    check_in(pg, pid)
    assert situacao(pg, pid)["efeito"] == "reembolso_integral"
    r = desistir(pg, pid)
    assert r.status_code == 200, r.text
    assert r.json()["reembolso_centavos"] == VALOR_ORCAMENTO
    assert desistir(pg, pid).json() == r.json()
    assert estado_pedido(pg, pid) == "cancelado" and ordens(pg, pid) == [VALOR_ORCAMENTO]
    (linha,) = registros(pg, pid)
    assert linha["iniciado"] and linha["status"] == "cancelado_sem_retencao" and linha["dentro"]


def test_sem_a_tabela_de_ausencia_o_registro_antigo_continua(pg):  # noqa: F811
    pid, _ = agendado(pg)
    agora = datetime.now(UTC)
    _no_passado(
        pg,
        "update public.agendamentos ag set janela_inicio = %s, janela_fim = %s, data = %s "
        "from public.contratos k where k.id = ag.contrato_id and k.pedido_id = %s",
        (agora - timedelta(minutes=30), agora + timedelta(hours=2), agora.date(), pid),
    )
    mudar = "alter table public.{} rename to {}"
    with pg.local.admin() as con:
        con.execute(mudar.format("ausencias_cliente", "ausencias_fora"))
    try:
        chegada = f"/v1/pedidos/{pid}/ausencia/chegada"
        assert _post(pg, "profissional", chegada, _prova()).status_code == 503
        r = ausente(pg, pid)
        assert r.status_code == 200, r.text
    finally:
        with pg.local.admin() as con:
            con.execute(mudar.format("ausencias_fora", "ausencias_cliente"))
