"""Correções do módulo Operação: fila paginada de verdade, contagem, assumir e decisão obsoleta."""

from datetime import timedelta

from admin_ambiente import AGORA, PEDIDO, adm, cab  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria, VerificacaoAdmin

BASE = "/v1/admin"
VER = f"{BASE}/verificacoes"


def _semear_verificacoes(adm, n: int) -> None:
    for i in range(n):
        adm.admin.verificacoes.adicionar(
            VerificacaoAdmin(
                f"ver-x{i:03d}", f"pro-x{i:03d}", f"Profissional {i:03d}", "verificado",
                "enviada", AGORA - timedelta(hours=200 - i),
            )
        )  # fmt: skip


# --- Verificação: paginação, busca e contagem ----------------------------------------------------


def test_fila_pagina_alem_de_100_sem_perder_nem_repetir(adm):
    _semear_verificacoes(adm, 130)  # + a ver-1 do ambiente = 131
    vistos: list[str] = []
    deslocamento = 0
    while True:
        r = adm.cliente.get(
            f"{VER}?limite=50&deslocamento={deslocamento}", headers=cab("t-cadastro")
        ).json()
        vistos += [v["id"] for v in r["itens"]]
        deslocamento += 50
        if deslocamento >= r["total"]:
            break
    assert r["total"] == 131
    assert len(vistos) == 131 and len(set(vistos)) == 131


def test_busca_por_nome_ou_id_curto_vem_do_servidor(adm):
    _semear_verificacoes(adm, 30)
    adm.admin.verificacoes.adicionar(
        VerificacaoAdmin(
            "ver-ana", "pro-ana", "Ana Eletricista", "verificado", "enviada", AGORA,
            publico_id="PRO-A1B2",
        )
    )  # fmt: skip
    por_nome = adm.cliente.get(f"{VER}?busca=ana ele", headers=cab("t-cadastro")).json()
    assert [v["id"] for v in por_nome["itens"]] == ["ver-ana"] and por_nome["total"] == 1
    por_id = adm.cliente.get(f"{VER}?busca=pro-a1b2", headers=cab("t-cadastro")).json()
    assert [v["id"] for v in por_id["itens"]] == ["ver-ana"]


def test_contagem_traz_todos_os_status(adm):
    _semear_verificacoes(adm, 3)
    decidir = {"aprovar": False, "motivo": "Selfie ilegível"}
    adm.cliente.post(f"{VER}/ver-x000/decisao", json=decidir, headers=cab("t-cadastro"))
    r = adm.cliente.get(f"{VER}/contagem", headers=cab("t-cadastro"))
    assert r.status_code == 200
    assert r.json() == {"enviada": 3, "em_analise": 0, "aprovada": 0, "recusada": 1}
    assert adm.cliente.get(f"{VER}/contagem", headers=cab("t-mediador")).status_code == 403


# --- Verificação: assumir ------------------------------------------------------------------------


def test_assumir_poe_em_analise_com_responsavel_e_audita(adm):
    adm.admin.verificacoes.nomear("eq-cadastro", "Carla Cadastro")
    r = adm.cliente.post(
        f"{VER}/ver-1/assumir", json={"motivo": "Vou analisar agora"}, headers=cab("t-cadastro")
    )
    assert r.status_code == 200
    assert r.json()["status"] == "em_analise"
    assert r.json()["analista_id"] == "eq-cadastro"
    assert r.json()["analista_nome"] == "Carla Cadastro"
    registros, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="verificacao.assumida"), 5, 0)
    assert registros[0].ator_id == "eq-cadastro" and registros[0].motivo == "Vou analisar agora"


