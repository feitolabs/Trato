"""TERMOS-BE-MEDIDAS no Postgres local (migration 20261125224600): medida com protocolo do
banco, contestação, fim automático, 72 h, rotas antigas e lista de exclusividades."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

from trato.api.medidas import aplicar_automatica, encerrar_vencidas, iniciar_agendadas

from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_exclusividade_cliente_postgres import dar_moedas, pedir
from .test_fluxo_postgres import abrir_pedido
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

PAINEL = "/v1/admin/medidas"


def _post(c, quem, url, corpo):
    return c.pagto[0].post(url, json=corpo, headers=c.token(quem))


def _get(c, quem, url):
    return c.pagto[0].get(url, headers=c.token(quem))


def status(c, quem="profissional") -> str:
    sql = "select status from public.usuarios where id = %s"
    return linhas(c, sql, (c.ids[quem],))[0][0]


def aplicar(c, quem="adm_a", **extra):
    corpo = {
        "usuario_id": c.ids["profissional"],
        "tipo": "restricao",
        "motivo": "Orçamentos repetidos no mesmo pedido.",
        "clausulas": ["11.4"],
        "dias": 5,
    } | extra
    return _post(c, quem, PAINEL, corpo)


def limpar(c):
    """Devolve a conta ao normal para os outros testes."""
    with c.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.medida_contestacoes")
        con.execute("delete from public.medidas_conta")
        con.execute(
            "update public.usuarios set status = 'ativo' where id = %s", (c.ids["profissional"],)
        )


def test_aplica_contesta_decide_e_o_agendador_devolve(pg, equipe):  # noqa: F811
    limpar(pg)
    try:
        respostas = []
        threads = [threading.Thread(target=lambda: respostas.append(aplicar(pg))) for _ in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert sorted(r.status_code for r in respostas) == [200] * 4 + [201], [
            r.text for r in respostas
        ]
        dados = respostas[0].json()
        assert dados["protocolo"].startswith("MED-") and status(pg) == "restrito"
        mid = dados["id"]
        url = f"/v1/me/medidas/{mid}/contestacao"
        r = _post(pg, "profissional", url, {"versao": "Foi um erro do app."})
        assert r.status_code == 200, r.text
        assert r.json()["contestacao"]["protocolo"].startswith("CMD-")
        decisao = f"{PAINEL}/{mid}/contestacao/decisao"
        corpo = {"resultado": "mantida", "resposta": "As provas confirmam a medida."}
        assert _post(pg, "adm_a", decisao, corpo).status_code == 422
        assert _post(pg, "adm_b", decisao, corpo).status_code == 200
        assert _post(pg, "adm_b", decisao, corpo).status_code == 409
        contexto = pg.pagto[1]
        depois = datetime.now(UTC) + timedelta(days=5, minutes=5)
        assert encerrar_vencidas(contexto, depois) == 0 or status(pg) == "ativo"
        lista = _get(pg, "adm_a", f"{PAINEL}?usuario_id={pg.ids['profissional']}").json()
        assert lista["total"] == 1 and lista["itens"][0]["usuario_nome"]
    finally:
        limpar(pg)


def test_automatica_72h_e_o_banco_nao_deixa_emendar(pg):  # noqa: F811
    limpar(pg)
    contexto = pg.pagto[1]
    quem = pg.ids["profissional"]
    try:
        medida, nova = aplicar_automatica(contexto, quem, "restricao", "Alerta um.", ("20.2",), 999)
        assert nova and medida.fim_em - medida.inicio_em == timedelta(hours=72)
        assert status(pg) == "restrito"
        try:
            aplicar_automatica(contexto, quem, "restricao", "Alerta dois.", ("20.2",))
        except Exception as erro:  # noqa: BLE001 - o gatilho do banco recusa o encadeamento
            assert "72" in str(erro) or "Analista" in str(erro)
        else:
            raise AssertionError("encadeou medidas automáticas")
        assert encerrar_vencidas(contexto, medida.fim_em + timedelta(minutes=1)) == 1
        assert status(pg) == "ativo"
    finally:
        limpar(pg)


def test_rotas_antigas_criam_e_revertem_a_medida(pg, equipe):  # noqa: F811
    limpar(pg)
    quem = pg.ids["profissional"]
    corpo = {"usuario_id": quem, "motivo": "Denúncia interna sigilosa."}
    try:
        r = _post(pg, "adm_a", "/v1/admin/risco/bloqueio-preventivo", corpo)
        assert r.status_code == 200, r.text
        assert status(pg) == "bloqueado"
        minhas = _get(pg, "profissional", "/v1/me/medidas")
        assert minhas.status_code in (200, 401), minhas.text
        assert "sigilosa" not in minhas.text
        sql = "select tipo, revertida_em is null from public.medidas_conta where usuario_id = %s"
        assert linhas(pg, sql, (quem,)) == [("bloqueio_preventivo", True)]
        r = _post(pg, "adm_a", "/v1/admin/risco/desbloqueio", corpo)
        assert r.status_code == 200, r.text
        assert status(pg) == "ativo"
        assert linhas(pg, sql, (quem,)) == [("bloqueio_preventivo", False)]
        url = f"/v1/admin/usuarios/{quem}/status"
        novo = {"status": "restrito", "motivo": "Revisão de cadastro."}
        assert _post(pg, "adm_a", url, novo).status_code == 200
        assert status(pg) == "restrito" and len(linhas(pg, sql, (quem,))) == 2
        mudar = "alter table public.{} rename to {}"
        with pg.local.admin() as con:
            con.execute(mudar.format("medida_contestacoes", "medida_contestacoes_fora"))
        try:
            assert _get(pg, "adm_a", PAINEL).status_code == 503
            r = _post(pg, "adm_a", url, {"status": "ativo", "motivo": "Voltou ao normal."})
            assert r.status_code == 200, r.text
        finally:
            with pg.local.admin() as con:
                con.execute(mudar.format("medida_contestacoes_fora", "medida_contestacoes"))
    finally:
        limpar(pg)


def test_lista_de_exclusividades_do_cliente(pg, equipe):  # noqa: F811
    dar_moedas(pg)
    pid = abrir_pedido(pg)
    eid = pedir(pg, pid).json()["id"]
    r = _get(pg, "adm_a", f"/v1/admin/exclusividades?pedido_id={pid}&status=ativa")
    assert r.status_code == 200, r.text
    (item,) = r.json()["itens"]
    assert item["id"].replace("-", "") == eid.replace("-", "") and item["moedas"] == 100
    assert item["estornada"] is False and item["cliente_nome"]


def test_encerramento_sem_falta_so_bloqueia_no_dia_avisado(pg, equipe):  # noqa: F811
    limpar(pg)
    try:
        r = aplicar(pg, tipo="encerramento", dias=None, sem_falta=True, clausulas=["20.8"])
        assert r.status_code == 201, r.text
        assert r.json()["vigente"] is False and status(pg) == "ativo"
        contexto = pg.pagto[1]
        dia = datetime.fromisoformat(r.json()["inicio_em"])
        assert dia - datetime.fromisoformat(r.json()["avisado_em"]) == timedelta(days=30)
        assert iniciar_agendadas(contexto, dia - timedelta(seconds=1)) == 0
        assert iniciar_agendadas(contexto, dia) == 1 and status(pg) == "bloqueado"
        assert iniciar_agendadas(contexto, dia) == 0
    finally:
        limpar(pg)


def test_historico_dos_termos_responde_com_o_banco_local(pg):  # noqa: F811
    r = pg.pagto[0].get("/v1/termos/versoes")
    assert r.status_code == 200, r.text
    assert "1.1" in [v["versao"] for v in r.json()["itens"]]
