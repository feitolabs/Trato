"""FIX-DISPUTA-PAINEL no Postgres LOCAL descartável: o painel grava a ordem de estorno, uma vez só,
e o SELECT das decisões antigas sem ordem. Provedor falso. Nunca toca no Supabase."""

# ruff: noqa: F811 - os parâmetros com nome de fixture importada são do pytest

from __future__ import annotations

import threading
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.financeiro.ledger import CUSTODIA, Livro, estornar_pedido
from trato.pagamentos.provedor import ErroProvedor

from .test_ausencia_reembolso_postgres import ordens, pago_e_agendado
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    estado_pedido,
    linhas,
    migrations_novas,
    pg,
)

pytestmark = pytest.mark.integracao

# Decisões de disputa que lançaram reembolso no ledger sem ordem de estorno (só leitura).
SELECT_DECISOES_SEM_ORDEM = """
with decisao as (
  select c.id as contrato_id, c.pedido_id, min(l.ocorrido_em) as decidido_em,
         sum(case pa.sentido when 'credito' then pa.valor_centavos
                             else -pa.valor_centavos end) as devolvido_no_ledger
    from public.lancamentos l
    join public.contratos c on c.id = l.contrato_id
    join public.partidas pa on pa.lancamento_id = l.id
    join public.contas_ledger k on k.id = pa.conta_id and k.codigo = 'cliente_externo'
   where starts_with(l.chave_idempotencia, 'disputa/')
   group by c.id, c.pedido_id)
select d.pedido_id, d.decidido_em, d.devolvido_no_ledger,
       coalesce(o.total, 0) as pedido_ao_provedor,
       d.devolvido_no_ledger - coalesce(o.total, 0) as falta_pedir,
       (select string_agg(g.stripe_payment_intent_id, ', ') from public.pagamentos g
         where g.contrato_id = d.contrato_id) as cobrancas_no_provedor
  from decisao d
  left join lateral (select sum(valor_centavos) as total from public.ordens_estorno
                      where contrato_id = d.contrato_id) o on true
 where d.devolvido_no_ledger > coalesce(o.total, 0)
 order by d.decidido_em
"""


@pytest.fixture(scope="module")
def equipe(pg):
    """Mediadores decidem (regra do banco); administradores aprovam acima da alçada."""
    nomes = {
        "med_baixa": ("mediador", 1),
        "med_a": ("mediador", 100_000_000),
        "med_b": ("mediador", 100_000_000),
        "adm_a": ("administrador", None),
        "adm_b": ("administrador", None),
    }
    teto = "select teto_centavos from public.papeis_alcada where papel = 'mediador'"
    mudar = "update public.papeis_alcada set teto_centavos = %s where papel = 'mediador'"
    with pg.local.admin() as con:
        antes = con.execute(teto).fetchone()
        con.execute(mudar, (100_000_000,))  # o teto do papel limita a alçada de cada pessoa
        for nome, (papel, alcada) in nomes.items():
            pg.ids[nome] = str(uuid.uuid4())
            con.execute("insert into auth.users (id) values (%s)", (pg.ids[nome],))
            con.execute(
                "insert into public.usuarios (id, nome) values (%s, %s)", (pg.ids[nome], nome)
            )
            con.execute(
                "insert into public.equipe (usuario_id, papel, alcada_centavos) values (%s, %s, %s)",
                (pg.ids[nome], papel, alcada),
            )
    yield pg
    if antes is not None:
        with pg.local.admin() as con:
            con.execute(mudar, (antes[0],))


def em_disputa(c) -> tuple[str, str]:
    http = c.pagto[0]
    pid, cobranca, _ = pago_e_agendado(c)
    corpo = {
        "motivo": "nao_compareceu",
        "descricao": "Combinou e não veio.",
        "fotos": [{"arquivo_id": str(uuid.uuid4()), "tirada_em": datetime.now(UTC).isoformat()}],
    }
    r = http.post(f"/v1/pedidos/{pid}/disputa", json=corpo, headers=c.token("cliente"))
    assert r.status_code == 201, r.text
    r = http.post(f"/v1/pedidos/{pid}/disputa/resposta", headers=c.token("profissional"))
    assert r.status_code == 200, r.text
    return pid, cobranca


def decidir(c, pid, quem="med_a", resultado="reembolso_total", **extra):
    corpo = {"resultado": resultado, "justificativa": "Conferido nas provas.", **extra}
    return c.pagto[0].post(f"/v1/admin/disputas/{pid}/decisao", json=corpo, headers=c.token(quem))


def aprovar(c, pid, quem):
    return c.pagto[0].post(
        f"/v1/admin/disputas/{pid}/aprovacao",
        json={"justificativa": "Concordo com a decisão."},
        headers=c.token(quem),
    )


