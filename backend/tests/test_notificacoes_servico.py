"""Serviço de notificações em memória: preferências, idempotência, canais, reenvio e SMS (D14)."""

from __future__ import annotations

import smtplib
from dataclasses import replace
from datetime import UTC, datetime, timedelta

import pytest

from trato.notificacoes.canais import (
    Canais,
    CanalApp,
    CanalFake,
    EmailSmtp,
    LimiteSmsExcedido,
    Mensagem,
    PushApns,
    PushFcm,
    ServicoSmsConfirmacao,
    SmsFake,
    canais_da_config,
)
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import MODELOS, Evento
from trato.notificacoes.ganchos import criar_gancho
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Acao, Estado, Pedido

T0 = datetime(2026, 11, 2, 9, 0, tzinfo=UTC)
ANA, BIA = "ana", "bia"


def cfg(**campos) -> ConfigNotificacoes:
    return ConfigNotificacoes(_env_file=None, **campos)


class Relogio:
    def __init__(self) -> None:
        self.agora = T0

    def __call__(self) -> datetime:
        return self.agora


@pytest.fixture
def push() -> CanalFake:
    return CanalFake("push")


@pytest.fixture
def email() -> CanalFake:
    return CanalFake("email")


@pytest.fixture
def relogio() -> Relogio:
    return Relogio()


class EmailsFixos:
    def email_de(self, usuario_id: str) -> str | None:
        return {ANA: "ana@exemplo.test"}.get(usuario_id)


@pytest.fixture
def servico(push, email, relogio) -> ServicoNotificacoes:
    return ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp(), push, email),
        cfg(padrao_email=True),
        relogio,
        EmailsFixos(),
    )


def so_app(novas):
    return next(n for n in novas if n.canal == "app")


def test_cria_na_caixa_de_entrada_com_deep_link(servico):
    n = so_app(servico.notificar(Evento.ORCAMENTO_ACEITO, ANA, chave="p1", pedido_id="p1"))
    assert (n.canal, n.tipo, n.titulo) == ("app", "orcamento.aceito", "Orçamento aceito")
    assert n.dados["link"] == "trato://pedido/p1"
    assert n.dados["pedido_id"] == "p1" and n.dados["tela"] == "pedido"
    assert servico.repo.listar(ANA, False, 10)[0].id == n.id


def test_textos_respeitam_a_d13():
    proibidos = ("escrow", "garantia total", "profissional seguro", "reembolso automático")
    for modelo in MODELOS.values():
        texto = f"{modelo.titulo} {modelo.corpo}".lower()
        assert not any(p in texto for p in proibidos)


def test_codigo_de_inicio_nao_vai_na_notificacao(servico):
    n = so_app(
        servico.notificar(
            Evento.CODIGO_INICIO, ANA, chave="p1", pedido_id="p1", dados={"extra": "ok"}
        )
    )
    assert set(n.dados) == {"evento", "tela", "pedido_id", "link", "extra", "chave"}
    assert n.dados["extra"] == "ok"


def test_mesmo_evento_duas_vezes_nao_duplica(servico):
    servico.repo.registrar_dispositivo(ANA, "token-aparelho-1", "android", T0)
    primeira = servico.notificar(Evento.ORCAMENTO_RECEBIDO, ANA, chave="p1")
    segunda = servico.notificar(Evento.ORCAMENTO_RECEBIDO, ANA, chave="p1")
    assert len(primeira) == 3 and segunda == []  # app + push + e-mail, uma vez só
    assert len(servico.repo.listar(ANA, False, 10)) == 1
    outra = servico.notificar(Evento.ORCAMENTO_RECEBIDO, ANA, chave="p2")  # outro fato
    assert len(outra) == 3


def test_preferencia_desligada_nao_cria_notificacao(servico, push):
    servico.repo.registrar_dispositivo(ANA, "token-aparelho-1", "android", T0)
    servico.repo.salvar_preferencias(ANA, {"orcamentos": {"app": False, "push": False}}, T0)
    novas = servico.notificar(Evento.ORCAMENTO_RECEBIDO, ANA, chave="p1")
    assert [n.canal for n in novas] == ["email"]  # só o e-mail (padrão ligado neste teste)
    assert push.enviados == [] and servico.repo.listar(ANA, False, 10) == ()


