# ruff: noqa: F811
"""BE-SEG-ALTOS: reproduções dos achados da Segurança sobre o commit 3af627a."""

from __future__ import annotations

import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import timedelta

import pytest
from casos_restauracao import CASOS
from conftest import AGORA, CLIENTE
from test_ausencia_cliente import ausente, chegar
from test_fluxo_pagamento_e2e import VALOR, _em_andamento, fluxo  # noqa: F401
from test_pessoa_diferente import agendado, incidentes, relatar
from test_trava_fraude import travar

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.ausencia_base import do_pedido
from trato.api.moedas import (
    LancamentoMoeda,
    MoedasEmMemoria,
    zerar_tratinhos_encerramento_voluntario,
)
from trato.api.moedas_saldo import vencido_sem_uso
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import EstadoAditivo, EstadoCobranca
from trato.pagamentos.provedor.base import TipoEvento
from trato.pedidos.estados import Acao, Estado
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

D = timedelta(days=1)


def aditivo_com_duas_cobrancas(f):
    pid = _em_andamento(f)
    pedido = f.ctx.pedidos.obter(pid)
    ad = f.servico.propor_aditivo(f.ctx, pedido, "Trocar o registro", 5_000)
    _, primeira = f.servico.aprovar_aditivo(f.ctx, pedido, ad.id, MeioPagamento.PIX)
    segunda = replace(primeira, id=primeira.id + "-2")
    f.servico.cobrancas.salvar(segunda)
    return pid, ad.id, primeira, segunda


def confirmar(f, cobranca_id):
    f.fake.marcar_paga(cobranca_id)
    return f.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id)


# --- A1 -------------------------------------------------------------------------------------


def test_a1_segunda_cobranca_de_aditivo_pago_volta(fluxo):
    pid, _, primeira, segunda = aditivo_com_duas_cobrancas(fluxo)
    fluxo.fake._cobrancas[segunda.id] = replace(fluxo.fake._cobrancas[primeira.id], id=segunda.id)
    assert confirmar(fluxo, primeira.id).status_code == 200
    assert confirmar(fluxo, segunda.id).status_code == 200
    assert fluxo.saldo(pid)["retido_centavos"] == VALOR + 5_000
    assert fluxo.servico.cobrancas.obter(segunda.id).status is EstadoCobranca.DEVOLVIDA


def test_a1_cobranca_de_aditivo_recusado_volta(fluxo):
    pid, aid, primeira, _ = aditivo_com_duas_cobrancas(fluxo)
    aditivo = fluxo.servico.aditivos.obter(aid)
    fluxo.servico.aditivos.salvar(replace(aditivo, estado=EstadoAditivo.RECUSADO))
    assert confirmar(fluxo, primeira.id).status_code == 200
    assert fluxo.saldo(pid)["retido_centavos"] == VALOR
    assert fluxo.servico.aditivos.obter(aid).estado is EstadoAditivo.RECUSADO


def test_a1_duas_aprovacoes_ao_mesmo_tempo_criam_uma_cobranca(fluxo, monkeypatch):
    pid = _em_andamento(fluxo)
    pedido = fluxo.ctx.pedidos.obter(pid)
    ad = fluxo.servico.propor_aditivo(fluxo.ctx, pedido, "Extra", 5_000)
    original = fluxo.servico.aditivos.obter
    juntos = threading.Barrier(2)

    def obter(aid):
        achado = original(aid)
        try:
            juntos.wait(timeout=0.5)  # as duas leem antes de qualquer uma gravar
        except threading.BrokenBarrierError:
            pass
        return achado

    monkeypatch.setattr(fluxo.servico.aditivos, "obter", obter)

    def aprovar(_):
        try:
            fluxo.servico.aprovar_aditivo(fluxo.ctx, pedido, ad.id, MeioPagamento.PIX)
            return True
        except Exception:  # noqa: BLE001
            return False

    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(aprovar, range(2))) == [False, True]


# --- A2 -------------------------------------------------------------------------------------


def expirar(f, pid):
    acao = AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"expira:{pid}", acao=Acao.EXPIRAR_PAGAMENTO
    )
    ExecutorContexto(f.ctx, None, f.servico.cobrancas).executar(
        acao, f.ctx.agora() + timedelta(days=30)
    )


def test_a2_contrato_que_nao_encerra_nao_reabre_o_pedido(fluxo, monkeypatch):
    pid = fluxo.aceitar()
    monkeypatch.setattr(fluxo.ctx.contratos, "pode_encerrar_por_pagamento_expirado",
                        lambda _: False, raising=False)  # fmt: skip
    monkeypatch.setattr(fluxo.ctx.contratos, "encerrar_por_pagamento_expirado", lambda _: False)
    with pytest.raises(Adiada):
        expirar(fluxo, pid)
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.ORCAMENTO_ACEITO


# --- A3 -------------------------------------------------------------------------------------


