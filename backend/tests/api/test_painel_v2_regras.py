"""Regras do painel admin v2 (documento de 02/11/2026): teto do pedido, número da auditoria e
motivo mínimo de 10 caracteres."""

from dataclasses import replace

from conftest import cab

CORPO_PEDIDO = {
    "categoria_id": "cat-1",
    "cidade_id": "cid-1",
    "titulo": "Pintar a sala",
    "descricao": "Duas demãos, parede inteira.",
    "endereco": {
        "logradouro": "Rua das Flores",
        "numero": "10",
        "bairro": "Centro",
        "cep": "35500-000",
    },
}


def _com_teto(amb, teto):
    amb.contexto.config._config = replace(
        amb.contexto.config.carregar(), valor_maximo_servico_centavos=teto
    )


def test_pedido_acima_do_teto_e_recusado(amb):
    _com_teto(amb, 100_000)  # R$ 1.000,00
    r = amb.cliente.post(
        "/v1/pedidos",
        json={**CORPO_PEDIDO, "faixa_preco_max_centavos": 3_000_000_000_000_000_000},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 422
    assert "R$ 1.000,00" in r.json()["detail"]


def test_pedido_dentro_do_teto_passa(amb):
    _com_teto(amb, 100_000)
    r = amb.cliente.post(
        "/v1/pedidos",
        json={**CORPO_PEDIDO, "faixa_preco_max_centavos": 90_000},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 201


def test_sem_teto_configurado_nao_barra(amb):
    # o teto só vale depois de aprovado em Configurações (nenhum número fica escrito no código)
    r = amb.cliente.post(
        "/v1/pedidos",
        json={**CORPO_PEDIDO, "faixa_preco_max_centavos": 5_000_000},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 201


def test_motivo_de_acao_sensivel_pede_10_caracteres(amb):
    r = amb.cliente.post(
        "/v1/admin/disputas/ped-1/decisao",
        json={"resultado": "liberar_tudo", "justificativa": "curto"},
        headers=cab("t-mediador"),
    )
    assert r.status_code == 422
