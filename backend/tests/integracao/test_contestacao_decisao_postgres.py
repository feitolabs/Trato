"""TERMOS-BE-87 (8.7) no Postgres local: contestação, concorrência, gatilho e compensação."""

from __future__ import annotations

import threading
from datetime import timedelta

import pytest

from .test_compensacao_postgres import liberar
from .test_disputa_painel_postgres import (  # noqa: F401 - `equipe` é fixture
    _juntos,
    aprovar,
    decidir,
    em_disputa,
    equipe,
    ordens,
)
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

pytestmark = pytest.mark.integracao

TEXTO = "A análise não considerou o horário combinado."
BASE = "/v1/admin/contestacoes-disputa"


def contestar(c, pid, quem="cliente", texto=TEXTO):
    return c.pagto[0].post(
        f"/v1/pedidos/{pid}/disputa/contestacoes",
        json={"o_que_faltou": texto},
        headers=c.token(quem),
    )


def analisar(c, cid, quem="med_b", resultado="alterada", nova="reembolso_parcial", valor=1_000):
    corpo = {"resultado": resultado, "resposta": "Revi as provas do pedido."}
    if nova:
        corpo |= {"nova_decisao": nova, "novo_valor_reembolso_centavos": valor}
    return c.pagto[0].post(f"{BASE}/{cid}/decisao", json=corpo, headers=c.token(quem))


def segunda(c, cid, quem):
    corpo = {"aprovar": True, "motivo": "Conferi a análise e as provas."}
    return c.pagto[0].post(f"{BASE}/{cid}/aprovacao", json=corpo, headers=c.token(quem))


def decidida(c) -> str:
    pid, _ = em_disputa(c)
    r = decidir(c, pid, "med_a", "reembolso_parcial", valor_cliente_centavos=5_000)
    assert r.status_code == 200 and r.json()["estado"] == "decidida", r.text
    return pid


def registros(c, pid):
    sql = (
        "select status, efeito_financeiro, canal from public.disputa_contestacoes "
        "where pedido_id = %s order by aberta_em"
    )
    return [tuple(r) for r in linhas(c, sql, (pid,))]


def test_fluxo_completo_com_concorrencia_e_compensacao(equipe):  # noqa: F811
    c = equipe
    http = c.pagto[0]
    pid = decidida(c)

    respostas: list[int] = []
    barreira = threading.Barrier(3)

    def abrir() -> None:
        barreira.wait()
        respostas.append(contestar(c, pid).status_code)

    fios = [threading.Thread(target=abrir) for _ in range(3)]
    [f.start() for f in fios]
    [f.join(40) for f in fios]
    assert sorted(respostas) == [200, 200, 201]
    assert registros(c, pid) == [("aberta", "nenhum", "app")]
    cid = contestar(c, pid).json()["id"]

    r = analisar(c, cid, "med_a")
    assert r.status_code == 403 and r.json()["codigo"] == "analista_impedido", r.text
    antes = ordens(c, pid)
    codigos = _juntos(
        lambda: analisar(c, cid, "med_b", valor=9_000),
        lambda: analisar(c, cid, "adm_b", valor=8_000),
    )
    assert codigos == [200, 409]
    assert registros(c, pid) == [("aguardando_aprovacao", "nenhum", "app")]
    detalhe = http.get(f"{BASE}/{cid}", headers=c.token("med_a")).json()
    outros = [q for q in ("adm_a", "adm_b") if c.ids[q] != detalhe["analista_id"]]
    assert segunda(c, cid, outros[0]).status_code == 200
    assert registros(c, pid) == [("alterada", "pendente_financeiro", "app")]
    assert ordens(c, pid) == antes  # a nova decisão não move dinheiro

    # o id da contestação aprovada serve para a compensação (só do que já foi liberado)
    liberar(c, pid, timedelta(days=15))
    corpo = {"pedido_id": pid, "contestacao_id": cid, "valor_centavos": 100}
    corpo["motivo"] = "Reembolso maior decidido na contestação."
    r = http.post("/v1/admin/compensacoes", json=corpo, headers=c.token("med_a"))
    assert r.status_code == 200 and r.json()["resultado"] == "ok", r.text

    # a outra parte contesta contra a decisão que vale agora e a mantém
    outro = contestar(c, pid, "profissional", "Discordo do novo valor.").json()["id"]
    r = analisar(c, outro, "med_b", "mantida", None)
    assert r.status_code == 200 and r.json()["status"] == "mantida", r.text
    assert r.json()["decisao_vigente"]["reembolso_centavos"] in (8_000, 9_000)
    avisos = linhas(
        c,
        "select tipo, count(distinct usuario_id) from public.notificacoes "
        "where tipo like 'disputa.contesta%%' and dados ->> 'pedido_id' = %s group by tipo "
        "order by tipo",
        (pid,),
    )
    assert [tuple(a) for a in avisos] == [
        ("disputa.contestacao_decidida", 2),
        ("disputa.contestada", 2),
    ]
    acoes = linhas(
        c,
        "select count(*) from public.auditoria where entidade = 'disputa_contestacoes' "
        "and entidade_id::text = any(%s)",
        ([cid, outro],),
    )
    assert acoes[0][0] == 3  # análise, aprovação e a segunda análise


def test_pelo_atendimento_e_alcada_na_aprovacao_do_painel(equipe):  # noqa: F811
    c = equipe
    http = c.pagto[0]
    pid, _ = em_disputa(c)
    r = decidir(c, pid, "med_baixa")
    assert r.json()["estado"] == "aguardando_aprovacao", r.text
    assert contestar(c, pid).json()["codigo"] == "sem_decisao"
    assert aprovar(c, pid, "adm_a").status_code == 200
    chamado = {"categoria": "contestacao", "assunto": "Decisão", "texto": "Quero contestar."}
    r = http.post("/v1/sac/chamados", json=chamado, headers=c.token("cliente"))
    assert r.status_code in (200, 201), r.text
    corpo = {"pedido_id": pid, "contestante_id": c.ids["cliente"], "chamado_id": r.json()["id"]}
    corpo["o_que_faltou"] = TEXTO
    r = http.post(BASE, json=corpo, headers=c.token("adm_b"))
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    # quem aprovou a disputa não analisa a contestação
    assert analisar(c, cid, "adm_a").status_code == 403
    assert registros(c, pid) == [("aberta", "nenhum", "sac")]


def test_sem_a_tabela_503_e_o_resto_segue(equipe):  # noqa: F811
    c = equipe
    http = c.pagto[0]
    pid = decidida(c)
    nome = "public.disputa_contestacoes"
    with c.local.admin() as con:
        con.execute(f"alter table {nome} rename to disputa_contestacoes_fora")
    try:
        for r in (contestar(c, pid), http.get(BASE, headers=c.token("med_a"))):
            assert r.status_code == 503 and r.json()["codigo"] == "indisponivel", r.text
        assert http.get(f"/v1/pedidos/{pid}", headers=c.token("cliente")).status_code == 200
    finally:
        with c.local.admin() as con:
            con.execute(
                "alter table public.disputa_contestacoes_fora rename to disputa_contestacoes"
            )
    assert contestar(c, pid).status_code == 201
