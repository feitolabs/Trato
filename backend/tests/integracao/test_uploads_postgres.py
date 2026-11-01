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
