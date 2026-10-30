"""Lado do profissional: atender o retrabalho (e a resposta à disputa que já existia)."""

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA, cab

from trato.pedidos.estados import Estado

URL = "/v1/pedidos/ped-1/retrabalho"


def pedir(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - timedelta(days=2))
    r = amb.cliente.post(URL, json={"descricao": "Mancha voltou"}, headers=cab("t-cliente"))
    assert r.status_code == 201, r.text


def atender(amb, etapa, quem="t-prof"):
    return amb.cliente.post(f"{URL}/atender", json={"etapa": etapa}, headers=cab(quem))


def test_profissional_aceita_inicia_e_resolve(amb):
    pedir(amb)
    for etapa, estado in (
        ("aceitar", "aceito"),
        ("iniciar", "em_execucao"),
        ("resolver", "resolvido"),
    ):
        r = atender(amb, etapa)
        assert r.status_code == 200, r.text
        assert r.json()["estado"] == estado and r.json()["pedido_id"] == "ped-1"
    assert r.json()["atendido_em"].startswith("2026-10-29T12:00")
    # um registro só, com a situação nova (não duplica na memória)
    [unico] = amb.contexto.garantias.retrabalhos("ped-1")
    assert unico.estado.value == "resolvido"
    # o cliente enxerga o andamento
    lista = amb.cliente.get(URL, headers=cab("t-cliente")).json()
    assert [x["estado"] for x in lista] == ["resolvido"]


def test_repetir_a_etapa_e_seguro_e_pular_etapa_da_409(amb):
    pedir(amb)
    assert atender(amb, "iniciar").status_code == 409  # falta aceitar
    assert atender(amb, "resolver").status_code == 409
    assert atender(amb, "aceitar").status_code == 200
    again = atender(amb, "aceitar")
    assert again.status_code == 200 and again.json()["estado"] == "aceito"
    assert atender(amb, "resolver").status_code == 409  # falta iniciar


def test_so_o_profissional_do_pedido_atende(amb):
    pedir(amb)
    assert atender(amb, "aceitar", "t-cliente").status_code == 403
    assert atender(amb, "aceitar", "t-outro-prof").status_code == 404  # não revela o pedido
    assert atender(amb, "aceitar", "t-equipe").status_code == 403
    assert amb.cliente.post(f"{URL}/atender", json={"etapa": "aceitar"}).status_code == 401
    assert amb.cliente.get(URL, headers=cab("t-outro-cliente")).status_code == 404
    assert amb.contexto.garantias.retrabalhos("ped-1")[0].estado.value == "aberto"


def test_prazo_de_atendimento_vencido_nao_aceita(amb):
    pedir(amb)
    amb.relogio.avancar(days=8)  # prazo de 7 dias da configuração
    r = atender(amb, "aceitar")
    assert r.status_code == 409 and "prazo" in r.json()["detail"]


def test_sem_retrabalho_da_409_e_etapa_invalida_422(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    assert atender(amb, "aceitar").status_code == 409
    assert (
        amb.cliente.post(f"{URL}/atender", json={"etapa": "x"}, headers=cab("t-prof")).status_code
        == 422
    )


def test_profissional_responde_a_disputa(amb):
    """A rota do lado do profissional já existe: resposta dentro do prazo vai para análise."""
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000)
    corpo = {"motivo": "mal_feito", "descricao": "Parede manchada"}
    r = amb.cliente.post("/v1/pedidos/ped-1/disputa", json=corpo, headers=cab("t-cliente"))
    assert r.status_code == 201
    url = "/v1/pedidos/ped-1/disputa/resposta"
    assert amb.cliente.post(url, headers=cab("t-cliente")).status_code == 403
    assert amb.cliente.post(url, headers=cab("t-outro-prof")).status_code == 404
    ok = amb.cliente.post(url, headers=cab("t-prof"))
    assert ok.status_code == 200 and ok.json()["estado"] == "em_analise"