def test_a3_relato_sem_texto_cancela_e_sinaliza_repeticao_e_espera(fluxo):
    pid, _ = agendado(fluxo)
    assert relatar(fluxo, pid).json()["cancelado"] is True
    primeiro = incidentes(fluxo, pid)[0]
    from trato.api.pessoa_diferente import sinais_antifraude

    assert sinais_antifraude(fluxo.ctx, primeiro) == []
    outro, _ = agendado(fluxo)
    janela = fluxo.ctx.pedidos.obter(outro).janela
    fluxo.amb.relogio.agora = janela.inicio
    assert chegar(fluxo, outro).status_code == 200
    assert relatar(fluxo, outro).json()["cancelado"] is True
    sinais = sinais_antifraude(fluxo.ctx, incidentes(fluxo, outro)[0])
    assert sinais == ["relato_repetido_do_cliente:2", "relato_durante_espera_de_ausencia"]
    # A espera que estava aberta não anda mais: nem registro de ausência, nem retenção.
    fluxo.amb.relogio.agora = janela.inicio + timedelta(hours=1)
    assert ausente(fluxo, outro).status_code == 409
    caso = do_pedido(fluxo.ctx, fluxo.ctx.pedidos.obter(outro))
    assert caso.status == "aguardando_espera" and caso.registrada_em is None
    assert fluxo.ctx.cancelamentos.do_pedido(outro) is None


# --- A4 -------------------------------------------------------------------------------------


class MoedasComFalha(MoedasEmMemoria):
    def lancar(self, lancamento):
        if lancamento.tipo == "ajuste":
            raise RuntimeError("conexão caiu")
        return super().lancar(lancamento)


def test_a4_falha_ao_zerar_aborta_a_exclusao():
    repo = MoedasComFalha()
    repo.lancar(LancamentoMoeda(CLIENTE.id, "bonus_avaliacao", 10, "c", AGORA - D))
    with pytest.raises(RuntimeError):
        zerar_tratinhos_encerramento_voluntario(repo, CLIENTE.id, "pedido-1", AGORA)


# --- M5 -------------------------------------------------------------------------------------


def test_m5_trava_menor_mais_nova_nao_reduz_a_retencao(amb):
    travar(amb, limite=50_000, motivo="Primeira apuração de fraude.")
    amb.relogio.agora = AGORA + timedelta(minutes=1)
    travar(amb, limite=1_000, motivo="Segunda apuração de fraude.")
    quem = next(iter(amb.contexto.medidas._itens.values())).usuario_id
    assert amb.contexto.medidas.retencao_por_fraude(quem, amb.relogio.agora) == 50_000


# --- M6 -------------------------------------------------------------------------------------


def test_m6_credito_novo_nao_diminui_a_restauracao():
    repo = MoedasEmMemoria()

    def credito(chave, quantidade, criado, vence):
        repo.lancar(
            LancamentoMoeda(
                CLIENTE.id, "bonus_avaliacao", quantidade, chave, criado, expira_em=vence
            )
        )

    inicio = AGORA - 40 * D
    credito("velho", 100, inicio - D, inicio + 10 * D)
    credito("segue", 30, inicio - D, AGORA + 10 * D)
    credito("novo", 80, AGORA - D, AGORA + 30 * D)
    assert repo.restauracao_devida("m", CLIENTE.id, "cliente", inicio, AGORA) == 100


def test_a3_sinal_avisa_a_equipe_sem_travar_o_reembolso(fluxo, monkeypatch):
    avisos = []

    class Notificador:
        def notificar(self, evento, pessoa, **kw):
            avisos.append((evento.value, pessoa, kw["chave"]))
            raise RuntimeError("aviso fora do ar")

    monkeypatch.setattr(fluxo.ctx.incidentes, "equipe_de_seguranca", lambda: ["eq-1"])
    primeiro, _ = agendado(fluxo)
    segundo, _ = agendado(fluxo)
    fluxo.ctx.extras["notificador"] = Notificador()
    assert relatar(fluxo, primeiro).json()["cancelado"] is True
    assert not [a for a in avisos if a[0] == "seguranca.sinal_antifraude"]
    r = relatar(fluxo, segundo)
    assert r.status_code == 200 and r.json()["cancelado"] is True
    assert [a[1] for a in avisos if a[0] == "seguranca.sinal_antifraude"] == ["eq-1"]


@pytest.mark.parametrize("nome", CASOS)
def test_m6_regra_da_133600_em_memoria(nome):
    itens, devido = CASOS[nome]
    lancamentos = [
        LancamentoMoeda(
            CLIENTE.id,
            tipo,
            q,
            chave,
            AGORA + criada * D,
            expira_em=None if vence is None else AGORA + vence * D,
        )
        for q, tipo, criada, vence, chave in itens
    ]
    assert vencido_sem_uso(lancamentos, AGORA - 40 * D, AGORA) == devido
