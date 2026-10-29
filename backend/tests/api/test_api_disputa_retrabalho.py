from datetime import timedelta

from conftest import AGORA, cab

from trato.pedidos.estados import Estado

DISPUTA = {"motivo": "mal_feito", "descricao": "Parede manchada"}


def abrir(amb, quem="t-cliente", corpo=None):
    return amb.cliente.post("/v1/pedidos/ped-1/disputa", json=corpo or DISPUTA, headers=cab(quem))


def test_cliente_abre_disputa_com_valor_do_ledger(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000)

    r = abrir(amb)

    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["estado"] == "aberta"
    assert corpo["valor_congelado_centavos"] == 100_000
    assert corpo["resposta_ate"].startswith("2026-10-31T12:00")  # 48 h da configuração
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.EM_DISPUTA
    assert amb.cliente.get("/v1/pedidos/ped-1/disputa", headers=cab("t-prof")).status_code == 200


def test_valor_congelado_e_retido_mais_a_liberar_sem_a_taxa(amb):
    # Dúvida de regra registrada no relatório: a taxa já repartida não entra no congelado.
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000, taxa=7_500)

    assert abrir(amb).json()["valor_congelado_centavos"] == 92_500


def test_disputa_sem_dinheiro_retido_da_409(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)

    r = abrir(amb)

    assert r.status_code == 409
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.EM_CONFIRMACAO


def test_profissional_nao_abre_disputa(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro()

    assert abrir(amb, "t-prof").status_code == 403


def test_disputa_em_estado_invalido_da_409(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.semear_dinheiro()

    assert abrir(amb).status_code == 409


def test_disputa_sem_descricao_da_422(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro()

    assert abrir(amb, corpo={"motivo": "mal_feito", "descricao": " "}).status_code == 422
    assert abrir(amb, corpo={"motivo": "inventado", "descricao": "x"}).status_code == 422


def test_ver_disputa_inexistente_da_404(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)

    assert amb.cliente.get("/v1/pedidos/ped-1/disputa", headers=cab("t-cliente")).status_code == 404


def test_profissional_responde_no_prazo(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro()
    abrir(amb)
    amb.relogio.avancar(hours=10)

    r = amb.cliente.post("/v1/pedidos/ped-1/disputa/resposta", headers=cab("t-prof"))

    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "em_analise"
    assert r.json()["respondida_em"] is not None


def test_resposta_fora_do_prazo_da_409(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro()
    abrir(amb)
    amb.relogio.avancar(hours=49)

    r = amb.cliente.post("/v1/pedidos/ped-1/disputa/resposta", headers=cab("t-prof"))

    assert r.status_code == 409


def test_quem_nao_e_o_profissional_nao_responde(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro()
    abrir(amb)
    url = "/v1/pedidos/ped-1/disputa/resposta"

    assert amb.cliente.post(url, headers=cab("t-cliente")).status_code == 403
    assert amb.cliente.post(url, headers=cab("t-outro-prof")).status_code == 404
    assert amb.cliente.post(url).status_code == 401


def test_responder_duas_vezes_da_409(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro()
    abrir(amb)
    url = "/v1/pedidos/ped-1/disputa/resposta"
    assert amb.cliente.post(url, headers=cab("t-prof")).status_code == 200

    assert amb.cliente.post(url, headers=cab("t-prof")).status_code == 409


# --- retrabalho -------------------------------------------------------------------------


def retrabalho(amb, quem="t-cliente", corpo=None):
    corpo = corpo or {"descricao": "Mancha voltou"}
    return amb.cliente.post("/v1/pedidos/ped-1/retrabalho", json=corpo, headers=cab(quem))


def test_cliente_pede_retrabalho_dentro_da_garantia(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - timedelta(days=10))

    r = retrabalho(amb)

    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["estado"] == "aberto"
    assert corpo["atender_ate"].startswith("2026-11-05T12:00")  # 7 dias da configuração
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.RETRABALHO
    assert len(amb.contexto.garantias.retrabalhos("ped-1")) == 1


def test_retrabalho_fora_da_garantia_da_409(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - timedelta(days=31))

    r = retrabalho(amb)

    assert r.status_code == 409
    assert "garantia" in r.json()["detail"]
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.CONCLUIDO


def test_retrabalho_antes_de_concluir_da_409(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)

    assert retrabalho(amb).status_code == 409


def test_profissional_nao_pede_retrabalho(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)

    assert retrabalho(amb, "t-prof").status_code == 403


def test_retrabalho_sem_descricao_da_422(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)

    assert retrabalho(amb, corpo={"descricao": "  "}).status_code == 422


def test_retrabalho_duas_vezes_da_409(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    assert retrabalho(amb).status_code == 201

    assert retrabalho(amb).status_code == 409
