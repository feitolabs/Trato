"""BE-TRATINHOS-ADMIN (Termos I.3, 12.10, 13.9 e I.10): consulta, concessão e cancelamento por
fraude de Tratinhos no painel administrativo."""

# ruff: noqa: F811

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

from admin_ambiente import AGORA, CLIENTE, PROFISSIONAL, adm, cab  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.admin.rotas_moedas import ACAO_CANCELAR_FRAUDE, ACAO_CONCEDER
from trato.api.moedas import (
    CARTEIRA_CLIENTE,
    CARTEIRA_PROFISSIONAL,
    TIPO_BONUS_CLIENTE,
    TIPO_BONUS_PROFISSIONAL,
    PendenteMoeda,
)

BASE = "/v1/admin/moedas/usuarios"


def _auditorias(adm, acao: str):
    itens, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao=acao), 50, 0)
    return itens


def _headers(token: str) -> dict[str, str]:
    return cab(token)


def test_permissao_moedas_configurar_exigida_nas_tres_rotas(adm):
    for token in ("t-cliente", "t-prof", "t-mediador"):
        assert adm.cliente.get(f"{BASE}/{CLIENTE.id}", headers=_headers(token)).status_code == 403
        assert (
            adm.cliente.post(
                f"{BASE}/{CLIENTE.id}/conceder",
                json={"carteira": "cliente", "quantidade": 50, "motivo": "Compensação de teste."},
                headers=_headers(token),
            ).status_code
            == 403
        )
        assert (
            adm.cliente.post(
                f"{BASE}/{CLIENTE.id}/cancelar-fraude",
                json={"carteira": "cliente", "quantidade": 10, "motivo": "Fraude comprovada."},
                headers=_headers(token),
            ).status_code
            == 403
        )


def test_conceder_consultar_idempotencia_e_auditoria(adm):
    body = {
        "carteira": CARTEIRA_CLIENTE,
        "quantidade": 120,
        "motivo": "Compensação por falha técnica no agendamento.",
        "chave_idempotencia": "comp-001",
        "referencia_id": "chamado-42",
    }
    r1 = adm.cliente.post(f"{BASE}/{CLIENTE.id}/conceder", json=body, headers=_headers("t-administrador"))
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert (d1["quantidade"], d1["saldo_atual"], d1["idempotente"]) == (120, 120, False)
    assert d1["expira_em"] == (AGORA + timedelta(days=90)).isoformat().replace("+00:00", "Z")

    # Repetição com mesma chave é idempotente: não dobra o saldo nem grava nova auditoria
    r2 = adm.cliente.post(f"{BASE}/{CLIENTE.id}/conceder", json=body, headers=_headers("t-administrador"))
    assert r2.status_code == 200, r2.text
    d2 = r2.json()
    assert (d2["saldo_atual"], d2["idempotente"]) == (120, True)

    # Concessão na carteira profissional com validade personalizada
    r3 = adm.cliente.post(
        f"{BASE}/{PROFISSIONAL.id}/conceder",
        json={
            "carteira": CARTEIRA_PROFISSIONAL,
            "quantidade": 80,
            "validade_dias": 30,
            "motivo": "Compensação de exclusividade cancelada.",
        },
        headers=_headers("t-administrador"),
    )
    assert r3.status_code == 200, r3.text
    assert r3.json()["saldo_atual"] == 80
    assert r3.json()["expira_em"] == (AGORA + timedelta(days=30)).isoformat().replace("+00:00", "Z")

    # Consulta retorna saldos, pendentes e extrato
    adm.contexto.moedas.criar_pendente(
        PendenteMoeda(
            usuario_id=CLIENTE.id,
            pedido_id="ped-99",
            quantidade=50,
            liberar_em=AGORA + timedelta(days=7),
            chave_idempotencia="avaliacao:ped-99",
            criada_em=AGORA,
            tipo_lancamento=TIPO_BONUS_CLIENTE,
        )
    )
    consulta = adm.cliente.get(f"{BASE}/{CLIENTE.id}", headers=_headers("t-administrador"))
    assert consulta.status_code == 200, consulta.text
    c = consulta.json()
    assert c["saldo_cliente"] == 120 and c["saldo_profissional"] == 0
    assert len(c["pendentes_cliente"]) == 1 and c["pendentes_cliente"][0]["quantidade"] == 50
    assert len(c["extrato_cliente"]) == 1 and c["extrato_cliente"][0]["tipo"] == "ajuste"
    assert c["extrato_cliente"][0]["referencia_id"] == "chamado-42"

    # Auditoria: exatamente 2 concessões (1 cliente + 1 profissional; repetição não duplicou)
    entradas = _auditorias(adm, ACAO_CONCEDER)
    assert len(entradas) == 2
    assert {e.entidade_id for e in entradas} == {CLIENTE.id, PROFISSIONAL.id}
    assert any(e.depois["quantidade"] == 120 for e in entradas)


