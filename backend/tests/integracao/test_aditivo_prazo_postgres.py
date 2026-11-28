"""BE-68 no Postgres local (Termos 6.8): a cobrança do aditivo encerrada no check-out ainda
vale quando o dinheiro entrou antes dele, e volta quando entrou depois."""

from __future__ import annotations

import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import UTC, datetime, timedelta

import psycopg
import pytest

from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor.base import TipoEvento

from .test_ausencia_cliente_postgres import _post
from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado
from .test_fluxo_postgres import foto
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
    webhook,
)

SITUACAO = (
    "select status, estornado_centavos from public.pagamentos where stripe_payment_intent_id = %s"
)


@pytest.mark.parametrize("antes", [True, False])
def test_aditivo_e_check_out(pg, antes):  # noqa: F811
    http, contexto, servico = pg.pagto
    pid, _ = agendado(pg)
    check_in(pg, pid)
    pedido = contexto.pedidos.obter(pid)
    aditivo = servico.propor_aditivo(contexto, pedido, "Trocar o registro", 5_000)
    _, cobranca = servico.aprovar_aditivo(contexto, pedido, aditivo.id, _pix())
    pago_em = datetime.now(UTC) - timedelta(seconds=2)
    visto = http.get(f"/v1/pedidos/{pid}", headers=pg.token("cliente")).json()
    saida = {"foto_final": foto(), "codigo_conclusao": visto["codigo_conclusao"]}
    r = _post(pg, "profissional", f"/v1/pedidos/{pid}/acoes/fazer_check_out", {"prova": saida})
    assert r.status_code == 200, r.text
    assert linhas(pg, SITUACAO, (cobranca.id,)) == [("expirado", 0)]
    servico.provedor.marcar_paga(cobranca.id)
    instante = pago_em if antes else datetime.now(UTC) + timedelta(seconds=60)
    for n in (1, 2):
        r = webhook(
            pg,
            TipoEvento.PAGAMENTO_CONFIRMADO,
            cobranca.id,
            instante=int(instante.timestamp()),
            evento_id=f"evt_ad_{pid}_{n}",
        )
        assert r.status_code == 200, r.text
    esperado = ("confirmado", 0) if antes else ("reembolsado", 5_000)
    assert linhas(pg, SITUACAO, (cobranca.id,)) == [esperado]
    devolvidos = [e.valor_centavos for e in servico.provedor.estornos_da_cobranca(cobranca.id)]
    assert devolvidos == ([] if antes else [5_000])


def test_a1_aditivo_so_se_paga_uma_vez_mesmo_em_paralelo(pg):  # noqa: F811
    _, contexto, servico = pg.pagto
    pid, _ = agendado(pg)
    check_in(pg, pid)
    pedido = contexto.pedidos.obter(pid)
    aditivo = servico.propor_aditivo(contexto, pedido, "Trocar o registro", 5_000)

    def aprovar(_):
        try:
            return servico.aprovar_aditivo(contexto, pedido, aditivo.id, _pix())[1]
        except Exception:  # noqa: BLE001
            return None

    with ThreadPoolExecutor(2) as pool:
        saidas = list(pool.map(aprovar, range(2)))
    (cobranca,) = [x for x in saidas if x is not None]
    segunda = servico.cobrar(contexto, pedido, 5_000, MeioPagamento.CARTAO, aditivo.id)
    assert segunda.id != cobranca.id
    for item in (cobranca, segunda):
        servico.provedor.marcar_paga(item.id)
        r = webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, item.id, evento_id=f"evt_{item.id}")
        assert r.status_code == 200, r.text
    assert linhas(pg, SITUACAO, (cobranca.id,)) == [("confirmado", 0)]
    assert linhas(pg, SITUACAO, (segunda.id,)) == [("reembolsado", 5_000)]


INDICE = "pagamentos_aditivo_pago_uidx"
ESTADO_DO_ADITIVO = "select count(*) from public.lancamentos where chave_idempotencia = %s"


def duas_cobrancas(pg):  # noqa: F811
    _, contexto, servico = pg.pagto
    pid, _ = agendado(pg)
    check_in(pg, pid)
    pedido = contexto.pedidos.obter(pid)
    aditivo = servico.propor_aditivo(contexto, pedido, "Trocar o registro", 5_000)
    _, primeira = servico.aprovar_aditivo(contexto, pedido, aditivo.id, _pix())
    segunda = servico.cobrar(contexto, pedido, 5_000, MeioPagamento.CARTAO, aditivo.id)
    for item in (primeira, segunda):
        servico.provedor.marcar_paga(item.id)
    return pid, aditivo.id, primeira, segunda


def confirmar(pg, cobranca_id, evento=None):  # noqa: F811
    return webhook(
        pg,
        TipoEvento.PAGAMENTO_CONFIRMADO,
        cobranca_id,
        evento_id=evento or f"evt_{cobranca_id}",
    )


def em_revisao(pg, evento_id):  # noqa: F811
    ((erro,),) = linhas(
        pg, "select erro from public.eventos_webhook where evento_id = %s", (evento_id,)
    )
    return (erro or "").startswith("revisar:")


def sem_a_checagem_do_app(pg, monkeypatch):  # noqa: F811
    """Cada confirmação só enxerga a própria cobrança: sobra o índice do banco."""
    cobrancas = pg.pagto[2].cobrancas
    monkeypatch.setattr(cobrancas, "do_pedido", lambda _: ())


def devolucoes(pg, cobranca_id):  # noqa: F811
    return [e.valor_centavos for e in pg.pagto[2].provedor.estornos_da_cobranca(cobranca_id)]


