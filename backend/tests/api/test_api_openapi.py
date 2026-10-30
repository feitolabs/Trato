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


TEXTOS_PROIBIDOS = (
    "garantia total",
    "escrow",
    "profissional seguro",
    "reembolso automático",
    "reembolso automatico",
    "menor taxa do mercado",
    "24/7",
)


def test_api_nao_promete_o_que_a_d13_proibe():
    import json

    texto = json.dumps(app.openapi(), ensure_ascii=False).lower()

    for proibido in TEXTOS_PROIBIDOS:
        assert proibido not in texto
    assert "suporte e análise de problemas" in texto


def test_modulos_nao_trazem_textos_proibidos():
    from pathlib import Path

    import trato

    raiz = Path(trato.__file__).parent
    for arquivo in raiz.rglob("*.py"):
        conteudo = arquivo.read_text(encoding="utf-8").lower()
        for proibido in TEXTOS_PROIBIDOS:
            assert proibido not in conteudo, f"{proibido!r} em {arquivo.name}"
