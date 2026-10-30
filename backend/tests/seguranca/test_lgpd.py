"""F8.3: exportar, pedir exclusão (dois passos, carência, anonimização) e consentimentos."""

from __future__ import annotations

from ambiente_seg import CLIENTE, OUTRO, cab, montar

URL = "/v1/me/exclusao"


def semear(amb) -> None:  # type: ignore[no-untyped-def]
    f = amb.fonte
    f.perfis[CLIENTE.id] = {"nome": "Ana Souza", "cpf": "12345678909", "telefone": "11987654321"}
    f.perfis[OUTRO.id] = {"nome": "Beto Lima"}
    f.documentos[CLIENTE.id] = ["docs/ana/rg.jpg"]
    f.mensagens.append({"autor_id": CLIENTE.id, "corpo": "oi"})
    f.mensagens.append({"autor_id": OUTRO.id, "corpo": "segredo do outro"})
    f.ledger.append({"id": 1, "valor_centavos": 1000})
    f.auditoria.append({"id": 1, "acao": "x"})


def pedir_e_confirmar(amb, token="t-cli"):  # noqa: S107  # type: ignore[no-untyped-def]
    passo1 = amb.cliente.post(URL, headers=cab(token))
    assert passo1.status_code == 200, passo1.text
    return passo1.json(), lambda t: amb.cliente.post(
        URL, json={"token_confirmacao": t}, headers=cab(token)
    )


# --- Exportar --------------------------------------------------------------------------


def test_exporta_meus_dados_em_json_sem_dados_de_outros():
    amb = montar()
    semear(amb)
    r = amb.cliente.get("/v1/me/dados", headers=cab("t-cli"))
    assert r.status_code == 200
    assert "attachment" in r.headers["content-disposition"]
    corpo = r.json()
    assert corpo["formato"] == "trato-lgpd-1" and corpo["titular_id"] == CLIENTE.id
    assert corpo["dados"]["perfil"]["nome"] == "Ana Souza"
    assert [m["corpo"] for m in corpo["dados"]["mensagens"]] == ["oi"]
    assert "Beto" not in r.text and "segredo do outro" not in r.text
    categorias = {c["categoria"] for c in corpo["retencao_por_lei"]}
    assert {"ledger_financeiro", "auditoria"} <= categorias
    assert "dado_pessoal.exportacao" in amb.auditoria
    evento = amb.seg.auditoria_em_memoria.eventos[-1]
    assert evento["motivo"] and "Ana" not in repr(evento)  # motivo obrigatório, sem dado pessoal


def test_exportar_exige_login_e_tem_limite_de_taxa():
    amb = montar()
    assert amb.cliente.get("/v1/me/dados").status_code == 401
    codigos = [amb.cliente.get("/v1/me/dados", headers=cab("t-cli")).status_code for _ in range(7)]
    assert codigos[:5] == [200] * 5 and codigos[5] == 429  # lgpd_exportar: 5 por hora (config)


# --- Exclusão --------------------------------------------------------------------------


def test_passo_1_mostra_o_que_some_e_o_que_fica_com_prazos_da_configuracao():
    amb = montar()
    passo1, _ = pedir_e_confirmar(amb)
    assert passo1["status"] == "aguardando_confirmacao" and passo1["token_confirmacao"]
    assert passo1["carencia_dias"] == 7 and passo1["pendencias"] == []
    mantido = {m["categoria"]: m["prazo_dias"] for m in passo1["sera_mantido"]}
    assert mantido["ledger_financeiro"] == 1825 and mantido["logs_acesso"] == 180
    assert "perfil" in passo1["sera_anonimizado"]
    # nada foi apagado ainda
    assert amb.fonte.anonimizados == set()