def test_outra_pessoa_nao_decide_nem_assume_sem_substituir(adm):
    adm.admin.verificacoes.nomear("eq-cadastro", "Carla Cadastro")
    corpo = {"motivo": "Vou analisar agora"}
    adm.cliente.post(f"{VER}/ver-1/assumir", json=corpo, headers=cab("t-cadastro"))

    decisao = {"aprovar": True, "motivo": "Tudo conferido"}
    r = adm.cliente.post(f"{VER}/ver-1/decisao", json=decisao, headers=cab("t-administrador"))
    assert r.status_code == 409 and "Carla Cadastro" in r.json()["detail"]

    outra = adm.cliente.post(f"{VER}/ver-1/assumir", json=corpo, headers=cab("t-administrador"))
    assert outra.status_code == 409

    troca = {"motivo": "Carla saiu de férias", "substituir": True}
    r = adm.cliente.post(f"{VER}/ver-1/assumir", json=troca, headers=cab("t-administrador"))
    assert r.status_code == 200 and r.json()["analista_id"] == "eq-administrador"
    r = adm.cliente.post(f"{VER}/ver-1/decisao", json=decisao, headers=cab("t-administrador"))
    assert r.status_code == 200 and r.json()["status"] == "aprovada"


def test_quem_assumiu_decide_e_cadastro_decidido_nao_se_assume(adm):
    corpo = {"motivo": "Vou analisar agora"}
    adm.cliente.post(f"{VER}/ver-1/assumir", json=corpo, headers=cab("t-cadastro"))
    decisao = {"aprovar": True, "motivo": "Tudo conferido"}
    r = adm.cliente.post(f"{VER}/ver-1/decisao", json=decisao, headers=cab("t-cadastro"))
    assert r.status_code == 200
    de_novo = adm.cliente.post(f"{VER}/ver-1/assumir", json=corpo, headers=cab("t-cadastro"))
    assert de_novo.status_code == 409


def test_assumir_exige_motivo_e_permissao_de_decidir(adm):
    url = f"{VER}/ver-1/assumir"
    assert adm.cliente.post(url, json={}, headers=cab("t-cadastro")).status_code == 422
    corpo = {"motivo": "Vou analisar agora"}
    assert adm.cliente.post(url, json=corpo, headers=cab("t-seguranca")).status_code == 403
    assert (
        adm.cliente.post(f"{VER}/xx/assumir", json=corpo, headers=cab("t-cadastro")).status_code
        == 404
    )


# --- Disputas: lista leve, situação, contagem e decisão obsoleta ---------------------------------


def test_lista_de_disputas_traz_os_nomes_sem_abrir_o_detalhe(adm):
    adm.semear_disputa()
    item = adm.cliente.get(f"{BASE}/disputas", headers=cab("t-mediador")).json()["itens"][0]
    assert item["cliente_nome"] == "Maria Cliente"
    assert item["profissional_nome"] == "João Pintor"


def test_situacao_e_contagem_das_disputas(adm):
    adm.semear_disputa()
    cab_med = cab("t-mediador")
    contagem = adm.cliente.get(f"{BASE}/disputas/contagem", headers=cab_med).json()
    assert contagem == {"abertas": 1, "decididas": 0, "todas": 1}

    corpo = {"resultado": "liberar_tudo", "justificativa": "Fotos mostram o serviço feito"}
    adm.cliente.post(f"{BASE}/disputas/{PEDIDO}/decisao", json=corpo, headers=cab_med)

    contagem = adm.cliente.get(f"{BASE}/disputas/contagem", headers=cab_med).json()
    assert contagem == {"abertas": 0, "decididas": 1, "todas": 1}
    for situacao, total in (("abertas", 0), ("decididas", 1), ("todas", 1)):
        r = adm.cliente.get(f"{BASE}/disputas?situacao={situacao}", headers=cab_med).json()
        assert r["total"] == total, situacao
    invalida = adm.cliente.get(f"{BASE}/disputas?situacao=outra", headers=cab_med)
    assert invalida.status_code == 422


def test_decisao_sobre_estado_velho_da_409_sem_mexer_em_nada(adm):
    adm.semear_disputa()  # o profissional já respondeu: em_analise
    antes = list(adm.lancamentos())
    corpo = {
        "resultado": "liberar_tudo",
        "justificativa": "Fotos mostram o serviço feito",
        "estado_esperado": "aberta",  # a pessoa abriu a tela antes da resposta
    }
    r = adm.cliente.post(f"{BASE}/disputas/{PEDIDO}/decisao", json=corpo, headers=cab("t-mediador"))
    assert r.status_code == 409 and "mudou" in r.json()["detail"]
    assert list(adm.lancamentos()) == antes

    corpo["estado_esperado"] = "em_analise"
    r = adm.cliente.post(f"{BASE}/disputas/{PEDIDO}/decisao", json=corpo, headers=cab("t-mediador"))
    assert r.status_code == 200 and r.json()["estado"] == "decidida"


