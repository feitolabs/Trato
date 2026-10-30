"""Configuração versionada: rascunho, aprovação dupla, publicar e reverter (memória)."""

from datetime import timedelta

from admin_ambiente import AGORA, BASE_FAIXAS, BASE_PARAMETROS, adm, cab  # noqa: F401

BASE = "/v1/admin/config"
MOTIVO = {"motivo": "Conferi a proposta e os números"}


def parametros(**trocas):
    itens = {p.chave: p.valor for p in BASE_PARAMETROS} | trocas
    return [{"chave": k, "valor": v} for k, v in itens.items()]


FAIXAS = [
    {"de_centavos": f.de_centavos, "ate_centavos": f.ate_centavos, "taxa_bps": f.taxa_bps}
    for f in BASE_FAIXAS
]


def criar(adm, quem="t-financeiro", **corpo):
    base = {
        "motivo": "Versão inicial",
        "parametros": parametros(),
        "faixas": FAIXAS,
        "partir_da_vigente": False,
    }
    return adm.cliente.post(f"{BASE}/versoes", json=base | corpo, headers=cab(quem))


def passo(adm, versao_id, acao, quem, corpo=None):
    return adm.cliente.post(
        f"{BASE}/versoes/{versao_id}/{acao}", json=corpo or MOTIVO, headers=cab(quem)
    )


def subir_ate_vigente(adm, **corpo):
    """financeiro propõe, administrador (outra pessoa) aprova e publica."""
    versao = criar(adm, **corpo).json()
    assert passo(adm, versao["id"], "enviar", "t-financeiro").status_code == 200
    assert passo(adm, versao["id"], "aprovar", "t-administrador").status_code == 200
    r = passo(adm, versao["id"], "publicar", "t-administrador")
    assert r.status_code == 200, r.text
    return r.json()


def test_ciclo_completo_proposta_aprovacao_publicacao(adm):
    assert adm.cliente.get(f"{BASE}/vigente", headers=cab("t-financeiro")).status_code == 404

    r = criar(adm)
    assert (
        r.status_code == 201
        and r.json()["status"] == "rascunho"
        and r.json()["criada_por"] == "eq-financeiro"
    )
    vid = r.json()["id"]
    assert passo(adm, vid, "enviar", "t-financeiro").json()["status"] == "aguardando_aprovacao"
    aprovada = passo(adm, vid, "aprovar", "t-administrador").json()
    assert aprovada["status"] == "aprovada" and aprovada["aprovada_por"] == "eq-administrador"
    assert aprovada["vigente_desde"] is not None
    publicada = passo(adm, vid, "publicar", "t-administrador").json()
    assert publicada["status"] == "vigente"

    vigente = adm.cliente.get(f"{BASE}/vigente", headers=cab("t-juridico")).json()
    assert vigente["id"] == vid and len(vigente["parametros"]) == 4 and len(vigente["faixas"]) == 2
    acoes = [
        i["acao"]
        for i in adm.cliente.get(
            "/v1/admin/auditoria?acao=config.", headers=cab("t-seguranca")
        ).json()["itens"]
    ]
    assert acoes == [
        "config.publicada", "config.aprovada", "config.enviada_para_aprovacao", "config.rascunho_criado"
    ]  # fmt: skip


def test_quem_propoe_nao_aprova(adm):
    # O administrador também pode propor, mas então precisa de OUTRO administrador para aprovar.
    vid = criar(adm, quem="t-administrador").json()["id"]
    passo(adm, vid, "enviar", "t-administrador")

    r = passo(adm, vid, "aprovar", "t-administrador")

    assert r.status_code == 403
    assert adm.admin.config.versao(vid).status == "aguardando_aprovacao"
    assert passo(adm, vid, "aprovar", "t-administrador2").status_code == 200


def test_proponente_sem_papel_de_aprovar_recebe_403(adm):
    vid = criar(adm).json()["id"]
    passo(adm, vid, "enviar", "t-financeiro")
    assert passo(adm, vid, "aprovar", "t-financeiro").status_code == 403
    assert passo(adm, vid, "publicar", "t-financeiro").status_code == 403


