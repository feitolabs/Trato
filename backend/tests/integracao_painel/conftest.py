"""Backend de teste (o mesmo de `harness/subir-backend-teste.py`) + cliente HTTP que imita o painel."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import trato.api  # noqa: F401 - primeiro: o orquestrador e a API se importam em ciclo
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.memoria import AditivosEmMemoria, CobrancasEmMemoria
from trato.pagamentos.modelos import CobrancaLocal, ConfigPagamento, EstadoCobranca
from trato.pagamentos.orquestrador import ServicoPagamento
from trato.pagamentos.provedor import ProvedorFake

_SCRIPT = Path(__file__).resolve().parents[3] / "harness" / "subir-backend-teste.py"
_spec = importlib.util.spec_from_file_location("subir_backend_teste", _SCRIPT)
assert _spec and _spec.loader
amb = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = amb
_spec.loader.exec_module(amb)


class Painel:
    """Faz o que o `ApiAdminHttp` do painel faz: login em /auth/v1/token e Bearer em tudo."""

    def __init__(self, ambiente) -> None:
        self.ambiente = ambiente
        self.http = TestClient(ambiente.app)

    def entrar(self, papel: str) -> str:
        r = self.http.post(
            "/auth/v1/token", params={"grant_type": "password"},
            json={"email": amb.email_de(papel), "password": amb.SENHA_TESTE}, headers={"apikey": "anon-de-teste"},
        )  # fmt: skip
        assert r.status_code == 200, r.text
        return r.json()["access_token"]

    def chamar(self, papel: str | None, metodo: str, caminho: str, **kw):
        cab = {"Authorization": f"Bearer {self.entrar(papel)}"} if papel else {}
        return self.http.request(metodo, caminho, headers=cab, **kw)


def _ligar_pagamento(app) -> None:
    """A decisão de disputa pede o estorno ao provedor: liga o pagamento com o provedor falso e
    uma cobrança paga para cada pedido com dinheiro no ledger. O script do harness (fora de
    `backend/`) ainda não faz isto."""
    contexto = app.state.contexto
    servico = ServicoPagamento(
        ProvedorFake(), lambda: ConfigPagamento(10**9), CobrancasEmMemoria(), AditivosEmMemoria()
    )
    for pedido_id in {i.pedido_id for i in contexto.ledger.lancamentos()}:
        valor = contexto.ledger.saldos_pedido(pedido_id, None).cliente_pagou
        if valor <= 0:
            continue
        criada = servico.provedor.criar_cobranca(
            valor_centavos=valor,
            meio=MeioPagamento.PIX,
            chave_idempotencia=f"painel/{pedido_id}",
            metadados={"pedido_id": pedido_id},
        )
        servico.provedor.marcar_paga(criada.id)
        servico.cobrancas.salvar(
            CobrancaLocal(
                criada.id,
                pedido_id,
                valor,
                MeioPagamento.PIX,
                EstadoCobranca.PAGA,
                contexto.agora(),
            )
        )
    app.state.servico_pagamento = servico


@pytest.fixture
def ambiente():
    montado = amb.montar()
    _ligar_pagamento(montado.app)
    return montado


@pytest.fixture
def painel(ambiente) -> Painel:
    return Painel(ambiente)
