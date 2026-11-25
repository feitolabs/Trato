"""A notificação diz para qual papel ela é (`dados.papel`), pelo pedido do destinatário."""

from __future__ import annotations

from conftest import CLIENTE, OUTRO_PROFISSIONAL, PROFISSIONAL, cab

from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp, Mensagem, PushFcm
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado, Pedido


def _servico(amb) -> ServicoNotificacoes:
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(), Canais(app=CanalApp()), ConfigNotificacoes(ativo=True)
    )
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    return notif


def _dados(notif, usuario_id, evento=Evento.PAGAMENTO_CONFIRMADO):
    (n,) = [x for x in notif.repo.listar(usuario_id, False, 50) if x.tipo == evento.value]
    return n.dados


def test_cliente_recebe_cliente_e_profissional_recebe_profissional(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    notif = _servico(amb)
    for quem in (CLIENTE.id, PROFISSIONAL.id):
        notif.notificar(Evento.PAGAMENTO_CONFIRMADO, quem, chave="c1", pedido_id="ped-1")
    assert _dados(notif, CLIENTE.id)["papel"] == "cliente"
    assert _dados(notif, PROFISSIONAL.id)["papel"] == "profissional"


def test_mesma_pessoa_com_os_dois_papeis_em_pedidos_diferentes(amb):
    # cli-1 é cliente do ped-1 e profissional do ped-2 (outro cliente)
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.contexto.pedidos.salvar(
        Pedido(
            id="ped-2",
            cliente_id="cli-2",
            aberto_em=amb.contexto.agora(),
            estado=Estado.PAGO_E_RETIDO,
            profissional_id=CLIENTE.id,
        )
    )
    notif = _servico(amb)
    notif.notificar(Evento.PAGAMENTO_CONFIRMADO, CLIENTE.id, chave="a", pedido_id="ped-1")
    notif.notificar(Evento.PAGAMENTO_CONFIRMADO, CLIENTE.id, chave="b", pedido_id="ped-2")
    papeis = {
        n.dados["pedido_id"]: n.dados["papel"] for n in notif.repo.listar(CLIENTE.id, False, 50)
    }
    assert papeis == {"ped-1": "cliente", "ped-2": "profissional"}


def test_sem_pedido_ou_fora_do_pedido_nao_vai_a_chave(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    notif = _servico(amb)
    notif.notificar(Evento.PAGAMENTO_CONFIRMADO, CLIENTE.id, chave="s", pedido_id=None)
    assert "papel" not in _dados(notif, CLIENTE.id)
    notif.notificar(
        Evento.PAGAMENTO_CONFIRMADO, OUTRO_PROFISSIONAL.id, chave="f", pedido_id="ped-1"
    )
    assert "papel" not in _dados(notif, OUTRO_PROFISSIONAL.id)
    novas = notif.notificar(
        Evento.PAGAMENTO_CONFIRMADO, CLIENTE.id, chave="n", pedido_id="nao-existe"
    )
    assert len(novas) == 1 and "papel" not in novas[0].dados  # pedido inexistente: sem erro


def test_uma_unica_leitura_de_pedido_por_notificacao(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    notif = _servico(amb)
    leituras: list[str] = []
    original = notif.pedidos

    def contar(pid):
        leituras.append(pid)
        return original(pid)

    notif.pedidos = contar
    notif.notificar(Evento.PAGAMENTO_CONFIRMADO, CLIENTE.id, chave="u", pedido_id="ped-1")
    assert leituras == ["ped-1"]  # app + push + e-mail compartilham a mesma leitura


def test_falha_na_leitura_do_pedido_nao_derruba_a_notificacao(amb):
    notif = _servico(amb)

    def quebrada(_pid):
        raise RuntimeError("banco fora")

    notif.pedidos = quebrada
    novas = notif.notificar(Evento.PAGAMENTO_CONFIRMADO, CLIENTE.id, chave="q", pedido_id="ped-1")
    assert len(novas) == 1 and "papel" not in novas[0].dados


def test_papel_explicito_vale_e_dados_do_chamador_nao_perde(amb):
    notif = _servico(amb)
    notif.notificar(
        Evento.PAGAMENTO_CONFIRMADO, CLIENTE.id, chave="e", pedido_id="ped-1", papel="profissional"
    )
    assert _dados(notif, CLIENTE.id)["papel"] == "profissional"


def test_gancho_das_transicoes_e_a_caixa_da_api_devolvem_o_papel(amb):
    amb.semear_pedido(Estado.AGUARDANDO_CONFIRMACAO)
    notif = _servico(amb)
    for gancho in amb.contexto.apos_transicao:
        antes = amb.contexto.pedidos.obter("ped-1")
        from dataclasses import replace

        from trato.pedidos.estados import Acao

        gancho(antes, replace(antes, estado=Estado.PAGO_E_RETIDO), Acao.CONFIRMAR_PAGAMENTO, None)
    assert _dados(notif, CLIENTE.id)["papel"] == "cliente"
    assert _dados(notif, PROFISSIONAL.id)["papel"] == "profissional"
    caixa = amb.cliente.get("/v1/notificacoes", headers=cab("t-prof"))
    assert caixa.status_code == 200, caixa.text
    itens = caixa.json()["itens"] if isinstance(caixa.json(), dict) else caixa.json()
    assert itens and all(i["dados"]["papel"] == "profissional" for i in itens)


def test_payload_fcm_leva_o_papel_como_texto():
    msg = Mensagem(
        "u1", "t", "c", {"evento": "x", "papel": "profissional", "pedido_id": "p1"}, ("tok",)
    )
    cfg = ConfigNotificacoes(push_ativo=True, fcm_projeto_id="proj")
    carga = PushFcm(cfg, lambda *a: 200, lambda: "t").carga("tok", msg)
    assert carga["message"]["data"]["papel"] == "profissional"


def test_push_nao_leva_none_como_texto_e_converte_o_resto():
    from trato.notificacoes.canais import PushApns

    dados = {"pedido_id": None, "": "x", "papel": "cliente", "n": 3, "ok": True, "zero": 0}
    msg = Mensagem("u1", "t", "c", dados, ("tok",))
    cfg = ConfigNotificacoes(push_ativo=True, fcm_projeto_id="proj")
    data = PushFcm(cfg, lambda *a: 200, lambda: "t").carga("tok", msg)["message"]["data"]
    assert data == {"papel": "cliente", "n": "3", "ok": "True", "zero": "0"}
    assert "None" not in data.values() and "pedido_id" not in data
    apns = PushApns(cfg, lambda *a: 200, lambda: "t").carga(msg)
    assert "pedido_id" not in apns and "None" not in str(apns) and apns["n"] == "3"


def test_caixa_da_api_nao_devolve_none_como_texto(amb):
    notif = _servico(amb)
    notif.notificar(Evento.PAGAMENTO_CONFIRMADO, PROFISSIONAL.id, chave="sp", pedido_id=None)
    r = amb.cliente.get("/v1/notificacoes", headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert '"None"' not in r.text
    itens = r.json()["itens"] if isinstance(r.json(), dict) else r.json()
    assert itens and itens[0]["dados"]["pedido_id"] is None  # ausente de verdade, não o texto


# --- pedido direto: o convidado ainda não é o profissional_id do pedido ----------------------


def test_eventos_da_tela_pedido_aberto_sao_todos_so_de_profissional():
    """Quem entra aqui recebe `papel = profissional` sem consulta. Evento novo nesta tela precisa
    ser revisto: se algum dia for para cliente, este teste falha de propósito."""
    from trato.notificacoes.eventos import MODELOS

    na_tela = {e for e, m in MODELOS.items() if m.tela == "pedido_aberto"}
    assert na_tela == {
        Evento.PEDIDO_NOVO,
        Evento.PEDIDO_DIRECIONADO,
        Evento.PEDIDO_URGENTE,
        Evento.ORCAMENTO_RECUSADO,
        Evento.ORCAMENTO_NAO_ESCOLHIDO,
        Evento.EXCLUSIVIDADE_ACEITA,
    }


def test_pedido_direcionado_e_pedido_novo_vao_como_profissional_sem_ler_o_pedido(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    notif = _servico(amb)
    leituras: list[str] = []
    notif.pedidos = lambda pid: leituras.append(pid)  # não pode ser chamada para estes eventos
    notif.notificar(Evento.PEDIDO_DIRECIONADO, PROFISSIONAL.id, chave="d", pedido_id="ped-1")
    notif.notificar(Evento.PEDIDO_NOVO, OUTRO_PROFISSIONAL.id, chave="n", pedido_id="ped-1")
    assert _dados(notif, PROFISSIONAL.id, Evento.PEDIDO_DIRECIONADO)["papel"] == "profissional"
    assert _dados(notif, OUTRO_PROFISSIONAL.id, Evento.PEDIDO_NOVO)["papel"] == "profissional"
    assert leituras == []


def test_convidado_de_pedido_direto_recebe_profissional_em_outros_eventos(amb):
    # pedido direto ainda sem orçamento aceito: pro-1 é só o convidado (profissional_id vazio)
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    amb.contexto.extras["pedidos_convidados"] = {"ped-1": PROFISSIONAL.id}
    notif = _servico(amb)
    notif.notificar(Evento.MENSAGEM_NOVA, PROFISSIONAL.id, chave="m", pedido_id="ped-1")
    notif.notificar(Evento.MENSAGEM_NOVA, CLIENTE.id, chave="m2", pedido_id="ped-1")
    notif.notificar(Evento.MENSAGEM_NOVA, OUTRO_PROFISSIONAL.id, chave="m3", pedido_id="ped-1")
    assert _dados(notif, PROFISSIONAL.id, Evento.MENSAGEM_NOVA)["papel"] == "profissional"
    assert _dados(notif, CLIENTE.id, Evento.MENSAGEM_NOVA)["papel"] == "cliente"
    assert "papel" not in _dados(
        notif, OUTRO_PROFISSIONAL.id, Evento.MENSAGEM_NOVA
    )  # não convidado


def test_convidado_pelos_dados_do_pedido_tambem_vale(amb):
    from types import SimpleNamespace

    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    amb.contexto.pedidos.dados_do_pedido = lambda _pid: SimpleNamespace(
        profissional_convidado_id=PROFISSIONAL.id
    )
    notif = _servico(amb)
    notif.notificar(Evento.MENSAGEM_NOVA, PROFISSIONAL.id, chave="m", pedido_id="ped-1")
    notif.notificar(Evento.MENSAGEM_NOVA, CLIENTE.id, chave="m2", pedido_id="ped-1")
    assert _dados(notif, PROFISSIONAL.id, Evento.MENSAGEM_NOVA)["papel"] == "profissional"
    assert _dados(notif, CLIENTE.id, Evento.MENSAGEM_NOVA)["papel"] == "cliente"
