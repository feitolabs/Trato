"""B43: contato escondido no chat SEMPRE, antes e depois da contratação, com burlas comuns."""

from __future__ import annotations

import pytest
from conftest import cab

from trato.pedidos.estados import Estado
from trato.seguranca.mascaramento import AVISO_MASCARA, mascarar

BURLAS = [
    # telefone: com e sem DDD / +55, espaços, pontos, barras, vírgulas, extenso
    "meu numero 11987654321",
    "(11) 98765-4321",
    "+55 11 98765-4321",
    "+5511987654321",
    "11 9 8765 4321",
    "11.98765.4321",
    "98765-4321",
    "9876-5432",
    "9 8 7 6 5 4 3 2 1",
    "9-8-7-6-5-4-3-2",
    "98765/4321",
    "11/98765/4321",
    "98765|4321",
    "9,8,7,6,5,4,3,2,1",
    "nove oito sete seis cinco quatro três dois um",
    "nove, oito, sete, seis, cinco, quatro, tres, dois",
    "onze nove oito sete seis cinco quatro tres dois um",
    "9 oito 7 seis 5 quatro 3 dois 1",
    "noventa e oito setenta e seis cinquenta e quatro trinta e dois",
    "chama no zap 98765432",
    "meu zap: 8765 4321",
    # e-mail
    "joao@gmail.com",
    "joao arroba gmail ponto com",
    "joao (at) gmail (dot) com",
    "joao @ gmail . com",
    "joao[arroba]gmail[ponto]com",
    # @usuário e redes
    "me acha no @joaosilva",
    "@joao_pintor",
    "@jps",
    "insta joao_silva",
    "meu insta é joaopintor",
    "instagram: joaops",
    "ig: joao.silva",
    "face joao.pintor22",
    # links externos
    "www.joaopintor.com.br",
    "http://x.io/a",
    "wa.me/5511987654321",
    "t.me/joao",
    "bit.ly/abc123",
    "joaopintor.com",
    "meusite ponto com ponto br",
    "joaopintor . com . br",
]

CONVERSA_NORMAL = [
    "O serviço fica R$ 1.500,00",
    "são 12,50 por metro",
    "Visita confirmada para 24/11/2026 das 14:00 às 16:00",
    "pode ser dia 25 às 9h",
    "a parede tem 3,5 x 2,8 metros",
    "são 2 quartos e 1 sala",
    "chego em 15 minutos",
    "o pedido PED-1042 ficou ok",
    "apto 1203 bloco 2",
    "código 4821",
    "preciso de 20 litros e 2 latas de 18",
    "entre 8 e 10 horas",
    "R$ 90.000",
    "são 150 reais ou 3x de 50",
    "um dois três testando",
    "voltagem 220/110",
    "safra 2025/2026",
    "janela 120x100",
    "nota 4.8 ok",
    "ponto de tomada novo, com fio",
    "olha a face da parede",
]


@pytest.mark.parametrize("texto", BURLAS)
def test_burla_e_escondida(texto):
    for com_endereco in (True, False):  # antes e depois da contratação
        resultado = mascarar(texto, incluir_endereco=com_endereco)
        assert AVISO_MASCARA in resultado.exibido, (texto, resultado.exibido)


@pytest.mark.parametrize("texto", CONVERSA_NORMAL)
def test_conversa_normal_passa(texto):
    assert mascarar(texto, incluir_endereco=False).exibido == texto


def test_endereco_so_e_escondido_antes_da_contratacao():
    texto = "Moro na Rua das Flores, 123"
    assert AVISO_MASCARA in mascarar(texto).exibido
    assert mascarar(texto, incluir_endereco=False).exibido == texto


def _conversar(amb, texto):
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens", json={"texto": texto}, headers=cab("t-cliente")
    )
    assert r.status_code == 201, r.text
    lidas = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-prof")).json()
    itens = lidas["itens"] if isinstance(lidas, dict) else lidas
    return itens[-1]


