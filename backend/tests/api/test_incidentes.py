"""TERMOS-BE-INCID (8.8, 9.3 a 9.6): rotas do painel para incidentes e denúncia por dano.
Memória."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import datetime, timedelta

import pytest
from conftest import AGORA, MEMBROS_EQUIPE, cab
from test_agendador import montar
from test_liberacao_automatica import concluido, repasses, saldo

from trato.api.admin.papeis import MATRIZ, PapelEquipe, Permissao
from trato.api.admin.repositorios import FiltroAuditoria

URL = "/v1/admin/incidentes"
QUEM = "t-seguranca"
NOVO = {
    "tipo": "acidente_dano",
    "descricao": "Vidro quebrado durante o serviço.",
    "contato": "11 99999-0000",
    "canal": "telefone",
    "pedido_id": "ped-1",
}
DESFECHO = "Apurado e resolvido com as partes."


def post(amb, caminho="", corpo=None, quem=QUEM):
    return amb.cliente.post(URL + caminho, json=corpo, headers=cab(quem))


def get(amb, caminho="", quem=QUEM, **filtros):
    return amb.cliente.get(URL + caminho, params=filtros, headers=cab(quem))


def aberto(amb, **extra) -> str:
    r = post(amb, corpo=NOVO | extra)
    assert r.status_code == 201, r.text
    return r.json()["id"]


def acoes(amb) -> list[str]:
    entradas, _ = amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)
    return sorted(e.acao.removeprefix("seguranca.incidente_") for e in entradas)


def encerrar(amb, iid, desfecho=DESFECHO, quem=QUEM):
    return post(amb, f"/{iid}/encerrar", {"desfecho": desfecho}, quem)


def test_ciclo_completo_com_prazo_auditoria_e_sem_mover_dinheiro(amb):
    concluido(amb)
    antes = saldo(amb)
    r = post(amb, corpo=NOVO)
    assert r.status_code == 201, r.text
    dados = r.json()
    assert dados["status"] == "aberto" and dados["protocolo"].startswith("INC-2026-")
    assert datetime.fromisoformat(dados["cautela_ate"]) == AGORA + timedelta(hours=24)
    assert dados["medidas"] == [] and dados["responsavel_id"] is None
    iid = dados["id"]
    cautela = {"status": "cautela_adotada"}
    assert post(amb, f"/{iid}/status", cautela).status_code == 409  # sem medida
    medida = {"tipo": "reter_valor", "descricao": "Valor retido até a análise."}
    r = post(amb, f"/{iid}/medidas", medida)
    assert r.status_code == 200 and r.json()["medidas"][0]["origem"] == "analista"
    r = post(amb, f"/{iid}/status", cautela)
    assert r.json()["status"] == "cautela_adotada" and r.json()["cautela_adotada_em"]
    r = post(amb, f"/{iid}/status", {"status": "em_apuracao"})
    assert r.json()["status"] == "em_apuracao" and r.json()["cautela_adotada_em"]
    r = encerrar(amb, iid)
    assert r.status_code == 200, r.text
    assert (r.json()["status"], r.json()["desfecho"]) == ("encerrado", DESFECHO)
    assert r.json()["responsavel_id"] == MEMBROS_EQUIPE[QUEM].usuario_id
    assert saldo(amb) == antes
    assert get(amb, f"/{iid}").json()["encerrado_em"]
    lista = get(amb, status="encerrado", pedido_id="ped-1").json()
    assert lista["total"] == 1 and lista["itens"][0]["id"] == iid
    assert get(amb, status="aberto").json() == {
        "itens": [], "total": 0, "limite": 20, "deslocamento": 0
    }  # fmt: skip
    assert acoes(amb) == sorted(
        ["aberto", "medida", "andamento", "andamento", "encerrado", "consultado"]
        + ["lista_consultada"] * 2
    )
    entradas, _ = amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)
    assert NOVO["contato"] not in str(entradas) and NOVO["descricao"] not in str(entradas)


def test_repeticao_nao_duplica(amb):
    concluido(amb)
    iid = aberto(amb)
    r = post(amb, corpo=NOVO)
    assert r.status_code == 200 and r.json()["id"] == iid
    medida = {"tipo": "preservar_registros", "descricao": "Registros preservados."}
    for _ in range(2):
        assert len(post(amb, f"/{iid}/medidas", medida).json()["medidas"]) == 1
    for _ in range(2):
        assert post(amb, f"/{iid}/status", {"status": "em_apuracao"}).status_code == 200
    primeiro = encerrar(amb, iid).json()
    amb.relogio.avancar(hours=1)
    segundo = encerrar(amb, iid)
    assert segundo.status_code == 200 and segundo.json() == primeiro
    assert encerrar(amb, iid, "Outro desfecho diferente.").status_code == 409
    assert post(amb, f"/{iid}/medidas", medida).status_code == 409
    assert post(amb, f"/{iid}/status", {"status": "em_apuracao"}).status_code == 409
    assert acoes(amb) == ["aberto", "andamento", "encerrado", "medida"]


def test_oito_toques_juntos_um_incidente_e_um_encerramento(amb):
    concluido(amb)
    respostas = []

    def juntos(funcao):
        respostas.clear()
        threads = [threading.Thread(target=lambda: respostas.append(funcao())) for _ in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

    juntos(lambda: post(amb, corpo=NOVO))
    assert sorted(r.status_code for r in respostas) == [200] * 7 + [201]
    iid = respostas[0].json()["id"]
    juntos(lambda: encerrar(amb, iid))
    assert {r.status_code for r in respostas} == {200}
    assert acoes(amb) == ["aberto", "encerrado"]


@pytest.mark.parametrize(
    "mudanca,status",
    [
        ({"contato": "  "}, 422),
        ({"canal": "carta"}, 422),
        ({"tipo": "pessoa_diferente", "pedido_id": None}, 422),
        ({"pedido_id": "nao-existe"}, 404),
        ({"envolvido_id": "pro-1"}, 422),
    ],
)
def test_entrada_invalida(amb, mudanca, status):
    concluido(amb)
    assert post(amb, corpo=NOVO | mudanca).status_code == status


def test_suspender_conta_e_desfecho_curto_recusados(amb):
    concluido(amb)
    iid = aberto(amb)
    medida = {"tipo": "suspender_conta", "descricao": "Suspender."}
    assert post(amb, f"/{iid}/medidas", medida).status_code == 422
    assert encerrar(amb, iid, "  curto    ").status_code == 422
    assert encerrar(amb, "nao-existe").status_code == 404


@pytest.mark.parametrize("horas,esperado", [(2, 2), (24, 24)])
def test_prazo_de_cautela_vem_da_configuracao(amb, horas, esperado):
    concluido(amb)
    config = amb.contexto.config
    config._config = replace(config.carregar(), incidente_seguranca_cautela_horas=horas)
    r = post(amb, corpo=NOVO).json()
    assert datetime.fromisoformat(r["cautela_ate"]) == AGORA + timedelta(hours=esperado)


def test_permissoes_por_papel():
    def com(permissao):
        return {p for p, perms in MATRIZ.items() if permissao in perms}

    quatro = {
        PapelEquipe.MEDIADOR,
        PapelEquipe.LIDER_SUPORTE,
        PapelEquipe.SEGURANCA,
        PapelEquipe.ADMINISTRADOR,
    }
    assert com(Permissao.INCIDENTES_VER) == com(Permissao.INCIDENTES_TRATAR) == quatro
    assert com(Permissao.INCIDENTES_ENCERRAR) == quatro - {PapelEquipe.MEDIADOR}


def test_mediador_trata_mas_nao_encerra_e_os_demais_nem_veem(amb):
    concluido(amb)
    r = post(amb, corpo=NOVO, quem="t-mediador")
    assert r.status_code == 201
    assert encerrar(amb, r.json()["id"], quem="t-mediador").status_code == 403
    for quem in ("t-n1", "t-financeiro", "t-cliente", "t-prof"):
        assert get(amb, quem=quem).status_code == 403
        assert post(amb, corpo=NOVO, quem=quem).status_code == 403


def test_sem_as_tabelas_503_sem_quebrar_o_resto(amb, monkeypatch):
    concluido(amb)
    monkeypatch.setattr(amb.contexto.incidentes, "disponivel", lambda: False)
    for r in (get(amb), post(amb, corpo=NOVO), encerrar(amb, "x")):
        assert r.status_code == 503 and "tabelas" in r.json()["detail"]
    assert montar(amb)[0].rodar_uma_vez().executadas == 1


def test_incidente_retem_e_encerrar_solta_uma_vez(amb):
    concluido(amb)
    iid = aberto(amb)
    agendador, _, _ = montar(amb)
    assert agendador.rodar_uma_vez().executadas == 0 and repasses(amb) == 0
    assert encerrar(amb, iid).status_code == 200
    assert agendador.rodar_uma_vez().executadas == 1
    assert encerrar(amb, iid).status_code == 200
    assert agendador.rodar_uma_vez().executadas == 0 and repasses(amb) == 1


def denunciar_dano(amb):
    corpo = {
        "alvo_tipo": "chat",
        "denunciado_id": "pro-1",
        "pedido_id": "ped-1",
        "motivo": "dano",
        "detalhes": "Quebrou o vidro da sala.",
    }
    return amb.cliente.post("/v1/denuncias", json=corpo, headers=cab("t-cliente"))


def test_encerrar_nao_solta_com_outra_trava_ate_resolver_a_denuncia_de_dano(amb):
    concluido(amb)
    assert denunciar_dano(amb).status_code == 201
    (alerta,) = amb.contexto.denuncias.alertas.values()
    assert alerta.severidade == "alta"
    iid = aberto(amb)
    assert encerrar(amb, iid).status_code == 200
    agendador, _, _ = montar(amb)
    assert agendador.rodar_uma_vez().executadas == 0 and repasses(amb) == 0
    amb.contexto.denuncias.alertas[alerta.id] = replace(alerta, resolvido=True)
    assert agendador.rodar_uma_vez().executadas == 1 and repasses(amb) == 1