def test_fluxo_completo_confirma_espera_a_carencia_e_anonimiza_sem_tocar_nos_imutaveis():
    amb = montar()
    semear(amb)
    ledger, auditoria, mensagens = (
        list(amb.fonte.ledger),
        list(amb.fonte.auditoria),
        list(amb.fonte.mensagens),
    )
    passo1, confirmar = pedir_e_confirmar(amb)
    r = confirmar(passo1["token_confirmacao"])
    assert r.status_code == 200 and r.json()["status"] == "agendada"
    # dentro da carência nada acontece
    equipe = cab("t-equipe")
    assert amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=equipe).json() == {
        "anonimizadas": 0, "adiadas": 0,
    }  # fmt: skip
    assert amb.fonte.perfis[CLIENTE.id]["nome"] == "Ana Souza"
    amb.relogio.avancar(days=7, minutes=1)
    assert (
        amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=equipe).json()["anonimizadas"] == 1
    )
    assert amb.fonte.perfis[CLIENTE.id] == {"nome": "Usuário anonimizado", "status": "anonimizado"}
    assert CLIENTE.id not in amb.fonte.documentos
    # outro titular intacto
    assert amb.fonte.perfis[OUTRO.id]["nome"] == "Beto Lima"
    # ledger, auditoria e mensagens imutáveis: exatamente como estavam
    assert (amb.fonte.ledger, amb.fonte.auditoria, amb.fonte.mensagens) == (
        ledger,
        auditoria,
        mensagens,
    )
    assert amb.cliente.get(URL, headers=cab("t-cli")).json() == {"pedido": None}  # concluída
    for acao in (
        "dado_pessoal.exclusao_solicitada",
        "dado_pessoal.exclusao_agendada",
        "dado_pessoal.anonimizacao",
    ):
        assert acao in amb.auditoria
    assert all(
        e["motivo"]
        for e in amb.seg.auditoria_em_memoria.eventos
        if e["acao"].startswith("dado_pessoal.")
    )
    # rodar de novo não anonimiza duas vezes
    assert (
        amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=equipe).json()["anonimizadas"] == 0
    )


def test_codigo_errado_ou_expirado_nao_agenda():
    amb = montar()
    passo1, confirmar = pedir_e_confirmar(amb)
    assert confirmar("codigo-errado").status_code == 403
    amb.relogio.avancar(minutes=31)
    r = confirmar(passo1["token_confirmacao"])
    assert r.status_code == 410
    assert confirmar(passo1["token_confirmacao"]).status_code == 409  # pedido expirou, recomeçar
    assert amb.fonte.anonimizados == set()


def test_confirmar_sem_pedir_antes_e_recusado():
    amb = montar()
    r = amb.cliente.post(URL, json={"token_confirmacao": "x"}, headers=cab("t-cli"))
    assert r.status_code == 409


def test_pendencias_impedem_confirmar_e_adiam_a_anonimizacao():
    amb = montar()
    semear(amb)
    abertas: list[str] = []
    amb.fonte._pendencias = lambda _u: abertas
    passo1, confirmar = pedir_e_confirmar(amb)
    abertas.append("pedido em andamento")
    r = confirmar(passo1["token_confirmacao"])
    assert r.status_code == 409 and "pedido em andamento" in r.json()["detail"]
    abertas.clear()
    passo1, confirmar = pedir_e_confirmar(amb)
    assert confirmar(passo1["token_confirmacao"]).status_code == 200
    abertas.append("disputa aberta")  # apareceu durante a carência
    amb.relogio.avancar(days=8)
    r = amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=cab("t-equipe"))
    assert r.json() == {"anonimizadas": 0, "adiadas": 1}
    assert amb.fonte.perfis[CLIENTE.id]["nome"] == "Ana Souza"
    abertas.clear()
    assert (
        amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=cab("t-equipe")).json()[
            "anonimizadas"
        ]
        == 1
    )


def test_titular_pode_cancelar_durante_a_carencia():
    amb = montar()
    semear(amb)
    passo1, confirmar = pedir_e_confirmar(amb)
    confirmar(passo1["token_confirmacao"])
    assert amb.cliente.get(URL, headers=cab("t-cli")).json()["pedido"]["status"] == "agendada"
    assert amb.cliente.post(URL, headers=cab("t-cli")).status_code == 409  # já agendada
    assert amb.cliente.delete(URL, headers=cab("t-cli")).status_code == 204
    amb.relogio.avancar(days=30)
    assert (
        amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=cab("t-equipe")).json()[
            "anonimizadas"
        ]
        == 0
    )
    assert amb.fonte.perfis[CLIENTE.id]["nome"] == "Ana Souza"
    assert amb.cliente.delete(URL, headers=cab("t-cli")).status_code == 404


