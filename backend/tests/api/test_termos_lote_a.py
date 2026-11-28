# ruff: noqa: F811
"""BE-LOTE-A: Termos 11.8, 15.3, 13.4/I.5, 5.2, 1.4 e 10.2."""

from __future__ import annotations

from dataclasses import replace
from datetime import timedelta

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401
from conftest import AGORA, CLIENTE, PROFISSIONAL
from conftest import cab as cab_app
from test_agendador import montar
from test_avaliacoes_moderacao import semear_avaliacoes
from test_busca_disponivel_agora import _semear

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.moedas import LancamentoMoeda
from trato.api.tratinhos_vencimento import antecedencia_dias, avisar_vencimentos
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado

D = timedelta(days=1)
OCULTAR = {"motivo": "dados_pessoais", "explicacao": "Nota interna do analista, não vai."}


def notificador(contexto, cliente, relogio):
    repo = RepositorioEmMemoria()
    servico = ServicoNotificacoes(
        repo, Canais(CanalApp()), ConfigNotificacoes(_env_file=None), relogio
    )
    ligar_ao_contexto(cliente.app, contexto, servico)
    return repo, servico


def avisos(repo, usuario, evento):
    return [r for r in repo.listar(usuario, False, 100) if r.dados["evento"] == evento]


# --- 11.8 -----------------------------------------------------------------------------------


def test_ocultar_avisa_o_autor_uma_vez_sem_a_nota_do_analista(adm):
    _, av = semear_avaliacoes(adm)
    repo, _ = notificador(adm.contexto, adm.cliente, adm.contexto.agora)
    h = cab(token_de("mediador"))
    url = f"/v1/admin/avaliacoes/{av}"
    r = adm.cliente.post(f"{url}/ocultar", json=OCULTAR, headers=h)
    assert r.status_code == 201, r.text
    assert r.json()["autor_avisado_em"] is not None
    assert adm.cliente.post(f"{url}/ocultar", json=OCULTAR, headers=h).status_code == 409
    again = adm.cliente.post(f"{url}/avisar-autor", headers=h)
    assert again.json()["autor_avisado_em"] == r.json()["autor_avisado_em"]
    (aviso,) = avisos(repo, CLIENTE.id, "conta.avaliacao_ocultada")
    assert "exposição de dados pessoais" in aviso.corpo and "contestar" in aviso.corpo
    assert "Nota interna" not in aviso.corpo
    assert avisos(repo, PROFISSIONAL.id, "conta.avaliacao_ocultada") == []


def test_aviso_adiado_exige_justificativa_e_sai_depois(adm):
    _, av = semear_avaliacoes(adm)
    repo, _ = notificador(adm.contexto, adm.cliente, adm.contexto.agora)
    h = cab(token_de("mediador"))
    url = f"/v1/admin/avaliacoes/{av}"
    sem = adm.cliente.post(f"{url}/ocultar", json={**OCULTAR, "adiar_aviso": True}, headers=h)
    assert sem.status_code == 422
    corpo = {
        **OCULTAR,
        "adiar_aviso": True,
        "justificativa_adiamento": "Avisar agora atrapalha a apuração de crime.",
    }
    r = adm.cliente.post(f"{url}/ocultar", json=corpo, headers=h)
    assert r.status_code == 201 and r.json()["autor_avisado_em"] is None
    assert avisos(repo, CLIENTE.id, "conta.avaliacao_ocultada") == []
    depois = adm.cliente.post(f"{url}/avisar-autor", headers=h)
    assert depois.status_code == 200 and depois.json()["autor_avisado_em"] is not None
    assert len(avisos(repo, CLIENTE.id, "conta.avaliacao_ocultada")) == 1
    acoes = [e.acao for e in adm.admin.auditoria.listar(FiltroAuditoria(), 50, 0)[0]]
    assert "avaliacao.autor_avisado" in acoes


def test_ocultacao_pela_revisao_tambem_avisa(adm):
    _, av = semear_avaliacoes(adm)
    repo, _ = notificador(adm.contexto, adm.cliente, adm.contexto.agora)
    pedido = adm.cliente.post(
        f"/v1/avaliacoes/{av}/revisoes",
        json={"justificativa": "O comentário contém ofensas pessoais previstas na 12.6."},
        headers=cab("t-prof"),
    ).json()
    r = adm.cliente.post(
        f"/v1/admin/avaliacoes/revisoes/{pedido['id']}/decidir",
        json={
            "status": "aceita",
            "resposta": "Revisão aceita após análise.",
            "ocultar_motivo": "ofensa_ou_ilegal",
        },
        headers=cab(token_de("mediador")),
    )
    assert r.status_code == 200, r.text
    assert len(avisos(repo, CLIENTE.id, "conta.avaliacao_ocultada")) == 1


# --- 15.3 -----------------------------------------------------------------------------------


def test_conclusao_por_prazo_avisa_as_duas_partes_uma_vez(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 8 * D)
    agendador, notif, _ = montar(amb)
    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    for usuario in (CLIENTE.id, PROFISSIONAL.id):
        assert len(avisos(notif.repo, usuario, "execucao.janela_encerrada")) == 1