def test_cancelar_fraude_valida_saldo_cancela_pendentes_e_idempotente(adm):
    # Sem ação (quantidade=0 e cancelar_pendentes=False) -> 422
    assert (
        adm.cliente.post(
            f"{BASE}/{CLIENTE.id}/cancelar-fraude",
            json={"carteira": "cliente", "quantidade": 0, "motivo": "Fraude comprovada no pedido."},
            headers=_headers("t-administrador"),
        ).status_code
        == 422
    )

    # Credita 100 moedas e 2 pendentes (1 cliente, 1 profissional)
    adm.cliente.post(
        f"{BASE}/{CLIENTE.id}/conceder",
        json={"carteira": "cliente", "quantidade": 100, "motivo": "Crédito inicial para teste."},
        headers=_headers("t-administrador"),
    )
    adm.contexto.moedas.criar_pendente(
        PendenteMoeda(
            usuario_id=CLIENTE.id,
            pedido_id="ped-f1",
            quantidade=50,
            liberar_em=AGORA + timedelta(days=7),
            chave_idempotencia="avaliacao:ped-f1",
            criada_em=AGORA,
            tipo_lancamento=TIPO_BONUS_CLIENTE,
        )
    )
    adm.contexto.moedas.criar_pendente(
        PendenteMoeda(
            usuario_id=CLIENTE.id,
            pedido_id="ped-f2",
            quantidade=30,
            liberar_em=AGORA + timedelta(days=7),
            chave_idempotencia="avaliacao-prof:ped-f2",
            criada_em=AGORA,
            tipo_lancamento=TIPO_BONUS_PROFISSIONAL,
        )
    )

    # Pedir mais que o saldo -> 409 sem debitar nem cancelar pendentes
    excesso = adm.cliente.post(
        f"{BASE}/{CLIENTE.id}/cancelar-fraude",
        json={
            "carteira": "cliente",
            "quantidade": 101,
            "cancelar_pendentes": True,
            "motivo": "Tentativa acima do saldo disponível.",
        },
        headers=_headers("t-administrador"),
    )
    assert excesso.status_code == 409, excesso.text
    assert adm.contexto.moedas.saldo(CLIENTE.id, AGORA, CARTEIRA_CLIENTE) == 100
    assert len(adm.contexto.moedas.pendentes_do_usuario(CLIENTE.id, TIPO_BONUS_CLIENTE)) == 1

    # Cancela 60 + pendentes da carteira cliente
    corpo = {
        "carteira": "cliente",
        "quantidade": 60,
        "cancelar_pendentes": True,
        "motivo": "Fraude confirmada em avaliações combinadas.",
        "chave_idempotencia": "fraude-001",
        "referencia_id": "inc-77",
    }
    r1 = adm.cliente.post(
        f"{BASE}/{CLIENTE.id}/cancelar-fraude", json=corpo, headers=_headers("t-administrador")
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert (d1["quantidade_debitada"], d1["pendentes_cancelados"], d1["saldo_atual"]) == (60, 1, 40)
    assert d1["idempotente"] is False
    # Pendente da outra carteira não foi tocado
    assert len(adm.contexto.moedas.pendentes_do_usuario(CLIENTE.id, TIPO_BONUS_PROFISSIONAL)) == 1

    # Repetição idempotente: não debita novamente nem devolve 409
    r2 = adm.cliente.post(
        f"{BASE}/{CLIENTE.id}/cancelar-fraude", json=corpo, headers=_headers("t-administrador")
    )
    assert r2.status_code == 200, r2.text
    assert (r2.json()["idempotente"], r2.json()["saldo_atual"]) == (True, 40)

    # Auditoria registrada uma única vez
    entradas = _auditorias(adm, ACAO_CANCELAR_FRAUDE)
    assert len(entradas) == 1
    assert entradas[0].depois["quantidade_debitada"] == 60
    assert entradas[0].depois["pendentes_cancelados"] == 1


def test_cancelar_fraude_concorrente_nao_negativa_saldo(adm):
    adm.cliente.post(
        f"{BASE}/{CLIENTE.id}/conceder",
        json={"carteira": "cliente", "quantidade": 100, "motivo": "Saldo inicial concorrência."},
        headers=_headers("t-administrador"),
    )

    def chamar(idx: int) -> int:
        return adm.cliente.post(
            f"{BASE}/{CLIENTE.id}/cancelar-fraude",
            json={
                "carteira": "cliente",
                "quantidade": 100,
                "motivo": "Cancelamento simultâneo por fraude.",
                "chave_idempotencia": f"corr-{idx}",
            },
            headers=_headers("t-administrador"),
        ).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        codigos = sorted(pool.map(chamar, (1, 2)))
    assert codigos == [200, 409]
    assert adm.contexto.moedas.saldo(CLIENTE.id, AGORA, CARTEIRA_CLIENTE) == 0
