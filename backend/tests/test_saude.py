from fastapi.testclient import TestClient

from trato.config import Config
from trato.main import app

cliente = TestClient(app)


def test_saude_responde_ok():
    resposta = cliente.get("/saude")

    assert resposta.status_code == 200
    corpo = resposta.json()
    assert corpo["status"] == "ok"
    assert corpo["app"] == "Trato"


def test_saude_nao_expoe_segredos():
    corpo = cliente.get("/saude").text.lower()

    for palavra in ("key", "secret", "senha", "password"):
        assert palavra not in corpo


def test_config_le_variaveis_de_ambiente(monkeypatch):
    monkeypatch.setenv("TRATO_AMBIENTE", "teste")
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_valor_falso")  # verificar: ignorar

    config = Config(_env_file=None)

    assert config.trato_ambiente == "teste"
    assert config.stripe_em_modo_teste is True
