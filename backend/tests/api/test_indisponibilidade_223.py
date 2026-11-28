"""BE-INDISPONIBILIDADE-22.3-A: falha do app ou do pagamento prorroga prazos e isenta o encargo
de ausência. Memória."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from conftest import AGORA, cab
from test_agendador import montar
from test_ausencia_cliente import LONGE, registrado, remarcado_para_longe
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.admin.rotas_ausencias import _barrar_retencao_de_bloqueado
from trato.api.indisponibilidade import impedimento_por_falha
from trato.disputas.indisponibilidade import prorrogar
from trato.pedidos.estados import Acao, Estado
from trato.pedidos.estados import Janela as JanelaPedido
from trato.persistencia.indisponibilidades import Janela, JanelaSobreposta

H = timedelta(hours=1)
D = timedelta(days=1)
URL = "/v1/admin/indisponibilidades"
MOTIVO = "Aplicativo fora do ar para todos."


@pytest.mark.parametrize(
    ("falhas", "extra"),
    [
        ([], 0),
        ([(-5, -1)], 0),  # antes do prazo começar
        ([(-1, 2)], 2),  # só o que cai dentro
        ([(1, 3), (2, 4)], 3),  # sobrepostas: sem dobro
        ([(1, 3), (1, 3)], 2),  # duas origens ao mesmo tempo
        ([(9, 12), (12, 13)], 4),  # encostadas, atravessando o vencimento
        ([(9, 11), (11.5, 12)], 2.5),  # a segunda cai na prorrogação
        ([(13, 14)], 0),  # depois do vencimento
    ],
)
def test_prorrogacao(falhas, extra):
    janelas = [(AGORA + a * H, AGORA + b * H) for a, b in falhas]
    assert prorrogar(AGORA, 10 * H, janelas) == AGORA + (10 + extra) * H


def test_falha_ativa_suspende_o_prazo():
    assert prorrogar(AGORA, 10 * H, [(AGORA + H, None)]) is None
    assert prorrogar(AGORA, 10 * H, [(AGORA + 11 * H, None)]) == AGORA + 10 * H


def falha(contexto, inicio, fim=None, origem="app"):
    return contexto.indisponibilidades.criar(
        Janela(origem, inicio, MOTIVO, "eq-admin", fim_em=fim)
    )[0]


def test_sem_confirmacao_pelo_silencio_ate_o_fim_prorrogado(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 8 * D)
    janela = falha(amb.contexto, AGORA - 6 * D)
    agendador, _, _ = montar(amb)
    agendador.rodar_uma_vez()
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.EM_CONFIRMACAO
    # Falha de 3 dias dentro de um prazo de 7: vence 10 dias depois do check-out.
    assert amb.contexto.indisponibilidades.encerrar(janela.id, AGORA - 3 * D, "eq-admin")
    agendador.rodar_uma_vez()
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.EM_CONFIRMACAO
    amb.relogio.avancar(days=2)
    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.CONCLUIDO
    assert len(amb.contexto.pedidos.eventos("ped-1")) == 1


def test_prazo_original_correndo_nao_e_adiamento_por_falha(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - D)
    ExecutorContexto(amb.contexto).executar(acao_de("ped-1", Acao.CONCLUIR_POR_PRAZO), AGORA)
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.EM_CONFIRMACAO


def test_falha_so_do_pagamento_nao_adia_a_confirmacao(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 8 * D)
    falha(amb.contexto, AGORA - 6 * D, origem="pagamento")
    montar(amb)[0].rodar_uma_vez()
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.CONCLUIDO


def acao_de(pid, acao):
    from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

    return AcaoRotina(TipoAcaoRotina.TRANSICIONAR, pid, f"teste:{pid}", acao=acao)


def test_pagamento_nao_expira_durante_a_falha_do_parceiro(fluxo):
    pid = fluxo.aceitar()
    falha(fluxo.ctx, fluxo.ctx.agora(), origem="pagamento")
    fluxo.amb.relogio.avancar(days=2)  # prazo de pagamento: 24 h
    with pytest.raises(Adiada, match="indisponibilidade"):
        ExecutorContexto(fluxo.ctx).executar(
            acao_de(pid, Acao.EXPIRAR_PAGAMENTO), fluxo.ctx.agora()
        )
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.ORCAMENTO_ACEITO


def test_falha_no_atendimento_nao_vira_ausencia_automatica(amb):
    janela = JanelaPedido(AGORA - 6 * H, AGORA - 4 * H)
    amb.semear_pedido(Estado.AGENDADO, janela=janela)
    falha(amb.contexto, AGORA - 5 * H, AGORA - 4.5 * H)
    with pytest.raises(Adiada, match="falha_cobre_evento"):
        ExecutorContexto(amb.contexto).executar(
            acao_de("ped-1", Acao.REGISTRAR_AUSENCIA), amb.relogio.agora
        )
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.AGENDADO


def test_falha_fora_do_atendimento_nao_isenta(amb):
    janela = JanelaPedido(AGORA - 6 * H, AGORA - 4 * H)
    amb.semear_pedido(Estado.AGENDADO, janela=janela)
    falha(amb.contexto, AGORA - 20 * H, AGORA - 10 * H)
    pedido = amb.contexto.pedidos.obter("ped-1")
    assert (
        impedimento_por_falha(amb.contexto, pedido, Acao.REGISTRAR_AUSENCIA, amb.relogio.agora)
        is None
    )


def test_sem_retencao_por_ausencia_quando_a_falha_cobre_o_atendimento(fluxo):
    pid, _ = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    pedido = fluxo.ctx.pedidos.obter(pid)
    _barrar_retencao_de_bloqueado(fluxo.ctx, pedido, "Decida sem retenção.")  # sem falha: passa
    falha(fluxo.ctx, pedido.janela.inicio, fluxo.ctx.agora())
    with pytest.raises(Exception, match="22.3"):
        _barrar_retencao_de_bloqueado(fluxo.ctx, pedido, "Decida sem retenção.")


def test_concorrencia_abre_uma_janela_so(amb):
    with ThreadPoolExecutor(4) as grupo:
        ids = {j.id for j in grupo.map(lambda _: falha(amb.contexto, AGORA - H), range(8))}
    assert len(ids) == 1
    with pytest.raises(JanelaSobreposta):
        falha(amb.contexto, AGORA - 30 * H, AGORA)


def test_rotas_admin_com_auditoria_e_encerramento_unico(amb):
    com_equipe(amb)
    http, agora = amb.cliente, amb.relogio.agora

    def post(url, corpo, quem="t-lider"):
        return http.post(url, json=corpo, headers=cab(quem))

    corpo = {"origem": "app", "inicio_em": (agora - 2 * H).isoformat(), "motivo": MOTIVO}
    assert post(URL, corpo, "t-mediador").status_code == 403
    assert post(URL, corpo, "t-cliente").status_code == 403
    futuro = corpo | {"inicio_em": (agora + H).isoformat()}
    assert post(URL, futuro).status_code == 422
    assert post(URL, corpo | {"motivo": "curto"}).status_code == 422
    assert post(URL, corpo | {"inicio_em": "2026-10-01T10:00:00"}).status_code == 422  # sem fuso
    r = post(URL, corpo)
    assert r.status_code == 201 and r.json()["ativa"], r.text
    assert post(URL, corpo).status_code == 200  # repetir não duplica
    assert post(URL, corpo | {"inicio_em": (agora - H).isoformat()}).status_code == 409
    lista = http.get(f"{URL}?abertas=true", headers=cab("t-admin")).json()
    assert lista["total"] == 1
    url = f"{URL}/{r.json()['id']}/encerrar"
    fim = {"motivo": "Serviço normalizado após o reparo."}
    assert post(url, fim | {"fim_em": (agora + H).isoformat()}).status_code == 422
    feito = post(url, fim)
    assert feito.status_code == 200 and not feito.json()["ativa"], feito.text
    assert post(url, fim).status_code == 409
    assert post(f"{URL}/nao-existe/encerrar", fim).status_code == 404
    acoes = [e.acao for e in amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)[0]]
    assert sorted(a for a in acoes if a.startswith("indisponibilidade.")) == [
        "indisponibilidade.encerrada",
        "indisponibilidade.registrada",
    ]
