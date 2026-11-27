"""TERMOS-BE1: e-mails, só MEI, prazo para avaliar (12.1), telefone depois da contratação (11.2),
avisos obrigatórios (15.2) e piso dos registros de acesso (14.8)."""

from __future__ import annotations

import re
from dataclasses import replace
from datetime import timedelta
from pathlib import Path

import pytest
from conftest import AGORA, CLIENTE, cab

import trato.api.rotas_legal as rotas_legal
from trato.lgpd.config import ConfigLgpd
from trato.notificacoes.canais import Canais, CanalApp, CanalFake
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import CATEGORIAS_OBRIGATORIAS, MODELOS, Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado
from trato.persistencia.conversas import ESTADOS_COM_CONTATO, mascarar_contatos
from trato.profissional.mei import MeiEmMemoria, RegistroMei, ServicoMei, StatusMei
from trato.seguranca.mascaramento import AVISO_MASCARA

DIA = timedelta(days=1)

# --- 1) e-mails -------------------------------------------------------------------------------


def test_paginas_legais_usam_os_enderecos_novos():
    fonte = Path(rotas_legal.__file__).read_text(encoding="utf-8")
    enderecos = set(re.findall(r"[\w.-]+@trato[\w.-]*\.br", fonte))
    assert enderecos == {
        "suporte@tratofeitolabs.com.br",
        "privacidade@tratofeitolabs.com.br",
    }


# --- 2) só MEI --------------------------------------------------------------------------------


def _com_registro(tipo: str | None) -> tuple[ServicoMei, MeiEmMemoria]:
    repo = MeiEmMemoria()
    repo.salvar(
        RegistroMei(
            "pro-1", "11222333000181", StatusMei.VALIDO, "CNPJ ativo.", AGORA, "Empresa", tipo
        )
    )
    return ServicoMei(repo=repo), repo


def test_validado_antes_sem_ser_mei_deixa_de_valer_sem_regravar():
    svc, repo = _com_registro("outro")
    assert svc.status("pro-1").mei_status is StatusMei.INVALIDO
    assert repo.obter("pro-1").mei_status is StatusMei.VALIDO  # nada foi escrito
    assert svc.liberado("pro-1")  # exigência desligada: ninguém é bloqueado
    svc.config = replace(svc.config, obrigatorio=True)
    assert not svc.liberado("pro-1")


@pytest.mark.parametrize("tipo", ["mei", None])
def test_mei_e_cadastro_sem_tipo_continuam_validos(tipo):
    svc, _ = _com_registro(tipo)
    svc.config = replace(svc.config, obrigatorio=True)
    assert svc.status("pro-1").mei_status is StatusMei.VALIDO and svc.liberado("pro-1")


def test_exigencia_de_mei_segue_desligada_por_padrao(monkeypatch):
    monkeypatch.delenv("TRATO_MEI_OBRIGATORIO", raising=False)
    assert ServicoMei().config.obrigatorio is False


# --- 3) prazo para avaliar --------------------------------------------------------------------


def _concluido(amb, ha: timedelta):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - ha)


def _avaliar(amb, quem="t-cliente", rota="/v1/pedidos/ped-1/avaliacao", nota=5):
    return amb.cliente.post(rota, json={"nota_geral": nota}, headers=cab(quem))


@pytest.mark.parametrize("quem", ["t-cliente", "t-prof"])
def test_avalia_ate_o_trigesimo_dia_e_depois_nao(amb, quem):
    _concluido(amb, 30 * DIA + timedelta(seconds=1))
    r = _avaliar(amb, quem)
    assert r.status_code == 409 and "30 dias" in r.text
    dados = amb.cliente.get("/v1/pedidos/ped-1/avaliacao", headers=cab(quem)).json()
    assert dados["prazo_encerrado"] is True and dados["bonus_disponivel"] is False


def test_no_limite_exato_ainda_avalia_pelas_duas_rotas(amb):
    _concluido(amb, 30 * DIA)
    assert _avaliar(amb).status_code == 201
    assert _avaliar(amb, "t-prof", "/v1/contratos/ped-1/avaliacao").status_code == 201


def test_repetir_a_mesma_avaliacao_depois_do_prazo_devolve_o_mesmo_sucesso(amb):
    _concluido(amb, 29 * DIA)
    assert _avaliar(amb).status_code == 201
    amb.relogio.avancar(days=10)
    assert _avaliar(amb).status_code == 200
    assert _avaliar(amb, nota=1).status_code == 409


@pytest.mark.parametrize("dias,ha,esperado", [(60, 45, 201), (7, 8, 409), (0, 20, 201)])
def test_prazo_vem_da_configuracao_com_padrao_seguro(amb, dias, ha, esperado):
    config = amb.contexto.config
    atual = config.carregar()
    config._config = replace(atual, prazo_avaliacao_dias=dias)
    _concluido(amb, ha * DIA)
    assert _avaliar(amb).status_code == esperado


# --- 4) telefone depois da contratação ----------------------------------------------------------

FONE = "(11) 98765-4321"


def _dizer(amb, texto):
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens", json={"texto": texto}, headers=cab("t-cliente")
    )
    assert r.status_code == 201, r.text
    return r.json()["texto"]


def _ler(amb):
    r = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-prof")).json()
    return [m["texto"] for m in (r["itens"] if isinstance(r, dict) else r)]


