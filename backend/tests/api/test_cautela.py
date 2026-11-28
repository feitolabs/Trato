"""BE-96-FIM (Termos 9.6): contato bloqueado e registros preservados enquanto o incidente não
encerra, e aviso à equipe quando o prazo de cautela vence. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from conftest import CLIENTE, PROFISSIONAL, cab
from test_cliente_bloqueado_pedido import bloquear
from test_conta_valores import agendar, lgpd
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401
from test_pessoa_diferente import URL, abrir_no_painel, agendado, relatar

from trato.api.cautela import avisar_cautela_atrasada
from trato.lgpd.servico import ErroLgpd


def medida(f, iid, tipo):
    corpo = {"tipo": tipo, "descricao": f"Medida de cautela: {tipo}."}
    r = f.http.post(f"{URL}/{iid}/medidas", json=corpo, headers=cab("t-seguranca"))
    assert r.status_code == 200, r.text


def encerrar(f, iid):
    corpo = {"desfecho": "Apurado e resolvido com as partes."}
    r = f.http.post(f"{URL}/{iid}/encerrar", json=corpo, headers=cab("t-seguranca"))
    assert r.status_code == 200, r.text


def mensagem(f, pid, quem="t-cliente"):
    extra = f"?profissional_id={PROFISSIONAL.id}" if quem == "t-cliente" else ""
    url = f"/v1/pedidos/{pid}/mensagens{extra}"
    return f.chamar("POST", url, quem, {"texto": "Olá, tudo bem?"})


def test_contato_bloqueado_entre_as_partes_ate_encerrar(fluxo):
    com_equipe(fluxo.amb)
    pid, _ = agendado(fluxo)
    assert mensagem(fluxo, pid).status_code == 201
    iid = abrir_no_painel(fluxo, pid, "agressao_ameaca_assedio")
    assert mensagem(fluxo, pid).status_code == 201  # abrir não bloqueia
    medida(fluxo, iid, "bloquear_contato")
    for quem in ("t-cliente", "t-prof"):
        r = mensagem(fluxo, pid, quem)
        assert r.status_code == 409 and "9.6" in r.json()["detail"], (quem, r.text)
    encerrar(fluxo, iid)
    assert mensagem(fluxo, pid).status_code == 201


def test_registros_preservados_adiam_a_exclusao_ate_encerrar(fluxo):
    com_equipe(fluxo.amb)
    pid, _ = agendado(fluxo)
    iid = abrir_no_painel(fluxo, pid, "comportamento_suspeito")
    assert fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti."}).status_code == 200
    s = lgpd(fluxo)
    agendar(fluxo, s)  # sem a medida ainda não há preservação
    medida(fluxo, iid, "preservar_registros")
    passo = s.situacao_exclusao(CLIENTE, fluxo.ctx.agora())
    assert passo["pedido"]["status"] == "agendada"
    fluxo.amb.relogio.avancar(days=8)
    assert s.processar_vencidas(fluxo.ctx.agora()) == {"anonimizadas": 0, "adiadas": 1}
    encerrar(fluxo, iid)
    assert s.processar_vencidas(fluxo.ctx.agora())["anonimizadas"] == 1


def test_preservacao_aparece_na_previa_e_barra_a_confirmacao(fluxo):
    com_equipe(fluxo.amb)
    pid, _ = agendado(fluxo)
    iid = abrir_no_painel(fluxo, pid, "comportamento_suspeito")
    medida(fluxo, iid, "preservar_registros")
    s = lgpd(fluxo)
    passo = s.pedir_exclusao(PROFISSIONAL, fluxo.ctx.agora())
    assert any("9.6" in p for p in passo["pendencias"]), passo["pendencias"]
    try:
        s.confirmar_exclusao(PROFISSIONAL, passo["token_confirmacao"], fluxo.ctx.agora())
        raise AssertionError("deveria recusar")
    except ErroLgpd as erro:
        assert erro.status == 409


class Avisos:
    def __init__(self) -> None:
        self.itens: dict[tuple[str, str], str] = {}

    def notificar(self, evento, usuario, *, chave, corpo=None, **_):
        self.itens.setdefault((usuario, chave), corpo)
        return []


def test_prazo_de_cautela_vencido_avisa_a_equipe_uma_vez(fluxo):
    com_equipe(fluxo.amb)
    pid, _ = agendado(fluxo)
    fluxo.ctx.incidentes.equipe = ["eq-seguranca"]
    iid = abrir_no_painel(fluxo, pid, "comportamento_suspeito")
    avisos = Avisos()
    fluxo.amb.relogio.avancar(hours=24)
    assert avisar_cautela_atrasada(fluxo.ctx, avisos, fluxo.ctx.agora()) == 0
    fluxo.amb.relogio.avancar(seconds=1)
    for _ in range(2):
        assert avisar_cautela_atrasada(fluxo.ctx, avisos, fluxo.ctx.agora()) == 1
    assert [u for u, _ in avisos.itens] == ["eq-seguranca"]
    medida(fluxo, iid, "reter_valor")
    corpo = {"status": "cautela_adotada"}
    r = fluxo.http.post(f"{URL}/{iid}/status", json=corpo, headers=cab("t-seguranca"))
    assert r.status_code == 200, r.text
    assert avisar_cautela_atrasada(fluxo.ctx, avisos, fluxo.ctx.agora()) == 0


def test_bloqueado_ve_o_pedido_cancelado_por_pessoa_diferente(fluxo):
    for antes in (True, False):
        pid, _ = agendado(fluxo)
        if antes:  # suspensão já cancelaria o pedido antes do relato (20.6)
            bloquear(fluxo, "bloqueio_preventivo")
        assert relatar(fluxo, pid).json()["cancelado"] is True
        if not antes:
            bloquear(fluxo)
        assert fluxo.chamar("GET", f"/v1/pedidos/{pid}", "t-cliente").status_code == 200
        lista = fluxo.chamar("GET", "/v1/pedidos", "t-cliente").json()
        assert pid in [p["id"] for p in lista]
        fluxo.amb.contexto.auth.bloqueados.clear()
