"""BE-CONTA-VALORES no Postgres local: o dinheiro parado num pedido concluído impede a
exclusão (Termos 4.8) e a leitura da medida traz a marca de infração grave (13.10)."""

from __future__ import annotations

from trato.persistencia.lgpd import FonteLgpdPostgres
from trato.persistencia.medidas import Medida

from .test_cliente_bloqueado_postgres import em_confirmacao
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    migrations_novas,
    pg,
)


def test_valor_a_liberar_em_pedido_concluido_e_pendencia(pg):  # noqa: F811
    fonte = FonteLgpdPostgres(pg.banco)
    pid = em_confirmacao(pg)
    url = f"/v1/pedidos/{pid}/acoes/confirmar_conclusao"
    r = pg.pagto[0].post(url, headers=pg.token("cliente"))
    assert r.status_code == 200, r.text
    for quem in ("cliente", "profissional"):
        pendencias = fonte.pendencias(pg.ids[quem])
        assert any("retido ou a liberar" in p for p in pendencias), (quem, pendencias)
    assert fonte.pendencias(pg.ids["cliente2"]) == [] or not any(
        "retido" in p for p in fonte.pendencias(pg.ids["cliente2"])
    )


def test_leitura_da_medida_traz_a_infracao_grave(pg, equipe):  # noqa: F811
    contexto = pg.pagto[1]
    agora = contexto.agora()
    medida, _ = contexto.medidas.criar(
        Medida(
            usuario_id=pg.ids["cliente2"],
            tipo="encerramento",
            motivo="Infração grave de teste.",
            clausulas=("20.1",),
            inicio_em=agora,
            efeito="Segue a cláusula 20.6.",
            como_contestar="Pelo atendimento.",
            aplicada_por=pg.ids["equipe1"],
            infracao_grave=True,
            avisado_em=agora,
        )
    )
    assert contexto.medidas.obter(medida.id).infracao_grave is True
    lidas, _ = contexto.medidas.listar(usuario_id=pg.ids["cliente2"], tipo="encerramento")
    assert [m.infracao_grave for m in lidas] == [True]