def test_nao_publica_sem_aprovar_nem_aprova_sem_enviar(adm):
    vid = criar(adm).json()["id"]
    assert passo(adm, vid, "aprovar", "t-administrador").status_code == 409
    assert passo(adm, vid, "publicar", "t-administrador").status_code == 409
    passo(adm, vid, "enviar", "t-financeiro")
    assert passo(adm, vid, "publicar", "t-administrador").status_code == 409


def test_nova_versao_substitui_a_vigente_e_o_historico_fica(adm):
    primeira = subir_ate_vigente(adm)
    segunda = subir_ate_vigente(
        adm, motivo="Resposta mais rápida", partir_da_vigente=True,
        parametros=[{"chave": "prazo_resposta_disputa_horas", "valor": 24}], faixas=[],
    )  # fmt: skip

    vigente = adm.cliente.get(f"{BASE}/vigente", headers=cab("t-financeiro")).json()
    valores = {p["chave"]: p["valor"] for p in vigente["parametros"]}
    assert vigente["id"] == segunda["id"] and valores["prazo_resposta_disputa_horas"] == 24
    assert valores["adiantamento_bps"] == 3000 and len(vigente["faixas"]) == 2  # herdou da vigente
    historico = adm.cliente.get(f"{BASE}/versoes", headers=cab("t-financeiro")).json()
    assert [(v["numero"], v["status"]) for v in historico] == [(2, "vigente"), (1, "substituida")]
    antiga = adm.cliente.get(f"{BASE}/versoes/{primeira['id']}", headers=cab("t-financeiro")).json()
    assert {p["chave"]: p["valor"] for p in antiga["parametros"]}[
        "prazo_resposta_disputa_horas"
    ] == 48


def test_reverter_cria_nova_versao_que_tambem_precisa_de_aprovacao(adm):
    primeira = subir_ate_vigente(adm)
    segunda = subir_ate_vigente(
        adm,
        partir_da_vigente=True,
        parametros=[{"chave": "prazo_resposta_disputa_horas", "valor": 24}],
        faixas=[],
    )

    r = passo(
        adm, primeira["id"], "reverter", "t-financeiro", {"motivo": "Prazo menor gerou reclamações"}
    )

    assert r.status_code == 201
    nova = r.json()
    assert nova["status"] == "aguardando_aprovacao" and nova["revertida_de"] == primeira["id"]
    assert nova["numero"] == 3 and nova["id"] not in (primeira["id"], segunda["id"])
    assert (
        adm.cliente.get(f"{BASE}/vigente", headers=cab("t-financeiro")).json()["id"]
        == segunda["id"]
    )
    assert passo(adm, nova["id"], "aprovar", "t-financeiro").status_code == 403
    assert passo(adm, nova["id"], "aprovar", "t-administrador").status_code == 200
    assert passo(adm, nova["id"], "publicar", "t-administrador").status_code == 200
    vigente = adm.cliente.get(f"{BASE}/vigente", headers=cab("t-financeiro")).json()
    assert {p["chave"]: p["valor"] for p in vigente["parametros"]}[
        "prazo_resposta_disputa_horas"
    ] == 48
    status = {
        v["numero"]: v["status"]
        for v in adm.cliente.get(f"{BASE}/versoes", headers=cab("t-financeiro")).json()
    }
    assert status == {1: "substituida", 2: "revertida", 3: "vigente"}


def test_nao_reverte_para_versao_que_nunca_valeu(adm):
    vid = criar(adm).json()["id"]
    assert passo(adm, vid, "reverter", "t-financeiro").status_code == 409


def test_versao_publicada_e_imutavel(adm):
    vigente = subir_ate_vigente(adm)
    descartar = adm.cliente.request(
        "DELETE", f"{BASE}/versoes/{vigente['id']}", json=MOTIVO, headers=cab("t-financeiro")
    )
    assert descartar.status_code == 409
    assert passo(adm, vigente["id"], "enviar", "t-financeiro").status_code == 409
    # Não há rota para editar parâmetros de uma versão existente.
    assert (
        adm.cliente.put(
            f"{BASE}/versoes/{vigente['id']}", json={}, headers=cab("t-financeiro")
        ).status_code
        == 405
    )
    assert (
        len(
            adm.cliente.get(f"{BASE}/versoes/{vigente['id']}", headers=cab("t-financeiro")).json()[
                "parametros"
            ]
        )
        == 4
    )