def test_evento_essencial_sempre_entra_na_caixa_mas_push_obedece(servico, push):
    servico.repo.registrar_dispositivo(ANA, "token-aparelho-1", "android", T0)
    servico.repo.salvar_preferencias(
        ANA, {"pagamentos": {"app": False, "push": False, "email": False}}, T0
    )
    novas = servico.notificar(Evento.PAGAMENTO_CONFIRMADO, ANA, chave="p1", pedido_id="p1")
    assert [n.canal for n in novas] == ["app"]
    assert push.enviados == []


def test_push_vai_para_todos_os_aparelhos_e_marca_enviada(servico, push):
    servico.repo.registrar_dispositivo(ANA, "token-aparelho-1", "android", T0)
    servico.repo.registrar_dispositivo(ANA, "token-aparelho-2", "ios", T0)
    servico.notificar(Evento.AVALIACAO, ANA, chave="p1", pedido_id="p1")
    [msg] = push.enviados
    assert msg.destinos == ("token-aparelho-1", "token-aparelho-2")
    assert servico.repo.pendentes(T0 - timedelta(days=1), 10) == ()


def test_sem_aparelho_ou_sem_email_nem_cria_linha_externa(servico):
    novas = servico.notificar(Evento.AVALIACAO, BIA, chave="p1")  # BIA: sem token e sem e-mail
    assert [n.canal for n in novas] == ["app"]


def test_canal_desligado_e_ignorado(push, email, relogio):
    push.ligado = False
    s = ServicoNotificacoes(
        RepositorioEmMemoria(), Canais(CanalApp(), push, None), cfg(), relogio, EmailsFixos()
    )
    s.repo.registrar_dispositivo(ANA, "token-aparelho-1", "android", T0)
    assert [n.canal for n in s.notificar(Evento.AVALIACAO, ANA, chave="p1")] == ["app"]


def test_reenvio_depois_de_falha(servico, push, relogio):
    servico.repo.registrar_dispositivo(ANA, "token-aparelho-1", "android", T0)
    push.falhar_proximos(2)
    servico.notificar(Evento.AVALIACAO, ANA, chave="p1")
    assert push.enviados == [] and len(servico.repo.pendentes(T0, 10)) == 1
    relogio.agora += timedelta(minutes=5)
    assert servico.reenviar_pendentes() == 0  # ainda fora do ar (2ª falha)
    relogio.agora += timedelta(minutes=5)
    assert servico.reenviar_pendentes() == 1
    assert len(push.enviados) == 1
    assert servico.reenviar_pendentes() == 0  # nada mais pendente: sem envio repetido
    assert len(push.enviados) == 1


def test_reenvio_nao_insiste_depois_da_janela(servico, push, relogio):
    servico.repo.registrar_dispositivo(ANA, "token-aparelho-1", "android", T0)
    push.falhar_proximos(1)
    servico.notificar(Evento.AVALIACAO, ANA, chave="p1")
    relogio.agora += timedelta(hours=25)  # janela padrão: 24 h
    assert servico.reenviar_pendentes() == 0 and push.enviados == []


def test_token_invalido_desativa_o_aparelho(servico, push):
    servico.repo.registrar_dispositivo(ANA, "token-morto-001", "android", T0)
    servico.repo.registrar_dispositivo(ANA, "token-vivo-0001", "android", T0)
    push.tokens_invalidos.add("token-morto-001")
    servico.notificar(Evento.AVALIACAO, ANA, chave="p1")
    assert servico.repo.tokens(ANA) == ("token-vivo-0001",)
    assert servico.reenviar_pendentes() == 1
    assert push.enviados[-1].destinos == ("token-vivo-0001",)


def test_preferencias_efetivas_juntam_padrao_e_escolha(servico):
    servico.repo.salvar_preferencias(ANA, {"disputas": {"push": False}}, T0)
    efetivas = servico.preferencias_efetivas(ANA)
    assert efetivas["disputas"] == {"app": True, "push": False, "email": True}
    assert set(efetivas) == {
        "orcamentos",
        "pagamentos",
        "agenda",
        "execucao",
        "disputas",
        "avaliacoes",
    }


# --- gancho das transições ----------------------------------------------------------------


def test_gancho_de_pagamento_avisa_cliente_e_profissional(servico):
    antes = Pedido("p1", "ana", T0, Estado.AGUARDANDO_CONFIRMACAO, profissional_id="bia")
    gancho = criar_gancho(servico)
    gancho(antes, replace(antes, estado=Estado.PAGO_E_RETIDO), Acao.CONFIRMAR_PAGAMENTO, None)
    gancho(antes, replace(antes, estado=Estado.PAGO_E_RETIDO), Acao.CONFIRMAR_PAGAMENTO, None)
    assert len(servico.repo.listar(ANA, False, 10)) == 1
    assert len(servico.repo.listar(BIA, False, 10)) == 1
    gancho(antes, antes, Acao.REMARCAR, None)  # ação sem evento: ignorada
    assert len(servico.repo.listar(ANA, False, 10)) == 1


