"""TERMOS-BE-209 no Postgres local: `medidas_conta` (infracao_grave/impedir_nova_conta),
`conta_impedimentos_cadastro` (HMAC + revogação) e `conta_pedidos_retorno` (prazo + aprovação)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.persistencia.medidas import Medida, MedidasPostgres
from trato.persistencia.retorno_conta import (
    RetornoContaPostgres,
    calcular_hmac_identificador,
)

from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao


def _criar_equipe_209(c) -> tuple[str, str]:
    med_id = str(uuid.uuid4())
    lider_id = str(uuid.uuid4())
    with c.local.admin() as con:
        for uid, nome, papel in (
            (med_id, "Mediador 209", "mediador"),
            (lider_id, "Lider 209", "lider_suporte"),
        ):
            con.execute("insert into auth.users (id) values (%s)", (uid,))
            con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
            con.execute(
                "insert into public.equipe (usuario_id, papel, ativo) values (%s, %s, true)",
                (uid, papel),
            )
    return med_id, lider_id


def test_impedimento_hmac_e_pedido_retorno_no_postgres(cenario, migrations_novas):  # noqa: F811
    _ = migrations_novas
    c = cenario
    medidas = MedidasPostgres(c.banco)
    retorno = RetornoContaPostgres(c.banco)
    assert retorno.disponivel()
    assert retorno.prazo_dias_vigente() == 90

    med_id, lider_id = _criar_equipe_209(c)
    agora = datetime.now(UTC)

    # 1) Encerramento por infração grave + impedimento HMAC (cliente)
    m_grave, nova = medidas.criar(
        Medida(
            usuario_id=c.ids["cliente"],
            tipo="encerramento",
            motivo="Fraude comprovada em análise de segurança.",
            clausulas=("20.9",),
            inicio_em=agora - timedelta(days=100),
            efeito="Conta encerrada.",
            como_contestar="Canal oficial.",
            aplicada_por=med_id,
            infracao_grave=True,
            impedir_nova_conta=True,
        )
    )
    assert nova and m_grave.id and m_grave.infracao_grave and m_grave.impedir_nova_conta

    h_cpf = calcular_hmac_identificador("cpf", "52998224725", "pepper-pg-teste")
    assert h_cpf is not None and len(h_cpf) == 64
    imp, imp_novo = retorno.registrar_impedimento(m_grave.id, "cpf", h_cpf, med_id, agora)
    assert imp_novo and retorno.esta_impedido([("cpf", h_cpf)]) is True

    # Revogar por líder de suporte
    imp_rev, cod_rev = retorno.revogar_impedimento(imp.id, lider_id, "Revogação de teste.", agora)
    assert cod_rev == "ok" and imp_rev is not None and imp_rev.revogado_por == lider_id
    assert retorno.esta_impedido([("cpf", h_cpf)]) is False

    # Infração grave bloqueia pedido de retorno
    _, _, cod_grave = retorno.abrir_retorno(
        c.ids["cliente"], "Quero voltar mesmo após infração grave.", "app", agora
    )
    assert cod_grave == "infracao_grave"

    # 2) Encerramento sem infração grave (profissional) -> pedido de retorno após 90 dias
    m_comum, nova2 = medidas.criar(
        Medida(
            usuario_id=c.ids["profissional"],
            tipo="encerramento",
            motivo="Encerramento administrativo sem infração grave.",
            clausulas=("20.9",),
            inicio_em=agora - timedelta(days=95),
            efeito="Conta encerrada.",
            como_contestar="Canal oficial.",
            aplicada_por=med_id,
            infracao_grave=False,
            impedir_nova_conta=False,
        )
    )
    assert nova2 and m_comum.id

    ret, eh_novo, cod_ret = retorno.abrir_retorno(
        c.ids["profissional"], "Prazo cumprido, solicito retorno.", "app", agora
    )
    assert eh_novo and cod_ret == "ok" and ret is not None and ret.protocolo.startswith("RET-")

    # Mediador analisa, líder aprova (validado pelo trigger do Postgres!)
    ret_ana, cod_ana = retorno.iniciar_analise_retorno(ret.id, med_id)
    assert cod_ana == "ok" and ret_ana is not None and ret_ana.status == "em_analise"

    ret_apr, cod_apr = retorno.decidir_retorno(
        ret.id, "aprovado", lider_id, "Histórico sem risco.", False, agora
    )
    assert cod_apr == "ok" and ret_apr is not None and ret_apr.status == "aprovado"
