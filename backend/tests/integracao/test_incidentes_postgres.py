"""TERMOS-BE-INCID no Postgres local: as rotas do painel respeitam as travas da migration
20261125225500, repetem sem duplicar e o encerramento solta a retenção só sem outra trava."""

from __future__ import annotations

import threading

import pytest

from trato.api.liberacao import relato_de_seguranca

from .test_ausencia_cliente_postgres import _post
from .test_compensacao_postgres import avisos, concluido  # noqa: F401 - `avisos` é fixture
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_liberacao_automatica_postgres import (  # noqa: F401 - `publicado` é fixture
    agendador,
    publicado,
    repasses,
)
from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao
URL = "/v1/admin/incidentes"
DESFECHO = "Apurado e resolvido com as partes."


def test_ciclo_no_banco_e_retencao_ate_a_ultima_trava(publicado):  # noqa: F811
    c = publicado
    pid = concluido(c)
    novo = {
        "tipo": "acidente_dano",
        "descricao": "Vidro quebrado.",
        "contato": "cliente@exemplo.test",
        "canal": "email",
        "pedido_id": pid,
    }
    r = _post(c, "med_a", URL, novo)
    assert r.status_code == 201, r.text
    iid = r.json()["id"]
    assert r.json()["protocolo"].startswith("INC-")
    repetido = _post(c, "med_a", URL, novo)
    assert repetido.status_code == 200 and repetido.json()["id"] == iid
    dano = {
        "alvo_tipo": "chat",
        "denunciado_id": c.ids["profissional"],
        "pedido_id": pid,
        "motivo": "dano",
        "detalhes": "Quebrou o vidro da sala.",
    }
    assert _post(c, "cliente", "/v1/denuncias", dano).status_code == 201

    cautela = {"status": "cautela_adotada"}
    assert _post(c, "med_a", f"{URL}/{iid}/status", cautela).status_code == 409
    medida = {"tipo": "reter_valor", "descricao": "Valor retido."}
    for _ in range(2):
        r = _post(c, "med_a", f"{URL}/{iid}/medidas", medida)
        assert r.status_code == 200 and len(r.json()["medidas"]) == 1, r.text
    for status in ("cautela_adotada", "cautela_adotada", "em_apuracao"):
        r = _post(c, "med_a", f"{URL}/{iid}/status", {"status": status})
        assert r.status_code == 200 and r.json()["status"] == status, r.text
    assert agendador(c, pid).rodar_uma_vez().falhas == 0 and repasses(c, pid) == 0

    corpo = {"desfecho": DESFECHO}
    assert _post(c, "med_a", f"{URL}/{iid}/encerrar", corpo).status_code == 403
    respostas = []

    def fechar():
        respostas.append(_post(c, "adm_a", f"{URL}/{iid}/encerrar", corpo))

    threads = [threading.Thread(target=fechar) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert [r.status_code for r in respostas] == [200] * 4, [r.text for r in respostas]
    assert len({r.json()["encerrado_em"] for r in respostas}) == 1
    assert _post(c, "med_a", f"{URL}/{iid}/medidas", medida).status_code == 409
    r = c.pagto[0].get(f"{URL}?pedido_id={pid}&status=encerrado", headers=c.token("med_a"))
    assert r.status_code == 200 and r.json()["total"] == 1, r.text
    r = c.pagto[0].get(f"{URL}/{iid}", headers=c.token("med_a"))
    assert r.json()["desfecho"] == DESFECHO

    feitas = linhas(
        c,
        "select acao, count(*) from public.auditoria where entidade = 'incidentes_seguranca' "
        "and entidade_id = %s and acao <> 'seguranca.incidente_consultado' group by acao",
        (iid,),
    )
    assert {tuple(x) for x in feitas} == {
        ("seguranca.incidente_aberto", 1),
        ("seguranca.incidente_medida", 1),
        ("seguranca.incidente_andamento", 2),
        ("seguranca.incidente_encerrado", 1),
    }

    # incidente encerrado: a denúncia de dano ainda segura
    assert relato_de_seguranca(c.pagto[1], pid) == "denuncia_grave"
    assert agendador(c, pid).rodar_uma_vez().falhas == 0 and repasses(c, pid) == 0
    with c.local.admin() as con:
        con.execute("update public.alertas_risco set resolvido = true where pedido_id = %s", (pid,))
    assert agendador(c, pid).rodar_uma_vez().falhas == 0 and repasses(c, pid) == 1