def devolvido(c, cobranca) -> list[int]:
    return [e.valor_centavos for e in c.pagto[2].provedor.estornos_da_cobranca(cobranca)]


def _juntos(*chamadas) -> list[int]:
    barreira, codigos = threading.Barrier(len(chamadas)), []

    def rodar(chamada) -> None:
        barreira.wait()
        codigos.append(chamada().status_code)

    fios = [threading.Thread(target=rodar, args=(f,)) for f in chamadas]
    [f.start() for f in fios]
    [f.join(40) for f in fios]
    return sorted(codigos)


def test_painel_grava_a_ordem_e_estorna_uma_vez(equipe):
    c = equipe
    pid, cobranca = em_disputa(c)
    r = decidir(c, pid)
    assert r.status_code == 200, r.text
    assert estado_pedido(c, pid) == "cancelado"
    assert [(o.valor_centavos, o.estado) for o in ordens(c, pid)] == [(VALOR_ORCAMENTO, "enviada")]
    assert devolvido(c, cobranca) == [VALOR_ORCAMENTO]
    assert c.pagto[1].ledger.saldo_da_conta(CUSTODIA, pid) == 0
    assert decidir(c, pid).status_code == 409
    assert len(ordens(c, pid)) == 1
    avisos = linhas(
        c,
        "select tipo, count(*) from public.notificacoes where canal = 'app' "
        "and dados ->> 'pedido_id' = %s and tipo in ('disputa.decidida', 'pagamento.estorno') "
        "group by tipo order by tipo",
        (c.pagto[1].pedidos.obter(pid).id,),
    )
    assert [tuple(x) for x in avisos] == [("disputa.decidida", 2), ("pagamento.estorno", 1)]


def test_proposta_nao_move_dinheiro_e_duas_aprovacoes_juntas_valem_uma(equipe):
    c = equipe
    pid, cobranca = em_disputa(c)
    r = decidir(c, pid, quem="med_baixa")
    assert r.status_code == 200 and r.json()["estado"] == "aguardando_aprovacao", r.text
    assert ordens(c, pid) == [] and devolvido(c, cobranca) == []
    codigos = _juntos(lambda: aprovar(c, pid, "adm_a"), lambda: aprovar(c, pid, "adm_b"))
    assert codigos == [200, 409]
    assert len(ordens(c, pid)) == 1 and devolvido(c, cobranca) == [VALOR_ORCAMENTO]


def test_duas_decisoes_ao_mesmo_tempo_no_banco(equipe):
    c = equipe
    pid, cobranca = em_disputa(c)
    codigos = _juntos(
        lambda: decidir(c, pid, "med_a"),
        lambda: decidir(c, pid, "med_b", "reembolso_parcial", valor_cliente_centavos=1_000),
    )
    assert codigos == [200, 409]
    (ordem,) = ordens(c, pid)
    assert devolvido(c, cobranca) == [ordem.valor_centavos]


def test_provedor_fora_fica_pendente_e_o_reenvio_completa(equipe, monkeypatch):
    c = equipe
    servico = c.pagto[2]
    pid, cobranca = em_disputa(c)

    def fora(*args):
        raise ErroProvedor("fora do ar")

    with monkeypatch.context() as m:
        m.setattr(servico.provedor, "estornar", fora)
        r = decidir(c, pid)
        assert r.status_code == 200, r.text
    assert [o.estado for o in ordens(c, pid)] == ["pendente"]
    assert servico.reenviar_estornos(pid, criadas_ate=datetime.now(UTC) + timedelta(hours=1)) == 1
    assert [o.estado for o in ordens(c, pid)] == ["enviada"]
    assert devolvido(c, cobranca) == [VALOR_ORCAMENTO]


def test_select_lista_so_a_decisao_antiga_sem_ordem(equipe):
    c = equipe
    contexto = c.pagto[1]
    antiga, cobranca = em_disputa(c)
    nova, _ = em_disputa(c)
    assert decidir(c, nova).status_code == 200
    # como o painel fazia antes: reembolso parcial só no ledger, com a chave `disputa/<pedido>/`
    livro = Livro()
    livro.lancar_varios(contexto.ledger.lancamentos(antiga))
    antes = len(livro.lancamentos)
    pedido_id = contexto.pedidos.obter(antiga).id
    estornar_pedido(livro, pedido_id, 20_000, f"disputa/{pedido_id}/est", datetime.now(UTC))
    contexto.ledger.lancar_varios(livro.lancamentos[antes:])

    achadas = {str(x[0]).replace("-", ""): x for x in linhas(c, SELECT_DECISOES_SEM_ORDEM)}

    assert nova.replace("-", "") not in achadas
    linha = achadas[antiga.replace("-", "")]
    assert (linha[2], linha[3], linha[4]) == (20_000, 0, 20_000) and cobranca in linha[5]
