"""BE-69 (Termos 6.9) no Postgres local (migration 20261128030000): execução do estorno de
material contestado. Retido, liberado, misto, parcelado, repetição, recusa e rollback."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

from trato.financeiro.ledger import (
    CUSTODIA,
    TAXA_TRATO,
    Livro,
    a_liberar,
    custo_parcelamento_em_aberto,
    liberar,
)
from trato.persistencia.execucao import ExecucaoPostgres, ItemNota
from trato.persistencia.materiais_contestacao import ContestacaoMaterialPostgres

from .test_compensacao_postgres import Avisos, concluido, zerar
from .test_compensacao_postgres import liberar as liberar_pela_rotina
from .test_desistencia_postgres import agendado, check_in, ordens
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_fluxo_postgres import foto
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    _aplicar,
    linhas,
    migrations_novas,
    pg,
)
from .test_termos_m2_postgres import pagar_parcelado

pytestmark = pytest.mark.integracao

MOTIVO = "Material não comprovado: estorno aprovado."
V = VALOR_ORCAMENTO // 4


@pytest.fixture(scope="module")
def migration_69(pg):
    """Depende de `ordens_estorno`, que só entra com `migrations_novas`: aplica aqui."""
    with pg.local.admin() as con:
        desfazer = _aplicar(
            con,
            "20261128030000_nota_material_estorno_69.sql",
            "20261128030000_nota_material_estorno_69_rollback.sql",
            "select to_regclass('public.nota_material_execucoes') is not null",
        )
    yield
    with pg.local.admin() as con:
        for sql in desfazer:
            con.execute(sql)


@pytest.fixture
def amb(pg, migration_69, equipe, monkeypatch):
    zerar_tudo(pg)
    avisos = Avisos()
    monkeypatch.setitem(pg.pagto[1].extras, "notificador", avisos)
    monkeypatch.setitem(pg.pagto[1].__dict__, "materiais_contestacao", repo(pg))
    pg.avisos = avisos
    yield pg
    zerar_tudo(pg)


def zerar_tudo(c):
    with c.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.nota_material_execucoes")
        con.execute("delete from public.nota_material_contestacoes")
    zerar(c)


def repo(c) -> ContestacaoMaterialPostgres:
    return ContestacaoMaterialPostgres(c.banco)


def aprovada(c, pid, valor=V, *, aprovar=True) -> str:
    nota = ExecucaoPostgres(c.banco).registrar_nota_material(
        pedido_id=pid,
        profissional_id=c.ids["profissional"],
        foto_storage_path=f"notas/{pid}.jpg",
        itens=[ItemNota("Tinta", Decimal("1"), VALOR_ORCAMENTO)],
    )
    agora = datetime.now(UTC)
    cont, _, codigo = repo(c).abrir(
        pedido_id=pid,
        nota_id=nota,
        nota_total_centavos=VALOR_ORCAMENTO,
        item_id=None,
        item_total_centavos=None,
        cliente_id=c.ids["cliente"],
        motivo="nao_comprovado",
        descricao="Não foi entregue.",
        anexos=(),
        valor_contestado_centavos=valor,
        aberta_em=agora,
        responder_ate=agora + timedelta(days=5),
    )
    assert codigo == "ok"
    _, codigo = repo(c).decidir(cont.id, "procedente", c.ids["med_a"], MOTIVO, valor, agora)
    assert codigo == "ok"
    if aprovar:
        _, codigo = repo(c).aprovar_financeiro(cont.id, c.ids["adm_a"])
        assert codigo == "ok"
    return cont.id


def executar(c, cid, quem="adm_a", no_app=True):
    return c.pagto[0].post(
        f"/v1/admin/materiais/contestacoes/{cid}/executar-estorno",
        json={"motivo": MOTIVO, "material_pago_no_app": no_app},
        headers=c.token(quem),
    )


def saldos(c, pid):
    contexto = c.pagto[1]
    return contexto.ledger.saldos_pedido(pid, contexto.pedidos.obter(pid).profissional_id)


def custo_aberto(c, pid) -> int:
    livro = Livro()
    livro.lancar_varios(list(c.pagto[1].ledger.lancamentos(pid)))
    return custo_parcelamento_em_aberto(livro, pid)


def foto_do_dinheiro(c, pid, cid):
    return (
        saldos(c, pid),
        len(c.pagto[1].ledger.lancamentos(pid)),
        ordens(c, pid),
        [x.estornado_centavos for x in c.pagto[2].cobrancas.do_pedido(pid)],
        repo(c).obter(cid).efeito_financeiro,
        c.pagto[1].compensacoes.listar(pedido_id=pid)[1],
        linhas(
            c,
            "select count(*) from public.nota_material_execucoes where contestacao_id = %s",
            (cid,),
        ),
    )


def no_provedor(c, pid) -> list[int]:
    servico = c.pagto[2]
    return [
        e.valor_centavos
        for cobranca in servico.cobrancas.do_pedido(pid)
        for e in servico.provedor.estornos_da_cobranca(cobranca.id)
    ]


def test_retido_repeticao_concorrente_e_o_pedido_segue_normal(amb):
    c = amb
    pid, _ = agendado(c)
    cid = aprovada(c, pid)
    saidas = []
    fios = [threading.Thread(target=lambda: saidas.append(executar(c, cid))) for _ in range(3)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    assert [r.status_code for r in saidas] == [200] * 3, [r.text for r in saidas]
    assert sorted(r.json()["resultado"] for r in saidas) == ["ja_executada"] * 2 + ["ok"]
    corpo = executar(c, cid).json()
    assert corpo["resultado"] == "ja_executada"
    assert (corpo["total_estornado_centavos"], corpo["valor_retido_centavos"]) == (V, V)
    assert corpo["compensacao_id"] is None and corpo["profissional_avisado"] is None
    assert corpo["contestacao"]["efeito_financeiro"] == "executado"
    assert ordens(c, pid) == [V] and no_provedor(c, pid) == [V]
    assert saldos(c, pid).retido == VALOR_ORCAMENTO - V

    # o serviço conclui e libera só o que sobrou
    check_in(c, pid)
    visto = c.pagto[0].get(f"/v1/pedidos/{pid}", headers=c.token("cliente")).json()
    prova = {"foto_final": foto(), "codigo_conclusao": visto["codigo_conclusao"]}
    url = f"/v1/pedidos/{pid}/acoes"
    r = c.pagto[0].post(
        f"{url}/fazer_check_out", json={"prova": prova}, headers=c.token("profissional")
    )
    assert r.status_code == 200, r.text
    r = c.pagto[0].post(f"{url}/confirmar_conclusao", json={}, headers=c.token("cliente"))
    assert r.status_code == 200, r.text
    assert saldos(c, pid).a_liberar == VALOR_ORCAMENTO - V


def test_liberado_vira_compensacao_avisada(amb):
    c = amb
    pid = concluido(c)
    liberar_pela_rotina(c, pid)
    cid = aprovada(c, pid)
    r = executar(c, cid)
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert (corpo["valor_retido_centavos"], corpo["valor_compensacao_centavos"]) == (0, V)
    assert corpo["profissional_avisado"] is True
    assert ordens(c, pid) == [V] and no_provedor(c, pid) == [V]
    (divida,), _ = c.pagto[1].compensacoes.listar(pedido_id=pid)
    assert (divida.origem_tipo, divida.valor_centavos) == ("nota_material_contestacao", V)
    assert divida.avisado_em is not None and not divida.suspensa
    # painel e app do profissional aceitam a nova origem
    meus = c.pagto[0].get("/v1/me/compensacoes", headers=c.token("profissional"))
    assert meus.status_code == 200, meus.text
    assert divida.id in [d["id"] for d in meus.json()]
    assert executar(c, cid).json()["resultado"] == "ja_executada"
    assert ordens(c, pid) == [V]
    assert c.pagto[1].compensacoes.listar(pedido_id=pid)[1] == 1
    # e desconta do repasse seguinte
    novo = concluido(c)
    liberar_pela_rotina(c, novo)
    (divida,), _ = c.pagto[1].compensacoes.listar(pedido_id=pid)
    assert (divida.compensado_centavos, divida.status) == (V, "quitada")


def test_misto_retido_primeiro_e_o_resto_vira_divida(amb):
    c = amb
    contexto = c.pagto[1]
    pid = concluido(c)
    prof = contexto.pedidos.obter(pid).profissional_id
    retido = V // 2
    livro = Livro()
    livro.lancar_varios(list(contexto.ledger.lancamentos(pid)))
    parte = liberar(
        livro, pid, prof, f"teste:{pid}:parcial", datetime.now(UTC), VALOR_ORCAMENTO - retido
    )
    contexto.ledger.lancar_varios([parte])
    r = executar(c, aprovada(c, pid))
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert (corpo["valor_retido_centavos"], corpo["valor_compensacao_centavos"]) == (
        retido,
        V - retido,
    )
    assert ordens(c, pid) == [V]
    assert contexto.ledger.saldo_da_conta(a_liberar(prof), pid) == 0
    assert saldos(c, pid).cliente_pagou == VALOR_ORCAMENTO - V


@pytest.mark.parametrize("liberado", [False, True])
def test_parcial_parcelado_devolve_o_custo_proporcional(amb, monkeypatch, liberado):
    c = amb
    contexto = c.pagto[1]
    pid, cobrado = pagar_parcelado(c, monkeypatch)
    custo = cobrado - VALOR_ORCAMENTO
    proporcional = (V * custo + VALOR_ORCAMENTO // 2) // VALOR_ORCAMENTO
    assert 0 < proporcional < custo
    if liberado:  # leva o pedido pago até a liberação
        inicio = datetime.now(UTC).replace(microsecond=0) + timedelta(days=2)
        janela = {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
        url = f"/v1/pedidos/{pid}/acoes"
        http = c.pagto[0]
        r = http.post(
            f"{url}/confirmar_agenda",
            json={"prova": {"janela": janela}},
            headers=c.token("profissional"),
        )
        assert r.status_code == 200, r.text
        check_in(c, pid)
        visto = http.get(f"/v1/pedidos/{pid}", headers=c.token("cliente")).json()
        prova = {"foto_final": foto(), "codigo_conclusao": visto["codigo_conclusao"]}
        r = http.post(
            f"{url}/fazer_check_out", json={"prova": prova}, headers=c.token("profissional")
        )
        assert r.status_code == 200, r.text
        r = http.post(f"{url}/confirmar_conclusao", json={}, headers=c.token("cliente"))
        assert r.status_code == 200, r.text
        liberar_pela_rotina(c, pid)
    cid = aprovada(c, pid)
    r = executar(c, cid)
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["custo_parcelamento_centavos"] == proporcional
    assert corpo["total_estornado_centavos"] == V + proporcional
    assert corpo["valor_compensacao_centavos"] == (V if liberado else 0)
    assert ordens(c, pid) == [V + proporcional] and no_provedor(c, pid) == [V + proporcional]
    assert saldos(c, pid).cliente_pagou == cobrado - V - proporcional
    assert custo_aberto(c, pid) == custo - proporcional
    assert contexto.ledger.saldo_da_conta(TAXA_TRATO, pid) == custo - proporcional
    if not liberado:
        assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR_ORCAMENTO - V


def test_recusas_nao_movem_nada(amb, monkeypatch):
    c = amb
    pid, _ = agendado(c)
    pendente = aprovada(c, pid, aprovar=False)
    antes = foto_do_dinheiro(c, pid, pendente)
    r = executar(c, pendente)
    assert (r.status_code, r.json()["codigo"]) == (409, "nao_elegivel"), r.text
    _, codigo = repo(c).aprovar_financeiro(pendente, c.ids["adm_a"])
    assert codigo == "ok"
    antes = foto_do_dinheiro(c, pid, pendente)

    assert executar(c, pendente, quem="med_a").status_code == 403  # sem a permissão
    assert executar(c, pendente, quem="cliente").status_code in (401, 403)
    r = executar(c, pendente, no_app=False)
    assert (r.status_code, r.json()["codigo"]) == (409, "analise_manual"), r.text

    with c.local.admin() as con:
        con.execute(
            "update public.equipe set alcada_centavos = 1 where usuario_id = %s",
            (c.ids["adm_b"],),
        )
    r = executar(c, pendente, quem="adm_b")
    assert (r.status_code, r.json()["codigo"]) == (403, "acima_da_alcada"), r.text

    servico = c.pagto[2]
    with monkeypatch.context() as m:  # o app não cobre o valor
        m.setattr(servico, "planejar_estorno_material", lambda *a: None)
        r = executar(c, pendente)
    assert (r.status_code, r.json()["codigo"]) == (409, "analise_manual"), r.text
    assert foto_do_dinheiro(c, pid, pendente) == antes


@pytest.mark.parametrize("liberado", [False, True])
def test_recusa_do_banco_desfaz_livro_e_ordens(amb, monkeypatch, liberado):
    c = amb
    if liberado:
        pid = concluido(c)
        liberar_pela_rotina(c, pid)
    else:
        pid, _ = agendado(c)
    cid = aprovada(c, pid)
    antes = foto_do_dinheiro(c, pid, cid)
    alvo = ContestacaoMaterialPostgres
    original = alvo.executar_estorno

    def custo_errado(self, contestacao, divida, custo, motivo, operador):
        # o banco de verdade recusa (custo_invalido) depois de livro e ordens gravados
        return original(self, contestacao, divida, custo + 1, motivo, operador)

    with monkeypatch.context() as m:
        m.setattr(alvo, "executar_estorno", custo_errado)
        r = executar(c, cid)
    assert (r.status_code, r.json()["codigo"]) == (422, "custo_invalido"), r.text
    assert foto_do_dinheiro(c, pid, cid) == antes
    assert no_provedor(c, pid) == []  # o provedor nunca foi chamado

    r = executar(c, cid)  # e a execução certa passa depois
    assert r.status_code == 200, r.text
    assert ordens(c, pid) == [V]