def test_dentro_da_janela_nao_avisa_encerramento(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - timedelta(hours=1))
    agendador, notif, _ = montar(amb)
    agendador.rodar_uma_vez()
    assert avisos(notif.repo, CLIENTE.id, "execucao.janela_encerrada") == []


# --- 13.4 e I.5 -----------------------------------------------------------------------------


def creditar(amb, chave, quantidade, vence_em, carteira="cliente", usuario=CLIENTE.id):
    amb.contexto.moedas.lancar(
        LancamentoMoeda(
            usuario,
            "bonus_avaliacao",
            quantidade,
            chave,
            AGORA - 30 * D,
            expira_em=vence_em,
            carteira=carteira,
        )
    )


def vencendo(repo, usuario=CLIENTE.id):
    return avisos(repo, usuario, "pagamento.tratinhos_vencendo")


def test_aviso_de_vencimento_na_borda_dos_7_dias_e_sem_repetir(amb):
    repo, notif = notificador(amb.contexto, amb.cliente, amb.relogio)
    creditar(amb, "a", 40, AGORA + 7 * D)
    creditar(amb, "b", 99, AGORA + 7 * D + timedelta(seconds=1))
    creditar(amb, "c", 5, AGORA)  # já venceu
    assert avisar_vencimentos(amb.contexto, notif, AGORA) == 1
    assert avisar_vencimentos(amb.contexto, notif, AGORA) == 0
    (aviso,) = vencendo(repo)
    assert "40 Tratinhos" in aviso.corpo


def test_aviso_conta_so_o_que_sobrou_e_separa_carteiras(amb):
    repo, notif = notificador(amb.contexto, amb.cliente, amb.relogio)
    creditar(amb, "a", 40, AGORA + 3 * D)
    amb.contexto.moedas.lancar(LancamentoMoeda(CLIENTE.id, "uso", -40, "u", AGORA - D))
    creditar(amb, "p", 10, AGORA + 3 * D, "profissional", PROFISSIONAL.id)
    assert avisar_vencimentos(amb.contexto, notif, AGORA) == 1
    assert vencendo(repo) == []
    assert vencendo(repo, PROFISSIONAL.id)[0].dados["carteira"] == "profissional"


@pytest.mark.parametrize(("publicado", "esperado"), [(15, 1), (2, 1), (7, 0), (90, 1)])
def test_antecedencia_configuravel_nunca_abaixo_de_7(amb, publicado, esperado):
    _, notif = notificador(amb.contexto, amb.cliente, amb.relogio)
    atual = amb.contexto.config.carregar()
    novo = replace(atual, tratinhos_aviso_vencimento_dias=publicado)
    amb.contexto.config.carregar = lambda: novo
    creditar(amb, "a", 40, AGORA + (6 if publicado == 2 else 10) * D)
    assert avisar_vencimentos(amb.contexto, notif, AGORA) == esperado


def test_rotina_entra_no_ciclo(amb):
    vistos = []
    agendador, _, _ = montar(amb, rotina_vencimento_moedas=lambda a: vistos.append(a) or 0)
    agendador.rodar_uma_vez()
    assert vistos == [AGORA]


# --- 5.2 ------------------------------------------------------------------------------------

COMPLETO = {
    "itens": [
        {"tipo": "outro", "descricao": "Pintar", "quantidade": 1, "valor_unitario_centavos": 9000}
    ],
    "prazo_execucao_dias": 3,
    "validade_ate": "2099-01-01T00:00:00Z",
    "fora_do_escopo": "Materiais não incluídos.",
    "garantia_dias": 90,
}


@pytest.mark.parametrize("campo", ["prazo_execucao_dias", "validade_ate", "garantia_dias"])
@pytest.mark.parametrize("como", ["ausente", "nulo"])
def test_orcamento_sem_campo_obrigatorio_da_422(amb, campo, como):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    corpo = dict(COMPLETO)
    if como == "ausente":
        del corpo[campo]
    else:
        corpo[campo] = None
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=corpo, headers=cab_app("t-prof"))
    assert r.status_code == 422 and campo in r.text


# --- 10.2 -----------------------------------------------------------------------------------


def test_data_do_selo_nas_rotas_de_catalogo(amb):
    _semear(amb)
    modulo = amb.cliente.app.state.modulo_profissional
    for uid, nivel in (("pro-on", "verificado"), ("pro-off", "basico")):
        modulo.repo.salvar(replace(modulo.repo.obter(uid), nivel_verificacao=nivel))
    amb.contexto.usuarios.selos = {"pro-on": AGORA, "pro-off": AGORA}
    h = cab_app("t-cliente")
    itens = {i["id"]: i for i in amb.cliente.get("/v1/profissionais", headers=h).json()["itens"]}
    assert itens["pro-on"]["selo_conferido_em"] is not None
    assert itens["pro-off"]["selo_conferido_em"] is None  # sem selo, sem data
    perfil = amb.cliente.get("/v1/profissionais/pro-on", headers=h)
    assert perfil.json()["selo_conferido_em"] == itens["pro-on"]["selo_conferido_em"]


def test_antecedencia_tem_teto_de_30_dias(amb):
    atual = amb.contexto.config.carregar()
    novo = replace(atual, tratinhos_aviso_vencimento_dias=365)
    amb.contexto.config.carregar = lambda: novo
    assert antecedencia_dias(amb.contexto) == 30