@pytest.mark.parametrize("estado", sorted(ESTADOS_COM_CONTATO))
def test_telefone_passa_com_o_pagamento_confirmado(amb, estado):
    amb.semear_pedido(estado)
    assert FONE in _dizer(amb, f"Chego em 10 min, meu número é {FONE}")
    assert any(FONE in t for t in _ler(amb))


@pytest.mark.parametrize(
    "estado", [Estado.ORCAMENTO_ACEITO, Estado.AGUARDANDO_CONFIRMACAO, Estado.CANCELADO]
)
def test_sem_pagamento_confirmado_o_telefone_continua_oculto(amb, estado):
    amb.semear_pedido(estado)
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens", json={"texto": f"liga {FONE}"}, headers=cab("t-cliente")
    )
    if r.status_code == 201:
        assert FONE not in r.json()["texto"] and AVISO_MASCARA in r.json()["texto"]


def test_mensagem_anterior_a_contratacao_segue_oculta(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    _dizer(amb, f"liga {FONE}")
    pedido = amb.contexto.pedidos.obter("ped-1")
    amb.contexto.pedidos.salvar(replace(pedido, estado=Estado.PAGO_E_RETIDO))
    assert all(FONE not in t for t in _ler(amb))
    assert FONE in _dizer(amb, f"agora sim {FONE}")


def test_pedido_cancelado_volta_a_esconder_na_leitura(amb):
    amb.semear_pedido(Estado.AGENDADO)
    _dizer(amb, f"liga {FONE}")
    pedido = amb.contexto.pedidos.obter("ped-1")
    amb.contexto.pedidos.salvar(replace(pedido, estado=Estado.CANCELADO))
    assert all(FONE not in t for t in _ler(amb))


def test_conversa_com_outro_profissional_nao_libera(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    contexto = amb.contexto
    outra = contexto.conversas.abrir("ped-1", "pro-nao-contratado")
    contexto.conversas.enviar(outra, CLIENTE.id, f"liga {FONE}")
    (msg,) = contexto.conversas.listar(outra)
    assert FONE not in msg.texto and msg.mascarada


@pytest.mark.parametrize(
    "texto",
    [
        "meu pix é 11987654321",
        f"paga por fora, liga {FONE}",
        "me paga direto no 11 98765-4321",
        f"sem a taxa do app, {FONE}",
        "a chave é 11987654321",
        "joao@gmail.com",
        "veja www.meusite.com.br",
        "me chama no ig fulano",
        "CPF 123.456.789-09",
        "cartão 4111 1111 1111 1111",
    ],
)
def test_liberado_o_telefone_o_resto_continua_oculto(texto):
    exibido = mascarar_contatos(texto, incluir_endereco=False, liberar_telefone=True)
    assert AVISO_MASCARA in exibido, exibido


@pytest.mark.parametrize(
    "texto", [FONE, "+55 11 98765-4321", "11987654321", "3221-4455", "nove oito sete 6 5 4 3 2"]
)
def test_formatos_de_telefone_liberados(texto):
    assert mascarar_contatos(texto, incluir_endereco=False, liberar_telefone=True) == texto
    assert AVISO_MASCARA in mascarar_contatos(texto)


# --- 5) avisos obrigatórios -------------------------------------------------------------------


@pytest.mark.parametrize(
    "evento", [e for e, m in MODELOS.items() if m.categoria in CATEGORIAS_OBRIGATORIAS]
)
def test_disputa_e_pagamento_ignoram_a_preferencia(evento):
    push, email = CanalFake("push"), CanalFake("email")

    class Emails:
        def email_de(self, usuario_id):
            return "pessoa@exemplo.test"

    s = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp(), push, email),
        ConfigNotificacoes(_env_file=None),
        lambda: AGORA,
        Emails(),
    )
    s.repo.registrar_dispositivo("u", "token-aparelho-1", "android", AGORA)
    desligado = {"app": False, "push": False, "email": False}
    s.repo.salvar_preferencias("u", {"disputas": desligado, "pagamentos": desligado}, AGORA)
    canais = [n.canal for n in s.notificar(evento, "u", chave="k")]
    esperado = ["app"] if MODELOS[evento].somente_app else ["app", "push", "email"]
    assert canais == esperado


def test_rota_nao_deixa_desligar_avisos_obrigatorios(amb):
    corpo = {"categorias": {"disputas": {"app": False}, "pagamentos": {"email": False}}}
    r = amb.cliente.put("/v1/notificacoes/preferencias", json=corpo, headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    ligados = {"app": True, "push": True, "email": True}
    assert r.json()["categorias"]["disputas"] == ligados
    assert r.json()["categorias"]["pagamentos"] == ligados
    assert r.json()["obrigatorias"] == ["disputas", "pagamentos"]
    assert Evento.DISPUTA_ABERTA in MODELOS


# --- 6) registros de acesso -------------------------------------------------------------------


@pytest.mark.parametrize(
    "configurado,vale", [({}, 184), ({"logs_acesso": 30}, 184), ({"logs_acesso": 365}, 365)]
)
def test_registros_de_acesso_tem_piso_de_6_meses(configurado, vale):
    cfg = ConfigLgpd(_env_file=None, retencao_dias=configurado)
    assert cfg.retencao_dias["logs_acesso"] == vale
    assert ConfigLgpd(_env_file=None).retencao_dias["logs_acesso"] == 184
