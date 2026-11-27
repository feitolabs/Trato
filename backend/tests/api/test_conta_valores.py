"""BE-CONTA-VALORES: a conta não é excluída com dinheiro parado (Termos 4.8 e 20.7) e os
Tratinhos de quem o Trato encerrou sem falta ficam guardados por 90 dias (13.10 e I.11).
Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import timedelta

import pytest
from conftest import CLIENTE, PROFISSIONAL
from test_cliente_bloqueado_pedido import bloquear
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.medidas import reverter
from trato.api.moedas import CARTEIRA_CLIENTE, LancamentoMoeda
from trato.lgpd import registrar_rotas
from trato.lgpd.servico import ErroLgpd


class SemAuditoria:
    def auditar(self, *_, **__) -> None:
        pass


def lgpd(f):
    registrar_rotas(f.http.app, SemAuditoria())
    return f.http.app.state.lgpd_fabrica(f.http.app)


def dinheiro(pendencias: list[str]) -> bool:
    return any("retido ou a liberar" in p for p in pendencias)


@pytest.mark.parametrize("usuario", [CLIENTE, PROFISSIONAL])
def test_valor_retido_ou_a_liberar_segura_a_exclusao(fluxo, usuario):
    s = lgpd(fluxo)
    assert s.pedir_exclusao(usuario, fluxo.ctx.agora())["pendencias"] == []
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)  # concluído, mas o valor ainda está a liberar
    passo = s.pedir_exclusao(usuario, fluxo.ctx.agora())
    assert dinheiro(passo["pendencias"]), passo["pendencias"]
    with pytest.raises(ErroLgpd) as erro:
        s.confirmar_exclusao(usuario, passo["token_confirmacao"], fluxo.ctx.agora())
    assert erro.value.status == 409


def test_pedido_pago_segura_e_reembolso_enviado_libera(fluxo):
    s = lgpd(fluxo)
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    assert dinheiro(s.pedir_exclusao(CLIENTE, fluxo.ctx.agora())["pendencias"])
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti."})
    assert r.status_code == 200, r.text
    assert s.pedir_exclusao(CLIENTE, fluxo.ctx.agora())["pendencias"] == []
    ordem = fluxo.servico.ordens.do_pedido(pid)[0]
    fluxo.servico.ordens.salvar(replace(ordem, estado="pendente"))
    (aviso,) = s.pedir_exclusao(CLIENTE, fluxo.ctx.agora())["pendencias"]
    assert "reembolso" in aviso


def agendar(f, s):
    passo = s.pedir_exclusao(CLIENTE, f.ctx.agora())
    s.confirmar_exclusao(CLIENTE, passo["token_confirmacao"], f.ctx.agora())


def creditar(f, quantidade=120):
    assert f.ctx.moedas.lancar(
        LancamentoMoeda(
            usuario_id=CLIENTE.id,
            tipo="bonus_avaliacao",
            quantidade=quantidade,
            chave_idempotencia="credito-guarda",
            criada_em=f.ctx.agora(),
            carteira=CARTEIRA_CLIENTE,
        )
    )


def saldo(f) -> int:
    return f.ctx.moedas.saldo(CLIENTE.id, f.ctx.agora(), CARTEIRA_CLIENTE)


def processar(f, s, dias=8):
    f.amb.relogio.avancar(days=dias)
    return s.processar_vencidas(f.ctx.agora())


def test_encerrada_pelo_trato_sem_falta_guarda_os_tratinhos(fluxo):
    s = lgpd(fluxo)
    creditar(fluxo)
    agendar(fluxo, s)
    medida = bloquear(fluxo, "encerramento")
    visto = s.situacao_exclusao(CLIENTE, fluxo.ctx.agora())
    assert visto["tratinhos_a_perder"] == 0
    assert visto["tratinhos_guardados_ate"] == (medida.inicio_em + timedelta(days=90)).isoformat()
    fluxo.amb.relogio.avancar(days=8)
    agora = fluxo.ctx.agora()
    with ThreadPoolExecutor(4) as grupo:  # a rotina repetida ao mesmo tempo não zera nada
        list(grupo.map(lambda _: s.processar_vencidas(agora), range(4)))
    assert saldo(fluxo) == 120


@pytest.mark.parametrize("caso", ["voluntaria", "revertida", "fora_do_prazo"])
def test_sem_guarda_a_exclusao_voluntaria_zera_como_antes(fluxo, caso):
    s = lgpd(fluxo)
    creditar(fluxo)
    agendar(fluxo, s)
    if caso != "voluntaria":
        medida = bloquear(fluxo, "encerramento")
        if caso == "revertida":
            assert reverter(fluxo.ctx, medida, "eq-mediador")
    processar(fluxo, s, 91 if caso == "fora_do_prazo" else 8)
    assert saldo(fluxo) == 0
    assert s.situacao_exclusao(CLIENTE, fluxo.ctx.agora()).get("tratinhos_guardados_ate") is None


@pytest.mark.parametrize("marca", ["infracao_grave", "motivo_fraude"])
def test_encerramento_por_falta_grave_nao_guarda(fluxo, marca):
    s = lgpd(fluxo)
    creditar(fluxo)
    agendar(fluxo, s)
    medida = bloquear(fluxo, "encerramento")
    assert fluxo.ctx.medidas.mudar(medida.id, {marca: True})
    processar(fluxo, s)
    assert saldo(fluxo) == 0


def test_pedido_de_exclusao_encerrado_nao_muda(fluxo):
    s = lgpd(fluxo)
    agendar(fluxo, s)
    antigo = s._r.exclusoes.ativo_do_usuario(CLIENTE.id)
    processar(fluxo, s)
    assert s._r.exclusoes.salvar(replace(antigo, status="cancelada")) is False
    with pytest.raises(ErroLgpd) as erro:
        s.cancelar_exclusao(CLIENTE)
    assert erro.value.status == 404
