"""Testes de persistência de uploads no Postgres local descartável (pgserver)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest

from trato.persistencia.uploads import UploadsPostgres
from trato.uploads.servico import Midia, Solicitacao

from .test_fluxo_postgres import abrir_pedido

pytestmark = pytest.mark.integracao


def test_uploads_postgres_ciclo_completo(cenario):
    banco = cenario.banco
    repo = UploadsPostgres(banco)

    dono_id = cenario.ids["cliente"]
    pedido_id = abrir_pedido(cenario)
    sol_id = uuid.uuid4().hex
    agora = datetime.now(UTC)

    sol = Solicitacao(
        id=sol_id,
        dono_id=dono_id,
        destino="checkin",
        bucket="pedido-midias",
        caminho=f"{pedido_id}/foto_inicio.jpg",
        content_type="image/jpeg",
        tamanho_bytes=10240,
        criada_em=agora,
        pedido_id=pedido_id,
        status="pendente",
    )
    repo.salvar_solicitacao(sol)

    lida = repo.solicitacao(sol_id)
    assert lida is not None
    assert lida.id == sol_id
    assert lida.dono_id == dono_id
    assert lida.status == "pendente"
    assert lida.pedido_id == pedido_id

    # Conclusão e registro de mídia
    midia_id = uuid.uuid4().hex
    midia = Midia(
        id=midia_id,
        pedido_id=pedido_id,
        enviada_por=cenario.ids["profissional"],
        finalidade="checkin",
        bucket="pedido-midias",
        storage_path=f"{pedido_id}/foto_inicio.jpg",
        mime="image/jpeg",
        tamanho_bytes=10240,
        sha256="abc123sha",
        criada_em=agora,
        lat=-19.92,
        lng=-43.94,
    )
    repo.salvar_midia(midia)

    midia_lida = repo.midia(midia_id)
    assert midia_lida is not None
    assert midia_lida.id == midia_id
    assert midia_lida.pedido_id == pedido_id
    assert midia_lida.lat == pytest.approx(-19.92)
    assert midia_lida.lng == pytest.approx(-43.94)

    # Atualiza solicitação com registro_id
    concluida = Solicitacao(
        id=sol_id,
        dono_id=dono_id,
        destino="checkin",
        bucket="pedido-midias",
        caminho=f"{pedido_id}/foto_inicio.jpg",
        content_type="image/jpeg",
        tamanho_bytes=10240,
        criada_em=agora,
        pedido_id=pedido_id,
        status="concluida",
        registro_id=midia_id,
    )
    repo.salvar_solicitacao(concluida)

    sol_atualizada = repo.solicitacao(sol_id)
    assert sol_atualizada is not None
    assert sol_atualizada.status == "concluida"
    assert sol_atualizada.registro_id == midia_id


def test_midias_do_pedido_filtra_por_finalidade_e_ordena_no_postgres(cenario):
    # A rota GET /v1/pedidos/{id}/fotos depende desta consulta (foto do serviço, não de disputa).
    repo = UploadsPostgres(cenario.banco)
    pedido_id = abrir_pedido(cenario)
    base = datetime.now(UTC)

    def midia(finalidade: str, depois_de_s: int) -> Midia:
        from datetime import timedelta

        return Midia(
            id=uuid.uuid4().hex,
            pedido_id=pedido_id,
            enviada_por=cenario.ids["profissional"],
            finalidade=finalidade,
            bucket="pedido-midias",
            storage_path=f"{pedido_id}/{finalidade}_{uuid.uuid4().hex[:6]}.jpg",
            mime="image/jpeg",
            tamanho_bytes=2048,
            sha256="x" * 8,
            criada_em=base + timedelta(seconds=depois_de_s),
        )

    saida, chegada, disputa = midia("checkout", 20), midia("checkin", 10), midia("disputa", 15)
    for m in (saida, chegada, disputa):
        repo.salvar_midia(m)

    achadas = repo.midias_do_pedido(pedido_id, ("checkin", "checkout"))

    assert [m.finalidade for m in achadas] == ["checkin", "checkout"]
    assert {m.id for m in achadas} == {chegada.id, saida.id}
    assert repo.midias_do_pedido(pedido_id, ("depois",)) == []


def test_cliente_edita_pedido_no_postgres(cenario):
    pedido_id = abrir_pedido(cenario)
    cab = cenario.token("cliente")
    r = cenario.cliente.patch(
        f"/v1/pedidos/{pedido_id}",
        json={
            "descricao": "Agora são 3 cômodos",
            "faixa_preco_max_centavos": 120000,
            "endereco": {"logradouro": "Rua Nova", "numero": "5", "bairro": "Savassi"},
        },
        headers=cab,
    )
    assert r.status_code == 200, r.text
    # segunda edição: o endereço já existe, então é atualizado (sem DELETE)
    r = cenario.cliente.patch(
        f"/v1/pedidos/{pedido_id}",
        json={"endereco": {"logradouro": "Rua Outra", "numero": "9"}},
        headers=cab,
    )
    assert r.status_code == 200, r.text
    lido = cenario.cliente.get(f"/v1/pedidos/{pedido_id}/dados", headers=cab).json()
    assert lido["faixa_preco_max_centavos"] == 120000
    assert "3 cômodos" in lido["descricao"]
    assert lido["endereco"]["logradouro"] == "Rua Outra"
