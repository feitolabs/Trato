"""TERMOS-BE-SAC no Postgres local (migration 20261125224500): protocolo do banco, repetição,
painel, contestação intocada pelo atendimento, texto original e o app sem as tabelas."""

from __future__ import annotations

import threading

from .test_ausencia_cliente_postgres import _post
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)
from .test_provas_ausencia_postgres import com_retencao, contestar

URL = "/v1/sac/chamados"
PAINEL = "/v1/admin/chamados"
NOVO = {"categoria": "reclamacao", "assunto": "Serviço", "texto": "Preciso de ajuda."}


def _get(c, quem, url):
    return c.pagto[0].get(url, headers=c.token(quem))


def test_protocolo_do_banco_repeticao_e_painel(pg, equipe):  # noqa: F811
    respostas = []
    corpo = NOVO | {"assunto": "Toques juntos"}
    threads = [
        threading.Thread(target=lambda: respostas.append(_post(pg, "cliente", URL, corpo)))
        for _ in range(6)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(r.status_code for r in respostas) == [200] * 5 + [201], [
        r.text for r in respostas
    ]
    dados = respostas[0].json()
    assert dados["protocolo"].startswith("SAC-") and dados["responder_ate"]
    cid = dados["id"]
    assert _get(pg, "profissional", f"{URL}/{cid}").status_code == 404
    assert _get(pg, "cliente", PAINEL).status_code == 403
    base = f"{PAINEL}/{cid}"
    assert _post(pg, "adm_a", f"{base}/assumir", {}).status_code == 200
    assert _post(pg, "adm_b", f"{base}/assumir", {}).status_code == 409
    nota = {"texto": "Nota só da equipe", "interna": True}
    assert _post(pg, "adm_a", f"{base}/mensagens", nota).status_code == 200
    r = _post(pg, "adm_a", f"{base}/mensagens", {"texto": "Vamos ver hoje."})
    assert r.status_code == 200 and r.json()["status"] == "respondido", r.text
    prazo = {"novo_prazo_ate": "2027-01-10T12:00:00Z", "motivo": "Falta o retorno do banco."}
    assert _post(pg, "adm_a", f"{base}/prazo", prazo).status_code == 200
    copia = _get(pg, "cliente", f"{URL}/{cid}").json()
    assert [m["autor"] for m in copia["mensagens"]] == ["usuario", "equipe", "sistema"]
    assert "Nota só da equipe" not in str(copia)
    fila = _get(pg, "adm_a", f"{PAINEL}?protocolo={dados['protocolo']}").json()
    assert fila["total"] == 1 and fila["itens"][0]["solicitante"]
    fim = {"mensagem": "Resolvido no atendimento."}
    assert _post(pg, "adm_a", f"{base}/encerrar", fim).status_code == 200
    assert _post(pg, "adm_a", f"{base}/encerrar", fim).status_code == 409
    assert _post(pg, "cliente", f"{URL}/{cid}/mensagens", {"texto": "oi"}).status_code == 409
    contato = NOVO | {"canal": "telefone", "contato": "31999999999"}
    r = _post(pg, "adm_a", PAINEL, contato)
    assert r.status_code == 201 and r.json()["usuario_id"] is None, r.text


def test_atendimento_nao_decide_a_contestacao_e_vinculo_exige_o_usuario(pg, equipe):  # noqa: F811
    pid = com_retencao(pg)
    leitura = f"/v1/admin/pedidos/{pid}/conversas/leitura"
    relato = {"motivo": "Análise do relato do caso.", "base": "relato"}
    painel_abre = NOVO | {"canal": "painel", "usuario_id": pg.ids["cliente"], "pedido_id": pid}
    assert _post(pg, "adm_a", PAINEL, painel_abre).status_code == 201
    assert _post(pg, "adm_a", leitura, relato).status_code == 409  # criado pela equipe
    assert contestar(pg, pid).status_code == 200
    r = _post(pg, "adm_a", leitura, relato)
    assert r.status_code == 200, r.text
    assert "texto_exibido" in r.text
    fila = _get(pg, "adm_a", f"{PAINEL}?pedido_id={pid}&categoria=contestacao").json()
    cid = fila["itens"][0]["id"]
    base = f"{PAINEL}/{cid}"
    assert _post(pg, "adm_a", f"{base}/mensagens", {"texto": "Recebido."}).status_code == 200
    fim = {"mensagem": "Tentando encerrar por aqui."}
    assert _post(pg, "adm_a", f"{base}/encerrar", fim).status_code == 409
    caso = _get(pg, "adm_a", f"/v1/admin/ausencias/{pid}").json()
    assert caso["contestacao"]["status"] == "aberta"
    url = f"/v1/admin/ausencias/{pid}/contestacao/decisao"
    decisao = {"resultado": "mantida", "resposta": "Conferimos os comprovantes."}
    assert _post(pg, "med_b", url, decisao).status_code == 200
    caso = _get(pg, "adm_a", f"/v1/admin/ausencias/{pid}").json()
    assert caso["contestacao"]["status"] == "mantida"
    assert caso["contestacao"]["resposta"] == "Conferimos os comprovantes."


def test_sem_as_tabelas_503_e_o_resto_segue(pg):  # noqa: F811
    mudar = "alter table public.{} rename to {}"
    with pg.local.admin() as con:
        con.execute(mudar.format("chamado_mensagens", "chamado_mensagens_fora"))
    try:
        r = _post(pg, "cliente", URL, NOVO)
        assert r.status_code == 503 and "indisponível" in r.text
        assert _get(pg, "cliente", URL).status_code == 503
        r = _get(pg, "cliente", "/v1/me/moedas")
        assert r.status_code == 200 and "creditos" in r.json(), r.text
    finally:
        with pg.local.admin() as con:
            con.execute(mudar.format("chamado_mensagens_fora", "chamado_mensagens"))
    assert linhas(pg, "select count(*) from public.chamado_mensagens", ())[0][0] >= 0