def test_indice_barra_a_segunda_e_ela_volta_uma_vez(pg, monkeypatch):  # noqa: F811
    pid, aid, primeira, segunda = duas_cobrancas(pg)
    assert confirmar(pg, primeira.id).status_code == 200
    with monkeypatch.context() as m:
        sem_a_checagem_do_app(pg, m)
        for evento in ("evt_a", "evt_a", "evt_b"):  # reenvio e outro evento
            r = confirmar(pg, segunda.id, f"{evento}_{segunda.id}")
            assert r.status_code == 200, r.text
    assert linhas(pg, SITUACAO, (primeira.id,)) == [("confirmado", 0)]
    assert linhas(pg, SITUACAO, (segunda.id,)) == [("reembolsado", 5_000)]
    assert devolucoes(pg, segunda.id) == [5_000]
    assert em_revisao(pg, f"evt_a_{segunda.id}")
    assert linhas(pg, ESTADO_DO_ADITIVO, (f"cob/{segunda.id}",)) == [(0,)]
    assert linhas(pg, ESTADO_DO_ADITIVO, (f"cob/{primeira.id}",)) == [(1,)]
    assert pg.pagto[2].aditivos.obter(aid).estado.value == "pago"


def test_indice_decide_a_corrida_sem_a_trava_do_pedido(pg, monkeypatch):  # noqa: F811
    _, _, primeira, segunda = duas_cobrancas(pg)
    sem_a_checagem_do_app(pg, monkeypatch)
    monkeypatch.setattr(pg.pagto[1].pedidos, "travar", lambda _: None)
    with ThreadPoolExecutor(2) as pool:
        saidas = list(pool.map(lambda c: confirmar(pg, c.id).status_code, (primeira, segunda)))
    assert saidas == [200, 200], saidas
    situacoes = sorted(linhas(pg, SITUACAO, (c.id,))[0] for c in (primeira, segunda))
    assert situacoes == [("confirmado", 0), ("reembolsado", 5_000)]
    assert sorted(devolucoes(pg, primeira.id) + devolucoes(pg, segunda.id)) == [5_000]


def test_contestacao_da_devolvida_com_outra_paga_fica_registrada(pg):  # noqa: F811
    _, aid, primeira, segunda = duas_cobrancas(pg)
    assert confirmar(pg, primeira.id).status_code == 200
    assert confirmar(pg, segunda.id).status_code == 200  # a 2ª volta; a 1ª vale
    disputa = f"dp_{uuid.uuid4().hex}"
    r = webhook(
        pg,
        TipoEvento.CONTESTACAO,
        segunda.id,
        evento_id=f"evt_{disputa}",
        objeto_id=disputa,
        valor_centavos=5_000,
        status_contestacao="needs_response",
    )
    assert r.status_code == 200, r.text
    assert linhas(
        pg,
        "select status from public.contestacoes where provedor_contestacao_id = %s",
        (disputa,),
    ) == [("aberta",)]
    assert linhas(pg, SITUACAO, (segunda.id,)) == [("reembolsado", 5_000)]
    assert em_revisao(pg, f"evt_{disputa}")
    # Marcar a devolvida como contestada no banco é barrado pelo índice: o backend não faz isso.
    with pytest.raises(psycopg.errors.UniqueViolation, match=INDICE), pg.local.admin() as con:
        con.execute(
            "update public.pagamentos set status = 'contestado' "
            "where stripe_payment_intent_id = %s",
            (segunda.id,),
        )
    assert pg.pagto[2].aditivos.obter(aid).estado.value == "pago"


def test_so_conta_como_pago_o_que_entrou_no_livro(pg):  # noqa: F811
    http, _, servico = pg.pagto
    pid, aid, primeira, segunda = duas_cobrancas(pg)
    assert confirmar(pg, primeira.id).status_code == 200
    # Paga e depois devolvida por inteiro: entrou no livro, continua "pago".
    paga = servico.cobrancas.obter(primeira.id)
    servico.cobrancas.salvar(
        replace(paga, status=EstadoCobranca.DEVOLVIDA, estornado_centavos=5_000)
    )
    assert servico.aditivos.obter(aid).estado.value == "pago"

    outro_pid, outro, orfa, _ = duas_cobrancas(pg)
    visto = http.get(f"/v1/pedidos/{outro_pid}", headers=pg.token("cliente")).json()
    saida = {"foto_final": foto(), "codigo_conclusao": visto["codigo_conclusao"]}
    caminho = f"/v1/pedidos/{outro_pid}/acoes/fazer_check_out"
    assert _post(pg, "profissional", caminho, {"prova": saida}).status_code == 200
    tarde = int((datetime.now(UTC) + timedelta(seconds=60)).timestamp())
    r = webhook(
        pg, TipoEvento.PAGAMENTO_CONFIRMADO, orfa.id, evento_id=f"evt_{orfa.id}", instante=tarde
    )
    assert r.status_code == 200, r.text
    assert linhas(pg, SITUACAO, (orfa.id,)) == [("reembolsado", 5_000)]
    assert servico.aditivos.obter(outro).estado.value == "aprovado"  # nunca foi pago


def test_sem_o_indice_a_regra_do_app_continua(pg):  # noqa: F811
    with pg.local.admin() as con:
        sql = con.execute(
            "select indexdef from pg_indexes where indexname = %s", (INDICE,)
        ).fetchone()[0]
        con.execute(f"drop index public.{INDICE}")
    try:
        _, _, primeira, segunda = duas_cobrancas(pg)
        assert confirmar(pg, primeira.id).status_code == 200
        assert confirmar(pg, segunda.id).status_code == 200
        assert linhas(pg, SITUACAO, (segunda.id,)) == [("reembolsado", 5_000)]
    finally:
        with pg.local.admin() as con:
            con.execute(sql)


def _pix():
    return MeioPagamento.PIX