def test_depois_de_contratado_so_o_telefone_passa_na_rota_do_chat(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)  # pagamento confirmado (Termos 5.3 e 11.2)
    msg = _conversar(amb, "Me liga no (11) 98765-4321 ou joao@gmail.com")
    assert "98765-4321" in msg["texto"] and "gmail" not in msg["texto"]
    assert AVISO_MASCARA in msg["texto"] and msg["mascarada"] is True


def test_depois_de_contratado_o_endereco_passa(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    msg = _conversar(amb, "Pode vir na Rua das Flores, 123")
    assert msg["texto"] == "Pode vir na Rua das Flores, 123" and msg["mascarada"] is False


# --- BUG-C12: rede social solta e dígitos isolados ------------------------------------------

NOVAS_BURLAS = [
    "ig fulano",
    "insta fulano",
    "me chama no ig fulano",
    "nove nove oito oito sete sete",
    "9 9 8 8 7 7",
    "IG FULANO",
    "Insta Fulano",
    "NOVE NOVE OITO OITO SETE SETE",
    "i g fulano",
    "insta: fulano",
    "zap nove nove oito oito sete sete",
    "Zap 9 9 8 8 7 7",
    "9.9.8.8.7.7",
    "9-9-8-8-7-7",
    "9 nove 8 oito 7 sete",
    "noventa e nove oitenta e oito setenta e sete",
    "meu zap 9 9 8 8",
    "fone 9988",
    "ligar 9988",
    "meu número é 9 9 8 8",
    "chama no whats fulano22",
    "whatsapp fulanodetal",
    "facebook joaopintor",
    "tiktok joaopintor",
    "x.com/@fulano",
]

NOVAS_NORMAIS = [
    "na insta de ontem eu vi",
    "o ig caiu hoje",
    "são 3 dias, 2 horas e 5 minutos",
    "apartamento 12, bloco 3",
    "R$ 150 e 50 de material",
    "dia 25 às 9 e 30",
    "olha a face da parede",
    "o número do apto é 1203",
    "código 4821",
    "o insta é bom",
    "o whatsapp está lento",
    "pedido 123456 ok",
    "chego em 2 ou 3 dias",
    "são 12 3 4 horas",
    "1 2 3 4 5",
    "o zap tá fora do ar",
    "o instagram não abriu",
    "Moro na Rua das Flores, 123 CEP 35500-001",
    "CEP 35500-001",
    "35500-001",
]


@pytest.mark.parametrize("texto", NOVAS_BURLAS)
def test_nova_burla_e_escondida(texto):
    for com_endereco in (True, False):
        assert AVISO_MASCARA in mascarar(texto, incluir_endereco=com_endereco).exibido, texto


@pytest.mark.parametrize("texto", NOVAS_NORMAIS)
def test_nova_conversa_normal_passa_depois_da_contratacao(texto):
    assert mascarar(texto, incluir_endereco=False).exibido == texto


def test_cep_e_escondido_antes_da_contratacao_e_passa_depois():
    assert AVISO_MASCARA in mascarar("CEP 35500-001").exibido
    assert mascarar("CEP 35500-001", incluir_endereco=False).exibido == "CEP 35500-001"
    # telefone com 5-4 continua escondido nos dois casos
    assert AVISO_MASCARA in mascarar("98765-4321", incluir_endereco=False).exibido


def test_4_ou_5_digitos_so_com_palavra_de_contato():
    assert AVISO_MASCARA in mascarar("zap 9988 7").exibido
    assert mascarar("sala 9 9 8 8").exibido == "sala 9 9 8 8"
    assert mascarar("apto 9 9 8 8 7").exibido == "apto 9 9 8 8 7"


def test_rota_do_chat_esconde_rede_social_depois_de_contratado(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    assert AVISO_MASCARA in _conversar(amb, "me chama no ig fulano")["texto"]
    assert _conversar(amb, "9 9 8 8 7 7")["texto"] == "9 9 8 8 7 7"  # telefone: liberado (11.2)
    assert _conversar(amb, "o ig caiu hoje")["texto"] == "o ig caiu hoje"