# --- Disputas: assumir ---------------------------------------------------------------------------

DISP = f"{BASE}/disputas/{PEDIDO}"
DECISAO_OK = {"resultado": "liberar_tudo", "justificativa": "Fotos mostram o serviço feito"}


def test_assumir_disputa_mostra_responsavel_na_lista_e_no_detalhe(adm):
    adm.semear_disputa()
    adm.admin.responsaveis_disputa.nomear("eq-mediador", "Marta Mediadora")
    r = adm.cliente.post(
        f"{DISP}/assumir", json={"motivo": "Vou analisar o caso"}, headers=cab("t-mediador")
    )
    assert r.status_code == 200
    assert r.json()["responsavel_id"] == "eq-mediador"
    assert r.json()["responsavel_nome"] == "Marta Mediadora"
    item = adm.cliente.get(f"{BASE}/disputas", headers=cab("t-mediador")).json()["itens"][0]
    assert item["responsavel_nome"] == "Marta Mediadora"
    registros, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="disputa.assumida"), 5, 0)
    assert registros[0].ator_id == "eq-mediador" and registros[0].motivo == "Vou analisar o caso"


def test_disputa_assumida_por_outra_pessoa_nao_se_decide_sem_substituir(adm):
    adm.semear_disputa()
    adm.admin.responsaveis_disputa.nomear("eq-mediador", "Marta Mediadora")
    corpo = {"motivo": "Vou analisar o caso"}
    adm.cliente.post(f"{DISP}/assumir", json=corpo, headers=cab("t-mediador"))
    antes = list(adm.lancamentos())

    r = adm.cliente.post(f"{DISP}/decisao", json=DECISAO_OK, headers=cab("t-administrador"))
    assert r.status_code == 409 and "Marta Mediadora" in r.json()["detail"]
    assert list(adm.lancamentos()) == antes
    outra = adm.cliente.post(f"{DISP}/assumir", json=corpo, headers=cab("t-administrador"))
    assert outra.status_code == 409

    troca = {"motivo": "Marta está de folga hoje", "substituir": True}
    r = adm.cliente.post(f"{DISP}/assumir", json=troca, headers=cab("t-administrador"))
    assert r.status_code == 200 and r.json()["responsavel_id"] == "eq-administrador"
    r = adm.cliente.post(f"{DISP}/decisao", json=DECISAO_OK, headers=cab("t-administrador"))
    assert r.status_code == 200 and r.json()["estado"] == "decidida"
    # Decidida: o responsável some da resposta e não se assume mais.
    assert r.json()["responsavel_id"] is None
    assert (
        adm.cliente.post(f"{DISP}/assumir", json=corpo, headers=cab("t-mediador")).status_code
        == 409
    )


def test_quem_assumiu_decide_e_sem_responsavel_qualquer_um_decide(adm):
    adm.semear_disputa()
    r = adm.cliente.post(f"{DISP}/decisao", json=DECISAO_OK, headers=cab("t-mediador"))
    assert r.status_code == 200  # ninguém assumiu: segue como antes


def test_assumir_disputa_exige_motivo_permissao_e_disputa(adm):
    adm.semear_disputa()
    corpo = {"motivo": "Vou analisar o caso"}
    assert (
        adm.cliente.post(f"{DISP}/assumir", json={}, headers=cab("t-mediador")).status_code == 422
    )
    assert (
        adm.cliente.post(f"{DISP}/assumir", json=corpo, headers=cab("t-atendente_n2")).status_code
        == 403
    )
    assert (
        adm.cliente.post(
            f"{BASE}/disputas/xx/assumir", json=corpo, headers=cab("t-mediador")
        ).status_code
        == 404
    )
