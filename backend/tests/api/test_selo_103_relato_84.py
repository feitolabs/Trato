"""BE-SELO-103-RELATO-84: retirada, reconferência e regularização do selo (10.3) e o resultado
esperado no Relato (8.4). Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace

from conftest import PROFISSIONAL, cab
from test_exclusividade import _pedido
from test_exclusividade_cliente import ligar, pedir
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401
from test_orcamentos_do_profissional_e_papel import ORC, _aberto, _post

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.repositorios_app import PerfilDetalhe

URL = f"/v1/admin/profissionais/{PROFISSIONAL.id}/selo"
MOTIVO = "A conferência de identidade falhou."


def preparar(amb, nivel="verificado") -> None:
    atual = amb.contexto.usuarios.detalhe(PROFISSIONAL.id) or PerfilDetalhe(
        PROFISSIONAL.id, "Pessoa", PROFISSIONAL.papel
    )
    amb.contexto.usuarios.adicionar(replace(atual, nivel_verificacao=nivel))
    amb.contexto.usuarios.tem_perfil_profissional = lambda uid: uid == PROFISSIONAL.id


def chamar(amb, acao, quem="t-cadastro", chave="chave-0001", motivo=MOTIVO, url=URL):
    corpo = {"motivo": motivo, "chave_idempotencia": chave}
    return amb.cliente.post(f"{url}/{acao}", json=corpo, headers=cab(quem))


def nivel(amb) -> str:
    return amb.contexto.usuarios.detalhe(PROFISSIONAL.id).nivel_verificacao


class Avisos:
    def __init__(self):
        self.corpos = []

    def notificar(self, evento, usuario, **kw):
        self.corpos.append((evento.value, usuario, kw["corpo"]))


def test_retira_uma_vez_audita_avisa_e_regulariza(amb):
    preparar(amb, "verificado_plus")
    avisos = amb.contexto.extras["notificador"] = Avisos()
    with ThreadPoolExecutor(4) as grupo:
        respostas = list(grupo.map(lambda _: chamar(amb, "retirar", "t-seguranca"), range(4)))
    assert {r.status_code for r in respostas} == {200}, [r.text for r in respostas]
    assert sorted(r.json()["resultado"] for r in respostas) == ["ja_existe"] * 3 + ["ok"]
    assert nivel(amb) == "basico" and respostas[0].json()["retirada_aberta"] is True
    assert chamar(amb, "retirar", chave="chave-0002").status_code == 409  # sem selo
    ((tipo, usuario, corpo),) = avisos.corpos
    assert tipo == "conta.selo_retirado" and usuario == PROFISSIONAL.id
    assert MOTIVO in corpo and "contestar" in corpo
    assert chamar(amb, "regularizar", "t-seguranca", "chave-0003").status_code == 403
    r = chamar(amb, "regularizar", chave="chave-0003")
    assert r.status_code == 200 and r.json()["retirada_aberta"] is False, r.text
    assert r.json()["nivel_verificacao"] == nivel(amb) == "verificado_plus"
    assert chamar(amb, "regularizar", chave="chave-0004").status_code == 409
    acoes = [e.acao for e in amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)[0]]
    assert sorted(a for a in acoes if a.startswith("profissional.selo")) == [
        "profissional.selo_regularizado",
        "profissional.selo_retirado",
    ]


def test_permissoes_validacoes_e_chave(amb):
    preparar(amb)
    for quem in ("t-mediador", "t-cliente", "t-prof"):
        assert chamar(amb, "retirar", quem).status_code == 403, quem
    assert chamar(amb, "retirar", motivo="curto").status_code == 422
    for sensivel in ("CPF 123.456.789-09 não confere.", "Ligar para (11) 98765-4321 hoje."):
        assert chamar(amb, "retirar", motivo=sensivel).status_code == 422, sensivel
    outro = "/v1/admin/profissionais/nao-existe/selo"
    assert chamar(amb, "retirar", url=outro).status_code == 404
    r = chamar(amb, "reconferencia", "t-seguranca")
    assert r.status_code == 200 and nivel(amb) == "verificado", r.text
    assert chamar(amb, "retirar").status_code == 422  # chave de outra operação
    assert nivel(amb) == "verificado"


def test_sem_a_tabela_responde_503(amb):
    preparar(amb)
    amb.contexto.selos.disponivel = lambda: False
    assert chamar(amb, "retirar").status_code == 503 and nivel(amb) == "verificado"


def test_sem_selo_nao_envia_orcamento_ate_regularizar(amb):
    _aberto(amb)
    preparar(amb)
    assert chamar(amb, "retirar").status_code == 200
    url = "/v1/pedidos/ped-1/orcamentos"
    r = _post(amb, url, "t-prof", ORC)
    assert r.status_code == 409 and r.json()["codigo"] == "selo_retirado", r.text
    assert not amb.contexto.orcamentos.do_pedido("ped-1")
    assert chamar(amb, "regularizar", chave="chave-0002").status_code == 200
    assert _post(amb, url, "t-prof", ORC).status_code < 300


def test_cliente_nao_reserva_exclusividade_com_selo_retirado(amb):
    ligar(amb)
    _pedido(amb)
    preparar(amb)
    assert chamar(amb, "retirar").status_code == 200
    r = pedir(amb)
    assert r.status_code >= 400 and r.json()["codigo"] == "profissional_indisponivel", r.text


def abrir(f, pid, **extra):
    corpo = {"motivo": "mal_feito", "descricao": "A pintura ficou manchada."} | extra
    return f.chamar("POST", f"/v1/pedidos/{pid}/disputa", "t-cliente", corpo)


def test_relato_guarda_o_resultado_esperado_e_continua_opcional(fluxo):
    pid = fluxo.ate_em_confirmacao()
    assert abrir(fluxo, pid, resultado_esperado="outro").status_code == 422
    r = abrir(fluxo, pid, resultado_esperado="reembolso_parcial")
    assert r.status_code < 300 and r.json()["resultado_esperado"] == "reembolso_parcial", r.text
    visto = fluxo.chamar("GET", f"/v1/pedidos/{pid}/disputa", "t-prof").json()
    assert visto["resultado_esperado"] == "reembolso_parcial"
    outro = fluxo.ate_em_confirmacao()
    r = abrir(fluxo, outro)
    assert r.status_code < 300 and r.json()["resultado_esperado"] is None, r.text
