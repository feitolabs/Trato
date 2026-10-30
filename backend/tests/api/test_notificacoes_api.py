"""Rotas de notificações, preferências, dispositivos e conversas (memória)."""

from __future__ import annotations

from conftest import CLIENTE, OUTRO_CLIENTE, PROFISSIONAL, cab

from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp, CanalFake
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado


def servico_do(amb, push=None):
    s = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp(), push, None),
        ConfigNotificacoes(_env_file=None),
        amb.relogio,
    )
    return ligar_ao_contexto(amb.cliente.app, amb.contexto, s)


def get(amb, url, quem="t-cliente"):
    return amb.cliente.get(url, headers=cab(quem))


def post(amb, url, quem="t-cliente", corpo=None):
    return amb.cliente.post(url, json=corpo, headers=cab(quem))


def put(amb, url, corpo, quem="t-cliente"):
    return amb.cliente.put(url, json=corpo, headers=cab(quem))


def test_tudo_exige_login(amb):
    for metodo, url in (
        ("get", "/v1/notificacoes"),
        ("get", "/v1/notificacoes/preferencias"),
        ("put", "/v1/notificacoes/preferencias"),
        ("post", "/v1/notificacoes/x/lida"),
        ("post", "/v1/dispositivos"),
        ("get", "/v1/conversas"),
        ("post", "/v1/mensagens/1/lida"),
    ):
        assert getattr(amb.cliente, metodo)(url).status_code == 401, url
    assert get(amb, "/v1/notificacoes", "t-equipe").status_code == 403


def test_listar_e_marcar_como_lida(amb):
    s = servico_do(amb)
    s.notificar(Evento.ORCAMENTO_ACEITO, CLIENTE.id, chave="a", pedido_id="ped-1")
    s.notificar(Evento.ORCAMENTO_ACEITO, OUTRO_CLIENTE.id, chave="b", pedido_id="ped-2")
    [nota] = get(amb, "/v1/notificacoes").json()
    assert nota["lida"] is False and nota["dados"]["link"] == "trato://pedido/ped-1"
    r = post(amb, f"/v1/notificacoes/{nota['id']}/lida")
    assert r.status_code == 200 and r.json()["lida"] is True
    de_novo = post(amb, f"/v1/notificacoes/{nota['id']}/lida")
    assert de_novo.json()["lida_em"] == r.json()["lida_em"]  # idempotente
    assert get(amb, "/v1/notificacoes?nao_lidas=true").json() == []


def test_nao_marca_a_notificacao_de_outra_pessoa(amb):
    s = servico_do(amb)
    [alheia] = s.notificar(Evento.AVALIACAO, OUTRO_CLIENTE.id, chave="b")
    assert post(amb, f"/v1/notificacoes/{alheia.id}/lida").status_code == 404
    assert post(amb, "/v1/notificacoes/inexistente/lida").status_code == 404


def test_notificacao_antiga_do_contexto_continua_aparecendo(amb):
    servico_do(amb)
    amb.contexto.notificacoes.criar(CLIENTE.id, "x", "Antiga", dados={"p": 1})
    assert [n["titulo"] for n in get(amb, "/v1/notificacoes").json()] == ["Antiga"]


def test_preferencias_leitura_e_troca_parcial(amb):
    servico_do(amb)
    padrao = get(amb, "/v1/notificacoes/preferencias").json()["categorias"]
    assert padrao["disputas"] == {"app": True, "push": True, "email": False}
    r = put(amb, "/v1/notificacoes/preferencias", {"categorias": {"disputas": {"push": False}}})
    assert r.status_code == 200
    assert r.json()["categorias"]["disputas"] == {"app": True, "push": False, "email": False}
    assert r.json()["categorias"]["agenda"] == padrao["agenda"]  # o resto não mexe
    # preferência é por pessoa
    assert get(amb, "/v1/notificacoes/preferencias", "t-prof").json()["categorias"] == padrao


def test_preferencias_recusam_canal_sms_e_categoria_inventada(amb):
    servico_do(amb)
    for corpo in (
        {"categorias": {"disputas": {"sms": True}}},
        {"categorias": {"disputas": {"whatsapp": True}}},
        {"categorias": {"inventada": {"app": True}}},
    ):
        assert put(amb, "/v1/notificacoes/preferencias", corpo).status_code == 422
    assert put(amb, "/v1/notificacoes/preferencias", {"x": 1}).status_code == 422


def test_preferencia_desligada_vale_nas_notificacoes(amb):
    s = servico_do(amb)
    put(amb, "/v1/notificacoes/preferencias", {"categorias": {"avaliacoes": {"app": False}}})
    assert s.notificar(Evento.AVALIACAO, CLIENTE.id, chave="a") == []
    assert get(amb, "/v1/notificacoes").json() == []


