"""BE-CHECKOUT-SEM-CODIGO-57-FASE2 (em memória + ProvedorFake): decisão administrativa
(`liberar` ou `estornar`) com ledger imutável, idempotência, auditoria, alçada e bloqueios."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace

from conftest import AGORA, PROFISSIONAL
from test_checkin_checkout_sem_codigo import _foto, _loc
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.pedidos.estados import Estado as E

URL_FILA = "/v1/admin/checkout-sem-codigo"
MOTIVO = "Provas do pedido conferidas pelo analista."


def _ate_checkout_sem_codigo(fluxo, *, avancar_prazo: bool = True):
    fluxo.amb.relogio.agora = AGORA
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    r = fluxo.acao(
        pid,
        "fazer_check_out",
        "t-prof",
        {
            "foto_final": _foto(fluxo.amb, f"foto-{pid}"),
            "localizacao": _loc(),
            "sem_codigo": True,
            "justificativa": "Cliente saiu antes do encerramento.",
        },
    )
    assert r.status_code == 200, r.text
    casos = [c for c in fluxo.ctx.checkout_sem_codigo.em_aberto() if c.pedido_id == pid]
    assert len(casos) == 1
    caso = casos[0]
    if caso.contatado_em is None:
        r_c = fluxo.chamar(
            "POST",
            f"{URL_FILA}/{caso.id}/contato",
            "t-mediador",
            {"canal": "whatsapp", "motivo": "Contato realizado para iniciar prazo."},
        )
        assert r_c.status_code == 200, r_c.text
        caso = fluxo.ctx.checkout_sem_codigo.obter(caso.id)
    if avancar_prazo:
        fluxo.amb.relogio.avancar(days=10)
    return pid, caso


def test_decidir_liberar_idempotencia_auditoria_e_bloqueio_duplicado(fluxo):
    pid, caso = _ate_checkout_sem_codigo(fluxo)
    url = f"{URL_FILA}/{caso.id}/decisao"

    # Validação de motivo curto -> 422
    assert (
        fluxo.chamar(
            "POST",
            url,
            "t-mediador",
            {"decisao": "liberar", "motivo": "curto", "chave_idempotencia": "chave-lib-0001"},
        ).status_code
        == 422
    )

    r = fluxo.chamar(
        "POST",
        url,
        "t-mediador",
        {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": "chave-lib-0001"},
    )
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["decisao"] == "liberar"
    assert corpo["estado_pedido"] == "concluido"
    assert corpo["idempotente"] is False
    assert corpo["chave_idempotencia"] == "chave-lib-0001"
    assert fluxo.ctx.pedidos.obter(pid).estado is E.CONCLUIDO
    assert fluxo.ctx.garantias.obter_garantia(pid) is not None

    saldos = fluxo.ctx.ledger.saldos_pedido(pid, PROFISSIONAL.id)
    assert saldos.retido == 0 and saldos.a_liberar == 100_000
    assert len(fluxo.ctx.repasses.do_pedido(pid)) == 1
    assert fluxo.chamar("GET", URL_FILA, "t-mediador").json()["total"] == 0

    lancamentos_antes = len(fluxo.ctx.ledger.lancamentos(pid))
    auditoria_antes = [
        e
        for e in fluxo.amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)[0]
        if e.acao == "financeiro.checkout_sem_codigo_decidido"
    ]
    assert len(auditoria_antes) == 1

    # Idempotência: mesma chave + mesma decisão retorna 200 sem duplicar dinheiro nem auditoria
    r_idem = fluxo.chamar(
        "POST",
        url,
        "t-mediador",
        {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": "chave-lib-0001"},
    )
    assert r_idem.status_code == 200 and r_idem.json()["idempotente"] is True
    assert len(fluxo.ctx.ledger.lancamentos(pid)) == lancamentos_antes
    auditoria_depois = [
        e
        for e in fluxo.amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)[0]
        if e.acao == "financeiro.checkout_sem_codigo_decidido"
    ]
    assert len(auditoria_depois) == 1

    # Mesma chave com outra decisão -> 409; nova chave em caso já decidido -> 409
    assert (
        fluxo.chamar(
            "POST",
            url,
            "t-mediador",
            {"decisao": "estornar", "motivo": MOTIVO, "chave_idempotencia": "chave-lib-0001"},
        ).status_code
        == 409
    )
    assert (
        fluxo.chamar(
            "POST",
            url,
            "t-mediador",
            {"decisao": "estornar", "motivo": MOTIVO, "chave_idempotencia": "chave-lib-0002"},
        ).status_code
        == 409
    )


def test_decidir_estornar_devolve_ao_cliente_e_audita(fluxo):
    pid, caso = _ate_checkout_sem_codigo(fluxo)
    r = fluxo.chamar(
        "POST",
        f"{URL_FILA}/{caso.id}/decisao",
        "t-mediador",
        {"decisao": "estornar", "motivo": MOTIVO, "chave_idempotencia": "chave-est-0001"},
    )
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["decisao"] == "estornar"
    assert corpo["estado_pedido"] == "cancelado"
    assert fluxo.ctx.pedidos.obter(pid).estado is E.CANCELADO
    saldos = fluxo.ctx.ledger.saldos_pedido(pid, PROFISSIONAL.id)
    assert saldos.retido == 0 and saldos.a_liberar == 0
    assert fluxo.servico.ordens.do_pedido(pid)
    assert fluxo.chamar("GET", URL_FILA, "t-mediador").json()["total"] == 0


def test_bloqueios_resposta_disputa_permissao_alcada_e_fase2(fluxo):
    # 1. Sem permissão -> 403
    pid1, caso1 = _ate_checkout_sem_codigo(fluxo)
    for quem in ("t-n1", "t-cadastro", "t-financeiro", "t-cliente", "t-prof"):
        assert (
            fluxo.chamar(
                "POST",
                f"{URL_FILA}/{caso1.id}/decisao",
                quem,
                {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": f"ch-{quem}-1234"},
            ).status_code
            == 403
        ), quem

    # 2. Alçada insuficiente -> 403 sem mover dinheiro
    med_atual = fluxo.amb.admin.equipe.obter("eq-med")
    fluxo.amb.admin.equipe.salvar(replace(med_atual, alcada_centavos=50_000))
    r_alc = fluxo.chamar(
        "POST",
        f"{URL_FILA}/{caso1.id}/decisao",
        "t-mediador",
        {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": "chave-alcada-001"},
    )
    assert r_alc.status_code == 403
    assert fluxo.ctx.pedidos.obter(pid1).estado is E.EM_CONFIRMACAO
    fluxo.amb.admin.equipe.salvar(med_atual)

    # 3. Cliente já confirmou -> 409
    assert fluxo.acao(pid1, "confirmar_conclusao", "t-cliente").status_code == 200
    assert (
        fluxo.chamar(
            "POST",
            f"{URL_FILA}/{caso1.id}/decisao",
            "t-mediador",
            {"decisao": "estornar", "motivo": MOTIVO, "chave_idempotencia": "chave-pos-conf-1"},
        ).status_code
        == 409
    )

    # 4. Disputa aberta -> 409
    pid2, caso2 = _ate_checkout_sem_codigo(fluxo)
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/pedidos/{pid2}/disputa",
            "t-cliente",
            {"motivo": "mal_feito", "descricao": "O serviço não foi concluído."},
        ).status_code
        == 201
    )
    assert (
        fluxo.chamar(
            "POST",
            f"{URL_FILA}/{caso2.id}/decisao",
            "t-mediador",
            {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": "chave-pos-disp-1"},
        ).status_code
        == 409
    )

    # 5. Sem fase 2 no banco -> 503
    pid3, caso3 = _ate_checkout_sem_codigo(fluxo)
    fluxo.ctx.checkout_sem_codigo.fase2_disponivel = lambda: False
    assert (
        fluxo.chamar(
            "POST",
            f"{URL_FILA}/{caso3.id}/decisao",
            "t-mediador",
            {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": "chave-sem-f2-001"},
        ).status_code
        == 503
    )
    assert fluxo.ctx.pedidos.obter(pid3).estado is E.EM_CONFIRMACAO

def test_bloqueia_decisao_sem_contato_ou_antes_do_prazo(fluxo):
    fluxo.ctx.extras.pop("notificador", None)
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    assert (
        fluxo.acao(
            pid,
            "fazer_check_out",
            "t-prof",
            {
                "foto_final": _foto(fluxo.amb, f"foto-{pid}"),
                "localizacao": _loc(),
                "sem_codigo": True,
                "justificativa": "Cliente saiu antes do encerramento.",
            },
        ).status_code
        == 200
    )
    caso = [c for c in fluxo.ctx.checkout_sem_codigo.em_aberto() if c.pedido_id == pid][0]
    url = f"{URL_FILA}/{caso.id}/decisao"

    # Sem contato -> 409
    assert (
        fluxo.chamar(
            "POST",
            url,
            "t-mediador",
            {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": "ch-sem-cont-01"},
        ).status_code
        == 409
    )

    # Com contato, mas prazo ainda não venceu -> 409
    assert (
        fluxo.chamar(
            "POST",
            f"{URL_FILA}/{caso.id}/contato",
            "t-mediador",
            {"canal": "telefone", "motivo": "Contato telefônico registrado pelo analista."},
        ).status_code
        == 200
    )
    assert (
        fluxo.chamar(
            "POST",
            url,
            "t-mediador",
            {"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": "ch-no-prazo-01"},
        ).status_code
        == 409
    )
