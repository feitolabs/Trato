"""TERMOS-BE-69 no Postgres local: `public.nota_material_contestacoes` (migration 225400),
protocolo CNM-, mudança de status da nota para `contestada`, idempotência e 4 olhos."""

from __future__ import annotations

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from threading import Barrier

import pytest

from trato.persistencia.execucao import ExecucaoPostgres, ItemNota
from trato.persistencia.materiais_contestacao import ContestacaoMaterialPostgres
from trato.persistencia.pedido_extras import NotasMaterialPostgres

from .test_ausencia_reembolso_postgres import pago_e_agendado
from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao


def _criar_equipe_69(c) -> tuple[str, str]:
    med_id = str(uuid.uuid4())
    lider_id = str(uuid.uuid4())
    with c.local.admin() as con:
        for uid, nome, papel in (
            (med_id, "Mediador 69", "mediador"),
            (lider_id, "Lider 69", "lider_suporte"),
        ):
            con.execute("insert into auth.users (id) values (%s)", (uid,))
            con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
            con.execute(
                "insert into public.equipe (usuario_id, papel, ativo) values (%s, %s, true)",
                (uid, papel),
            )
    return med_id, lider_id


def test_contestacao_nota_material_e_4_olhos_no_postgres(pg):  # noqa: F811
    c = pg
    repo = ContestacaoMaterialPostgres(c.banco)
    assert repo.disponivel()

    pid, _, _ = pago_e_agendado(c)
    exec_pg = ExecucaoPostgres(c.banco)
    nota_id = exec_pg.registrar_nota_material(
        pedido_id=pid,
        profissional_id=c.ids["profissional"],
        foto_storage_path="notas/pg-teste.jpg",
        itens=[ItemNota("Tinta", Decimal("2"), 5_000)],
    )

    med_id, lider_id = _criar_equipe_69(c)
    agora = datetime.now(UTC)

    # Abrir contestação -> protocolo CNM-... e status da nota muda para 'contestada' pelo trigger
    c1, nova1, cod1 = repo.abrir(
        pedido_id=pid,
        nota_id=nota_id,
        nota_total_centavos=10_000,
        item_id=None,
        item_total_centavos=None,
        cliente_id=c.ids["cliente"],
        motivo="nao_comprovado",
        descricao="Uma lata não foi entregue.",
        anexos=(),
        valor_contestado_centavos=5_000,
        aberta_em=agora,
        responder_ate=agora + timedelta(days=5),
    )
    assert nova1 and cod1 == "ok" and c1 is not None and c1.protocolo.startswith("CNM-")
    assert linhas(c, "select status from public.notas_material where id = %s", (nota_id,)) == [
        ("contestada",)
    ]

    # Item da nota: o id vem do repositório; item e nota inteira não se sobrepõem
    (nota,) = NotasMaterialPostgres(c.banco, exec_pg).do_pedido(pid)
    assert len(nota.item_ids) == 1
    _, _, cod_item = repo.abrir(
        pedido_id=pid,
        nota_id=nota_id,
        nota_total_centavos=10_000,
        item_id=nota.item_ids[0],
        item_total_centavos=10_000,
        cliente_id=c.ids["cliente"],
        motivo="nao_comprovado",
        descricao="Item que sobrepõe a nota inteira.",
        anexos=(),
        valor_contestado_centavos=1_000,
        aberta_em=agora,
        responder_ate=agora + timedelta(days=5),
    )
    assert cod_item == "sobreposicao"

    # Repetição idempotente
    c2, nova2, cod2 = repo.abrir(
        pedido_id=pid,
        nota_id=nota_id,
        nota_total_centavos=10_000,
        item_id=None,
        item_total_centavos=None,
        cliente_id=c.ids["cliente"],
        motivo="nao_comprovado",
        descricao="Repetição.",
        anexos=(),
        valor_contestado_centavos=5_000,
        aberta_em=agora,
        responder_ate=agora + timedelta(days=5),
    )
    assert not nova2 and cod2 == "ja_aberta" and c2 is not None and c2.id == c1.id

    # Analista decide procedente; mesmo analista não aprova; líder aprova (4 olhos no trigger!)
    dec, cod_dec = repo.decidir(c1.id, "procedente", med_id, "Confirmada ausência.", 5_000, agora)
    assert cod_dec == "ok" and dec is not None and dec.status == "procedente"

    _, cod_mesmo = repo.aprovar_financeiro(c1.id, med_id)
    assert cod_mesmo == "mesma_pessoa"

    apr, cod_apr = repo.aprovar_financeiro(c1.id, lider_id)
    assert (
        cod_apr == "ok"
        and apr is not None
        and apr.aprovada_por == lider_id
        and apr.efeito_financeiro == "pendente_financeiro"
    )


def test_duplo_toque_com_o_valor_inteiro_abre_uma_so_no_postgres(pg):  # noqa: F811
    c = pg
    repo = ContestacaoMaterialPostgres(c.banco)
    pid, _, _ = pago_e_agendado(c)
    nota_id = ExecucaoPostgres(c.banco).registrar_nota_material(
        pedido_id=pid,
        profissional_id=c.ids["profissional"],
        foto_storage_path="notas/pg-corrida.jpg",
        itens=[ItemNota("Tinta", Decimal("1"), 4_000)],
    )
    agora = datetime.now(UTC)
    largada = Barrier(2)

    def abrir(_):
        largada.wait()
        return repo.abrir(
            pedido_id=pid,
            nota_id=nota_id,
            nota_total_centavos=4_000,
            item_id=None,
            item_total_centavos=None,
            cliente_id=c.ids["cliente"],
            motivo="nao_comprovado",
            descricao="Não foi entregue.",
            anexos=(),
            valor_contestado_centavos=4_000,
            aberta_em=agora,
            responder_ate=agora + timedelta(days=5),
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        saidas = list(pool.map(abrir, range(2)))
    assert sorted(s[2] for s in saidas) == ["ja_aberta", "ok"]
    assert saidas[0][0].id == saidas[1][0].id