def test_carencia_vem_da_configuracao(monkeypatch):
    from trato.lgpd import config as cfg

    monkeypatch.setenv("TRATO_LGPD_CARENCIA_EXCLUSAO_DIAS", "0")
    monkeypatch.setenv("TRATO_LGPD_RETENCAO_DIAS", '{"ledger_financeiro": 3650}')
    cfg.obter_config_lgpd.cache_clear()
    try:
        amb = montar()
        passo1, confirmar = pedir_e_confirmar(amb)
        assert passo1["carencia_dias"] == 0
        assert {m["categoria"]: m["prazo_dias"] for m in passo1["sera_mantido"]}[
            "ledger_financeiro"
        ] == 3650
        confirmar(passo1["token_confirmacao"])
        assert (
            amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=cab("t-equipe")).json()[
                "anonimizadas"
            ]
            == 1
        )
    finally:
        cfg.obter_config_lgpd.cache_clear()


def test_so_equipe_processa_exclusoes():
    amb = montar()
    assert amb.cliente.post("/v1/lgpd/exclusoes/processar", headers=cab("t-cli")).status_code == 403


def test_exclusao_exige_login():
    assert montar().cliente.post(URL).status_code == 401


# --- Consentimentos --------------------------------------------------------------------

CONS = "/v1/me/consentimentos"


def test_registra_consulta_e_revoga_consentimento_sem_apagar_historico():
    amb = montar()
    corpo = {"finalidade": "comunicacoes_marketing", "aceito": True, "versao_texto": "2026-10"}
    assert amb.cliente.post(CONS, json=corpo, headers=cab("t-cli")).status_code == 201
    amb.relogio.avancar(days=3)
    assert (
        amb.cliente.post(CONS, json={**corpo, "aceito": False}, headers=cab("t-cli")).status_code
        == 201
    )
    dados = amb.cliente.get(CONS, headers=cab("t-cli")).json()
    assert dados["vigentes"]["comunicacoes_marketing"]["aceito"] is False
    assert [h["aceito"] for h in dados["historico"]] == [True, False]  # histórico só cresce
    assert amb.cliente.get(CONS, headers=cab("t-outro")).json()["historico"] == []
    assert "consentimento.registrado" in amb.auditoria and "consentimento.revogado" in amb.auditoria


def test_finalidade_desconhecida_e_aceite_obrigatorio_nao_se_revoga():
    amb = montar()
    base = {"aceito": True, "versao_texto": "v1"}
    assert (
        amb.cliente.post(
            CONS, json={**base, "finalidade": "inventada"}, headers=cab("t-cli")
        ).status_code
        == 422
    )
    r = amb.cliente.post(
        CONS,
        json={"finalidade": "termos_de_uso", "aceito": False, "versao_texto": "v1"},
        headers=cab("t-cli"),
    )
    assert r.status_code == 422 and "exclusão" in r.json()["detail"]
    assert (
        amb.cliente.post(
            CONS, json={"finalidade": "termos_de_uso", **base}, headers=cab("t-cli")
        ).status_code
        == 201
    )


def test_consentimento_exige_login_e_rejeita_campos_extras():
    amb = montar()
    corpo = {"finalidade": "termos_de_uso", "aceito": True, "versao_texto": "v1"}
    assert amb.cliente.post(CONS, json=corpo).status_code == 401
    assert (
        amb.cliente.post(
            CONS, json={**corpo, "usuario_id": "outro"}, headers=cab("t-cli")
        ).status_code
        == 422
    )


def test_modo_postgres_sem_adaptador_responde_503_em_vez_de_perder_dado(monkeypatch):
    from trato.config import obter_config

    amb = montar()
    del amb.contexto.extras["lgpd"]
    monkeypatch.setattr(obter_config(), "trato_persistencia", "postgres")
    assert amb.cliente.get("/v1/me/dados", headers=cab("t-cli")).status_code == 503
    assert (
        amb.cliente.post(
            CONS,
            json={"finalidade": "termos_de_uso", "aceito": True, "versao_texto": "v"},
            headers=cab("t-cli"),
        ).status_code
        == 503
    )
