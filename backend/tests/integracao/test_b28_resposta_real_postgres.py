"""B28 no Postgres local descartável: selo `responde_em_faixa` calculado na leitura."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

from trato.api.repositorios import EtapaProposta, ItemOrcamento
from trato.api.resposta_real import FAIXA_NO_MESMO_DIA, JANELA_DIAS, MIN_PEDIDOS_RESPONDIDOS

from .test_fluxo_postgres import abrir_pedido

pytestmark = pytest.mark.integracao


def _novo_profissional_aprovado(c) -> str:
    """Profissional só deste teste: o banco do cenário é compartilhado e tem orçamentos de outros."""
    novo = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (novo,))
        con.execute("insert into public.usuarios (id, nome) values (%s, 'Pro B28')", (novo,))
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (novo,))
        con.execute(
            "update public.perfis_profissional set status = 'aprovado', "
            "nivel_verificacao = 'verificado' where usuario_id = %s",
            (novo,),
        )
    return novo


def _orcar(c, pedido_id: str, pro: str, agora: datetime) -> None:
    c.contexto.orcamentos.enviar(
        pedido_id=pedido_id,
        profissional_id=pro,
        itens=[ItemOrcamento("horas", "Mão de obra", Decimal("8"), 10_000)],
        etapas=[EtapaProposta("Serviço", 80_000)],
        agora=agora,
        prazo_execucao_dias=5,
        garantia_dias=90,
    )


def _faixa(c, pro_id: str):
    r = c.cliente.get(f"/v1/profissionais/{pro_id}", headers=c.token("cliente"))
    assert r.status_code == 200, r.text
    return r.json()["responde_em_faixa"]


def test_responde_em_faixa_no_postgres(cenario):
    c = cenario
    pro = _novo_profissional_aprovado(c)
    assert _faixa(c, pro) is None  # sem orçamento

    agora = datetime.now(UTC)
    for _ in range(MIN_PEDIDOS_RESPONDIDOS - 1):
        _orcar(c, abrir_pedido(c), pro, agora)
    assert _faixa(c, pro) is None  # 4 pedidos: ainda pouco

    # o 5º foi respondido há mais que a janela de 90 dias: não conta
    antigo = abrir_pedido(c)
    _orcar(c, antigo, pro, agora - timedelta(days=JANELA_DIAS + 10))
    assert _faixa(c, pro) is None

    # um 5º pedido recente fecha as 5 respostas rápidas: selo positivo
    ultimo = abrir_pedido(c)
    _orcar(c, ultimo, pro, agora)
    assert _faixa(c, pro) == FAIXA_NO_MESMO_DIA

    # outro profissional (sem orçamentos dele) não herda o selo
    outro = _novo_profissional_aprovado(c)
    assert _faixa(c, outro) is None

    # quem demora 3 dias em 5 pedidos tem mediana > 24 h: null (nunca faixa pior)
    lento = _novo_profissional_aprovado(c)
    for _ in range(MIN_PEDIDOS_RESPONDIDOS):
        _orcar(c, abrir_pedido(c), lento, agora + timedelta(days=3))
    assert _faixa(c, lento) is None