def test_rascunho_pode_ser_descartado(adm):
    vid = criar(adm).json()["id"]
    r = adm.cliente.request(
        "DELETE", f"{BASE}/versoes/{vid}", json=MOTIVO, headers=cab("t-financeiro")
    )
    assert r.status_code == 204
    assert adm.cliente.get(f"{BASE}/versoes/{vid}", headers=cab("t-financeiro")).status_code == 404


def test_valores_fora_dos_limites_do_catalogo_sao_recusados(adm):
    assert criar(adm, parametros=parametros(prazo_resposta_disputa_horas=9999)).status_code == 422
    assert criar(adm, parametros=parametros(prazo_resposta_disputa_horas=0)).status_code == 422
    assert criar(adm, parametros=[{"chave": "nao_existe", "valor": 1}]).status_code == 422
    escopo = [
        {"chave": "adiantamento_bps", "valor": 100, "escopo_tipo": "cidade", "escopo_id": "x"}
    ]
    assert criar(adm, parametros=escopo).status_code == 422  # escopo não permitido para a chave
    mal = [{"chave": "validade_pedido_horas", "valor": 10, "escopo_tipo": "cidade"}]
    assert criar(adm, parametros=mal).status_code == 422  # cidade sem escopo_id
    repetido = parametros() + [{"chave": "adiantamento_bps", "valor": 10}]
    assert criar(adm, parametros=repetido).status_code == 422
    assert adm.admin.config.versoes() == ()


def test_faixas_com_buraco_sobreposicao_ou_sem_fim_nao_passam(adm):
    buraco = [
        {"de_centavos": 0, "ate_centavos": 100, "taxa_bps": 750},
        {"de_centavos": 200, "ate_centavos": None, "taxa_bps": 600},
    ]
    sobreposta = [
        {"de_centavos": 0, "ate_centavos": 200, "taxa_bps": 750},
        {"de_centavos": 100, "ate_centavos": None, "taxa_bps": 600},
    ]
    assert criar(adm, faixas=sobreposta).status_code == 422
    vid = criar(adm, faixas=buraco).json()["id"]  # rascunho aceita incompleto...
    assert passo(adm, vid, "enviar", "t-financeiro").status_code == 422  # ...mas não sai dele
    sem_fim = [{"de_centavos": 0, "ate_centavos": 100_000, "taxa_bps": 750}]
    vid = criar(adm, faixas=sem_fim).json()["id"]
    assert passo(adm, vid, "enviar", "t-financeiro").status_code == 422
    fora = [{"de_centavos": 0, "ate_centavos": None, "taxa_bps": 10_001}]
    assert criar(adm, faixas=fora).status_code == 422


def test_versao_sem_o_que_o_backend_exige_nao_vira_vigente(adm):
    incompleta = [p for p in parametros() if p["chave"] != "prazo_congelar_disputa_horas"]
    vid = criar(adm, parametros=incompleta).json()["id"]
    r = passo(adm, vid, "enviar", "t-financeiro")
    assert r.status_code == 422 and "prazo_congelar_disputa_horas" in r.text
    sem_faixas = criar(adm, faixas=[]).json()["id"]
    assert passo(adm, sem_faixas, "enviar", "t-financeiro").status_code == 422


def test_vigencia_agendada_so_publica_quando_chega_a_hora(adm):
    futuro = (AGORA + timedelta(days=2)).isoformat()
    vid = criar(adm, vigente_desde=futuro).json()["id"]
    passo(adm, vid, "enviar", "t-financeiro")
    passo(adm, vid, "aprovar", "t-administrador")

    assert passo(adm, vid, "publicar", "t-administrador").status_code == 409

    adm.relogio.avancar(days=3)
    assert passo(adm, vid, "publicar", "t-administrador").status_code == 200


def test_definicoes_e_corpo_estranho(adm):
    itens = adm.cliente.get(f"{BASE}/definicoes", headers=cab("t-juridico")).json()
    assert "adiantamento_bps" in [d["chave"] for d in itens]
    r = adm.cliente.post(
        f"{BASE}/versoes", json={"motivo": "Testando", "intruso": 1}, headers=cab("t-financeiro")
    )
    assert r.status_code == 422
    assert criar(adm, motivo="x").status_code == 422  # motivo curto demais
