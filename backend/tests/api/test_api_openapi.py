from trato.main import app


def test_openapi_lista_as_rotas_v1():
    caminhos = app.openapi()["paths"]

    for rota in (
        "/v1/pedidos",
        "/v1/pedidos/{pedido_id}/acoes/{acao}",
        "/v1/pedidos/{pedido_id}/disputa",
        "/v1/pedidos/{pedido_id}/disputa/resposta",
        "/v1/pedidos/{pedido_id}/retrabalho",
        "/v1/pedidos/{pedido_id}/saldo",
        "/v1/extrato",
        "/v1/webhooks/stripe",
        "/saude",
    ):
        assert rota in caminhos


def test_app_principal_sem_adaptadores_responde_503():
    from fastapi.testclient import TestClient

    r = TestClient(app).post("/v1/pedidos", headers={"Authorization": "Bearer x"})

    assert r.status_code == 503