# --- adaptadores desligados por padrão ------------------------------------------------------


def test_adaptadores_reais_vem_desligados():
    c = cfg()
    assert not PushFcm(c, lambda *a: 200, lambda: "t").disponivel
    assert not PushApns(c, lambda *a: 200, lambda: "t").disponivel
    assert not EmailSmtp(c).disponivel
    canais = canais_da_config(c)
    assert not canais.push.disponivel and not canais.email.disponivel
    assert canais.por_nome("sms") is None and canais.por_nome("whatsapp") is None


def test_fcm_monta_a_carga_e_trata_token_morto():
    chamadas = []

    def transporte(url, cab, corpo):
        chamadas.append((url, cab, corpo))
        return 404 if corpo["message"]["token"] == "morto" else 200  # noqa: S105

    fcm = PushFcm(cfg(push_ativo=True, fcm_projeto_id="proj"), transporte, lambda: "acesso")
    assert fcm.disponivel
    fcm.enviar(Mensagem(ANA, "Oi", "corpo", {"pedido_id": "p1", "n": 3}, ("vivo",)))
    url, cab, corpo = chamadas[0]
    assert url.endswith("/projects/proj/messages:send") and cab["Authorization"] == "Bearer acesso"
    assert corpo["message"]["data"] == {"pedido_id": "p1", "n": "3"}
    with pytest.raises(Exception, match="inválido") as erro:
        fcm.enviar(Mensagem(ANA, "Oi", None, {}, ("morto",)))
    assert erro.value.token == "morto"  # noqa: S105


def test_apns_monta_carga_e_cabecalhos():
    chamadas = []
    c = cfg(apns_ativo=True, apns_bundle_id="br.com.trato", apns_chave_id="K1")
    apns = PushApns(c, lambda u, h, b: chamadas.append((u, h, b)) or 200, lambda: "jwt")
    apns.enviar(Mensagem(ANA, "Oi", "x", {"a": 1}, ("tk",)))
    url, cab, corpo = chamadas[0]
    assert url.endswith("/3/device/tk") and cab["apns-topic"] == "br.com.trato"
    assert corpo["aps"]["alert"]["title"] == "Oi" and corpo["a"] == "1"


def test_email_smtp_usa_a_fabrica_injetada():
    enviados = []

    class SmtpFalso:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def starttls(self):
            pass

        def login(self, u, s):
            enviados.append(("login", u, s))

        def send_message(self, m):
            enviados.append(("msg", m["To"], m["Subject"]))

    c = cfg(
        email_ativo=True,
        smtp_host="smtp.exemplo.test",
        email_remetente="nao-responda@exemplo.test",
        smtp_usuario="u",
        smtp_senha="senha-de-teste",
    )  # noqa: S106
    EmailSmtp(c, lambda h, p: SmtpFalso()).enviar(
        Mensagem(ANA, "Assunto", "x", {}, ("ana@exemplo.test",))
    )
    assert enviados == [("login", "u", "senha-de-teste"), ("msg", "ana@exemplo.test", "Assunto")]

    class Quebrado(SmtpFalso):
        def send_message(self, m):
            raise smtplib.SMTPException("caiu")

    with pytest.raises(Exception, match="SMTP falhou"):
        EmailSmtp(c, lambda h, p: Quebrado()).enviar(Mensagem(ANA, "A", None, {}, ("x@y.test",)))


def test_sms_so_para_confirmar_celular_e_com_limite():
    fake = SmsFake()
    sms = ServicoSmsConfirmacao(fake, max_envios=2)
    sms.enviar_codigo("+5531999990000", "123456")
    sms.enviar_codigo("+5531999990000", "654321")
    with pytest.raises(LimiteSmsExcedido):
        sms.enviar_codigo("+5531999990000", "111111")
    sms.enviar_codigo("+5531988880000", "222222")  # outro celular tem a própria conta
    assert len(fake.enviados) == 3 and "123456" in fake.enviados[0][1]
    # SMS e WhatsApp não são canais de notificação comum.
    assert Canais().por_nome("sms") is None and Canais().por_nome("whatsapp") is None
