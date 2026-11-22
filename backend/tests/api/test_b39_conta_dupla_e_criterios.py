"""B39: conta dupla (upload de portfólio e extrato profissional separado) e nota por critérios."""

from __future__ import annotations

from typing import Any

from conftest import CLIENTE, PROFISSIONAL, cab
from test_profissional_upload import JPEG_COM_EXIF, e2  # noqa: F401

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import PerfilDetalhe
from trato.pedidos.estados import Estado as E


def test_1_cliente_consegue_pedir_upload_de_portfolio_e_equipe_continua_bloqueada(
    e2: Any,  # noqa: F811
) -> None:
    # Conta com papel CLIENTE ativando modo profissional consegue enviar foto de portfólio
    pedir, concluir = e2.enviar("t-cliente", "portfolio", JPEG_COM_EXIF)
    assert pedir.status_code == 201, pedir.text
    assert concluir.status_code == 200, concluir.text
    assert concluir.json()["destino"] == "portfolio"

    # EQUIPE continua bloqueada (403)
    r_equipe = e2.amb.cliente.post(
        "/v1/uploads",
        json={
            "destino": "portfolio",
            "nome_arquivo": "foto.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": len(JPEG_COM_EXIF),
        },
        headers=cab("t-equipe"),
    )
    assert r_equipe.status_code == 403


def test_2_extrato_como_profissional_nao_mistura_lancamentos_de_cliente(amb: Any) -> None:
    # Cliente pagou por um serviço (tem lançamentos como cliente, mas zero como profissional)
    amb.semear_pedido(E.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000, taxa=7_500)

    r_prof = amb.cliente.get("/v1/extrato?como=profissional", headers=cab("t-cliente"))
    assert r_prof.status_code == 200, r_prof.text
    assert r_prof.json()["itens"] == []
    assert r_prof.json()["total"] == 0

    r_cli = amb.cliente.get("/v1/extrato?como=cliente", headers=cab("t-cliente"))
    assert r_cli.status_code == 200, r_cli.text
    assert r_cli.json()["total"] == 3
    assert {i["tipo"] for i in r_cli.json()["itens"]} == {"cobranca", "retencao", "taxa"}

    # Saldo e PDF profissional também respondem 200 zerado para conta CLIENTE
    r_saldo = amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-cliente"))
    assert r_saldo.status_code == 200
    assert r_saldo.json()["a_liberar_centavos"] == 0
    assert r_saldo.json()["liberado_centavos"] == 0

    r_pdf = amb.cliente.get(
        "/v1/profissionais/me/extrato.pdf?mes=2026-10", headers=cab("t-cliente")
    )
    assert r_pdf.status_code == 200
    assert r_pdf.content.startswith(b"%PDF-")


def test_3_avaliacao_com_criterios_recalcula_nota_decimal_e_nota_geral(amb: Any) -> None:
    amb.semear_pedido(E.CONCLUIDO, id="ped-1")
    amb.contexto.usuarios.adicionar(PerfilDetalhe(CLIENTE.id, "Maria Silva", PapelUsuario.CLIENTE))
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(PROFISSIONAL.id, "Carlos Souza", PapelUsuario.PROFISSIONAL)
    )

    criterios_48 = {
        "pontualidade": 5,
        "qualidade": 5,
        "limpeza": 5,
        "comunicacao": 5,
        "preco_justo": 4,
    }
    # Payload tenta enviar nota_decimal=4.1 e nota_geral=3 divergentes da média real (4.8 -> 5)
    r = amb.cliente.post(
        "/v1/contratos/ped-1/avaliacao",
        json={"nota_geral": 3, "nota_decimal": 4.1, "criterios": criterios_48},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["nota_decimal"] == 4.8
    assert corpo["nota_geral"] == 5
    assert corpo["criterios"] == criterios_48

    salva = amb.contexto.avaliacoes.obter("ped-1", "cliente_para_profissional")
    assert salva is not None
    assert salva.nota_decimal == 4.8
    assert salva.nota_geral == 5

    # Duplo toque idempotente com os mesmos critérios (mesmo que mande outra nota_decimal no payload)
    r_dup = amb.cliente.post(
        "/v1/contratos/ped-1/avaliacao",
        json={"nota_geral": 4, "nota_decimal": 4.2, "criterios": criterios_48},
        headers=cab("t-cliente"),
    )
    assert r_dup.status_code == 200
    assert r_dup.json()["nota_decimal"] == 4.8
    assert r_dup.json()["nota_geral"] == 5
