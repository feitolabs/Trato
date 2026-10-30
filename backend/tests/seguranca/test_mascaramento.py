"""F8.1: telefone, e-mail, link, perfil e endereço somem do chat; conversa normal passa."""

from __future__ import annotations

import pytest

from trato.persistencia.conversas import mascarar_contatos
from trato.seguranca.config import ConfigSeguranca
from trato.seguranca.mascaramento import AVISO_MASCARA, mascarar

CFG = ConfigSeguranca(_env_file=None)

ESCONDE = [
    ("me liga 11 98765-4321", "telefone"),
    ("+55 (11) 98765-4321", "telefone"),
    ("11987654321", "telefone"),
    ("1 1 9 8 7 6 5 4 3 2 1", "telefone"),
    ("onze nove oito sete seis cinco quatro três dois um", "telefone"),
    ("nove oito sete seis cinco quatro três dois um", "telefone"),
    ("meu zap é 98 7654-321", "telefone"),
    ("９８７６５４３２１", "telefone"),  # dígitos largos
    ("9️⃣8️⃣7️⃣6️⃣5️⃣4️⃣3️⃣2️⃣1️⃣", "telefone"),  # emojis de teclado
    ("(11).9.8.7.6.5.4.3.2.1", "telefone"),
    ("joao@gmail.com", "email"),
    ("joao arroba gmail ponto com", "email"),
    ("joao @ gmail . com", "email"),
    ("fulano [at] provedor [dot] com.br", "email"),
    ("joao at gmail dot com", "email"),
    ("fale com joao(at)gmail(dot)com", "email"),
    ("veja www.meusite.com.br/orcamento", "link"),
    ("https://wa.me/5511987654321", "link"),
    ("meusite ponto com ponto br", "link"),
    ("chama no t.me/joaoeletrica", "link"),
    ("meu insta é joao_eletrica", "rede_social"),
    ("me acha em @joaoeletrica", "rede_social"),
    ("Rua das Flores, 123", "endereco"),
    ("moro na Av. Brasil nº 1500", "endereco"),
    ("cep 01310-100", "telefone"),  # 8 dígitos: cai como contato, mas some
]

PASSA = [
    "Bom dia! Posso ir amanhã às 14h30.",
    "O orçamento ficou em R$ 1.500,00 com material.",
    "R$ 12.345.678,90",
    "Preciso de 3 tomadas e 2 interruptores.",
    "Serviço agendado para 15/03/2026.",
    "15.03.2026 está bom?",
    "Tenho 12 anos de experiência e faço em 2 dias.",
    "Nesse ponto com certeza dá para resolver.",
    "O instagram é muito usado, mas aqui vale o chat.",
    "A parede tem 4 metros por 2,5 metros.",
    "Vou levar dez dias para terminar.",
    "pode ser na rua mesmo, perto da padaria",
    "ok",
    "",
]


@pytest.mark.parametrize(("texto", "categoria"), ESCONDE)
def test_esconde_contato(texto: str, categoria: str):
    r = mascarar(texto, CFG)
    assert r.mascarada, texto
    assert AVISO_MASCARA in r.exibido
    assert categoria in r.categorias, (texto, r.categorias)
    assert r.original == texto  # o original é preservado para guardar em `corpo`


@pytest.mark.parametrize("texto", PASSA)
def test_conversa_normal_nao_e_mexida(texto: str):
    r = mascarar(texto, CFG)
    assert not r.mascarada, (texto, r.exibido)
    assert r.exibido == texto


def test_nenhum_digito_do_telefone_vaza():
    r = mascarar("onze nove oito sete seis cinco quatro três dois um, ou 11 98765-4321", CFG)
    assert "onze" not in r.exibido
    assert "98765" not in r.exibido


def test_misturado_mantem_o_resto_da_frase():
    r = mascarar("Fechado por R$ 800,00. Meu fone: 11 98765-4321, até amanhã!", CFG)
    assert "R$ 800,00" in r.exibido
    assert "até amanhã!" in r.exibido
    assert "98765" not in r.exibido


def test_limite_de_digitos_vem_da_configuracao():
    estrito = ConfigSeguranca(_env_file=None, mascara_min_digitos=5)
    assert mascarar("código 12345", estrito).mascarada
    assert not mascarar("código 12345", CFG).mascarada


def test_texto_enorme_nao_trava():
    assert mascarar("1 " * 5000 + "x" * 5000, CFG).mascarada


def test_funcao_antiga_continua_funcionando():
    assert mascarar_contatos("joao@gmail.com") == AVISO_MASCARA
    assert mascarar_contatos("oi, tudo bem?") == "oi, tudo bem?"