def test_registrar_dispositivo_e_receber_push(amb):
    push = CanalFake("push")
    s = servico_do(amb, push)
    r = post(
        amb, "/v1/dispositivos", corpo={"token": "token-do-aparelho-1", "plataforma": "android"}
    )
    assert r.status_code == 204
    post(amb, "/v1/dispositivos", corpo={"token": "token-do-aparelho-1", "plataforma": "android"})
    assert s.repo.tokens(CLIENTE.id) == ("token-do-aparelho-1",)  # repetir não duplica
    s.notificar(Evento.AVALIACAO, CLIENTE.id, chave="a")
    assert push.enviados[0].destinos == ("token-do-aparelho-1",)
    # o aparelho trocou de dono (outra conta entrou no mesmo celular)
    post(
        amb,
        "/v1/dispositivos",
        "t-outro-cliente",
        {"token": "token-do-aparelho-1", "plataforma": "ios"},
    )
    assert s.repo.tokens(CLIENTE.id) == () and s.repo.tokens(OUTRO_CLIENTE.id) == (
        "token-do-aparelho-1",
    )


def test_dispositivo_invalido(amb):
    servico_do(amb)
    assert (
        post(amb, "/v1/dispositivos", corpo={"token": "curto", "plataforma": "android"}).status_code
        == 422
    )
    r = post(
        amb, "/v1/dispositivos", corpo={"token": "token-do-aparelho-1", "plataforma": "windows"}
    )
    assert r.status_code == 422
    r = post(
        amb, "/v1/dispositivos", corpo={"token": "token-do-aparelho-1", "plataforma": "ios", "x": 1}
    )
    assert r.status_code == 422


# --- conversas ----------------------------------------------------------------------------


def _conversa(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens", json={"texto": "Oi, tudo bem?"}, headers=cab("t-cliente")
    )
    assert r.status_code == 201, r.text
    return r.json()


def test_lista_de_conversas_com_nao_lidas(amb):
    servico_do(amb)
    m = _conversa(amb)
    amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens", json={"texto": "Respondendo"}, headers=cab("t-prof")
    )
    do_cliente = get(amb, "/v1/conversas").json()
    assert len(do_cliente) == 1
    assert do_cliente[0]["outra_parte_id"] == PROFISSIONAL.id
    assert do_cliente[0]["nao_lidas"] == 1 and do_cliente[0]["ultima_mensagem"] == "Respondendo"
    do_prof = get(amb, "/v1/conversas", "t-prof").json()
    assert do_prof[0]["nao_lidas"] == 1 and do_prof[0]["ultima_minha"] is True
    assert get(amb, "/v1/conversas", "t-outro-cliente").json() == []
    assert m["id"] >= 1


def test_marcar_mensagem_como_lida(amb):
    servico_do(amb)
    m = _conversa(amb)
    # o autor não "lê" a própria mensagem; quem recebeu, sim, e repetir não muda a hora
    assert post(amb, f"/v1/mensagens/{m['id']}/lida").status_code == 422
    assert post(amb, f"/v1/mensagens/{m['id']}/lida", "t-outro-cliente").status_code == 404
    r = post(amb, f"/v1/mensagens/{m['id']}/lida", "t-prof")
    assert r.status_code == 200
    assert post(amb, f"/v1/mensagens/{m['id']}/lida", "t-prof").json() == r.json()
    assert get(amb, "/v1/conversas", "t-prof").json()[0]["nao_lidas"] == 0
    assert post(amb, "/v1/mensagens/999/lida", "t-prof").status_code == 404


def test_marcar_conversa_inteira_como_lida(amb):
    servico_do(amb)
    _conversa(amb)
    amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens", json={"texto": "Mais uma"}, headers=cab("t-cliente")
    )
    conversa = get(amb, "/v1/conversas", "t-prof").json()[0]["id"]
    assert post(amb, f"/v1/conversas/{conversa}/lida", "t-outro-cliente").status_code == 404
    assert post(amb, f"/v1/conversas/{conversa}/lida", "t-prof").json() == {"marcadas": 2}
    assert post(amb, f"/v1/conversas/{conversa}/lida", "t-prof").json() == {"marcadas": 0}


def test_previa_da_conversa_continua_mascarada_antes_da_contratacao(amb):
    servico_do(amb)
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    amb.contexto.contratos = type(amb.contexto.contratos)()  # sem contrato: ainda não contratou
    amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens?profissional_id=pro-1",
        json={"texto": "me chama em fulano@exemplo.com"},
        headers=cab("t-cliente"),
    )
    previa = get(amb, "/v1/conversas").json()[0]["ultima_mensagem"]
    assert "fulano@exemplo.com" not in previa
