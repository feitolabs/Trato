"""BE-COMPENSACAO-DUPLA no Postgres local (Termos 8.6 e 8.7): decisão que reduz a compensação
não pode virar um segundo estorno ao cliente."""

from __future__ import annotations

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest

from .test_ausencia_cliente_postgres import _no_passado, _post
from .test_compensacao_postgres import (  # noqa: F401 - `avisos` é fixture
    PAINEL,
    PARTE,
    VALOR_ORCAMENTO,
    avisos,
    check_in,
    concluido,
    disponivel_do_profissional,
    liberar,
    tem_funcao_com_operador,
    zerar,
)
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

MENOR = PARTE // 2
CONTESTACAO = (
    "insert into public.disputa_contestacoes (id, protocolo, disputa_id, pedido_id, "
    "contestante_id, o_que_faltou, canal, contestar_ate, responder_ate, status, analista_id, "
    "resposta, nova_decisao, novo_valor_reembolso_centavos, aprovada_por, decidida_em, "
    "efeito_financeiro) values (%s, %s, %s, %s, %s, 'Fotos', 'app', "
    "now() + interval '5 days', now() + interval '10 days', 'alterada', %s, 'Procede.', "
    "'reembolso_parcial', %s, %s, clock_timestamp(), 'pendente_financeiro')"
)


def contestar(
    c, pid, disputa_id, quem, valor, status="alterada", efeito_="pendente_financeiro"
) -> str:
    ident = str(uuid.uuid4())
    protocolo = f"CDS-2026-{uuid.uuid4().int % 900000 + 100000}"
    sql, parcial = CONTESTACAO.replace("'pendente_financeiro'", f"'{efeito_}'"), valor
    if status == "revertida":
        sql = sql.replace("'alterada'", "'revertida'").replace(
            "'reembolso_parcial'", "'liberar_tudo'"
        )
        parcial = None
    _no_passado(
        c,
        sql,
        (ident, protocolo, disputa_id, pid, c.ids[quem], c.ids["med_b"], parcial, c.ids["adm_b"]),
    )
    return ident


def compensada_e_depois_reduzida(c):
    """Pedido repassado; uma contestação manda devolver PARTE (compensação registrada e
    estorno ordenado) e outra, depois, reduz para MENOR."""
    zerar_reducoes(c)
    pid, cobranca = agendado(c)
    check_in(c, pid)
    disputa = {"motivo": "mal_feito", "descricao": "Parede manchada.", "fotos": []}
    assert _post(c, "cliente", f"/v1/pedidos/{pid}/disputa", disputa).status_code == 201
    assert _post(c, "profissional", f"/v1/pedidos/{pid}/disputa/resposta", None).status_code == 200
    decisao = {"resultado": "liberar_tudo", "justificativa": "Serviço entregue como combinado."}
    assert _post(c, "med_a", f"/v1/admin/disputas/{pid}/decisao", decisao).status_code == 200
    liberar(c, pid, timedelta(days=15))
    ((disputa_id,),) = linhas(
        c,
        "select d.id::text from public.disputas d join public.contratos k on k.id = d.contrato_id "
        "where k.pedido_id = %s",
        (pid,),
    )
    primeira = contestar(c, pid, disputa_id, "cliente", PARTE)
    corpo = {"pedido_id": pid, "valor_centavos": PARTE, "motivo": "Revisão: dano comprovado."}
    r = _post(c, "med_a", PAINEL, corpo | {"contestacao_id": primeira})
    assert r.status_code == 200, r.text
    divida = r.json()["compensacao"]
    assert divida["suspensa"] is False
    segunda = contestar(c, pid, disputa_id, "profissional", MENOR)
    novo = corpo | {"valor_centavos": MENOR, "contestacao_id": segunda}
    return pid, cobranca, divida["id"], novo, corpo | {"contestacao_id": primeira}


def devolvido(c, cobranca):
    return [e.valor_centavos for e in c.pagto[2].provedor.estornos_da_cobranca(cobranca)]


def livro(c, pid):
    return len(c.pagto[1].ledger.lancamentos(pid))


def repassado_com_disputa(c):
    """Disputa decidida sem reembolso e valor já repassado."""
    zerar_reducoes(c)
    pid, cobranca = agendado(c)
    check_in(c, pid)
    disputa = {"motivo": "mal_feito", "descricao": "Parede manchada.", "fotos": []}
    assert _post(c, "cliente", f"/v1/pedidos/{pid}/disputa", disputa).status_code == 201
    assert _post(c, "profissional", f"/v1/pedidos/{pid}/disputa/resposta", None).status_code == 200
    decisao = {"resultado": "liberar_tudo", "justificativa": "Serviço entregue como combinado."}
    assert _post(c, "med_a", f"/v1/admin/disputas/{pid}/decisao", decisao).status_code == 200
    liberar(c, pid, timedelta(days=15))
    ((disputa_id,),) = linhas(
        c,
        "select d.id::text from public.disputas d join public.contratos k on k.id = d.contrato_id "
        "where k.pedido_id = %s",
        (pid,),
    )
    return pid, cobranca, disputa_id


def propor(c, pid, valor) -> str:
    corpo = {
        "pedido_id": pid,
        "referencia": str(uuid.uuid4()),
        "valor_centavos": valor,
        "motivo": "Garantia acionada depois do repasse.",
    }
    r = _post(c, "med_a", f"{PAINEL}/regressos", corpo)
    assert r.status_code == 201, r.text
    return r.json()["proposta"]["id"]


def aprovar(c, proposta):
    return _post(c, "adm_a", f"{PAINEL}/regressos/{proposta}/aprovacao", None)


def registrar_pela_contestacao(c, pid, disputa_id, valor, quem="cliente"):
    ident = contestar(c, pid, disputa_id, quem, valor)
    corpo = {"pedido_id": pid, "valor_centavos": valor, "motivo": "Revisão: dano comprovado."}
    return lambda: _post(c, "med_a", PAINEL, corpo | {"contestacao_id": ident})


def cancelar(c, divida_id):
    r = _post(c, "adm_a", f"{PAINEL}/{divida_id}/cancelar", {"motivo": "Cancelada para teste."})
    assert r.status_code == 200, r.text


def recusado(c, r, pid, cobranca, antes):
    assert r.status_code == 409 and r.json()["codigo"] == "estorno_ja_ordenado", r.text
    assert devolvido(c, cobranca) == antes[0] and livro(c, pid) == antes[1]


def test_disputa_cancelada_barra_o_regresso(pg, equipe, avisos):  # noqa: F811
    pid, cobranca, disputa_id = repassado_com_disputa(pg)
    r = registrar_pela_contestacao(pg, pid, disputa_id, PARTE)()
    assert r.status_code == 200, r.text
    cancelar(pg, r.json()["compensacao"]["id"])
    proposta = propor(pg, pid, MENOR)
    antes = (devolvido(pg, cobranca), livro(pg, pid))
    recusado(pg, aprovar(pg, proposta), pid, cobranca, antes)
    assert antes[0] == [PARTE]
    ((status,),) = linhas(
        pg, "select status from public.compensacao_propostas_regresso where id = %s", (proposta,)
    )
    assert status == "proposta"  # a aprovação foi desfeita junto
    zerar(pg)


@pytest.mark.parametrize("depois", ["regresso", "disputa"])
def test_regresso_cancelado_barra_os_dois_caminhos(pg, equipe, avisos, depois):  # noqa: F811
    pid, cobranca, disputa_id = repassado_com_disputa(pg)
    primeira = propor(pg, pid, PARTE)
    r = aprovar(pg, primeira)
    assert r.status_code == 200, r.text
    cancelar(pg, r.json()["compensacao"]["id"])
    if depois == "regresso":
        proposta = propor(pg, pid, MENOR)
        acao = lambda: aprovar(pg, proposta)  # noqa: E731
    else:
        acao = registrar_pela_contestacao(pg, pid, disputa_id, MENOR)
    antes = (devolvido(pg, cobranca), livro(pg, pid))
    assert antes[0] == [PARTE]
    recusado(pg, acao(), pid, cobranca, antes)
    assert aprovar(pg, primeira).json()["resultado"] == "ja_aprovada"  # repetir não quebra
    assert devolvido(pg, cobranca) == [PARTE]
    zerar(pg)


def test_os_dois_caminhos_ao_mesmo_tempo_nao_estornam_de_novo(pg, equipe, avisos):  # noqa: F811
    pid, cobranca, disputa_id = repassado_com_disputa(pg)
    r = aprovar(pg, propor(pg, pid, PARTE))
    cancelar(pg, r.json()["compensacao"]["id"])
    propostas = [propor(pg, pid, MENOR // 2), propor(pg, pid, MENOR // 3)]
    acoes = [lambda p=p: aprovar(pg, p) for p in propostas]
    acoes.append(registrar_pela_contestacao(pg, pid, disputa_id, MENOR))
    antes = (devolvido(pg, cobranca), livro(pg, pid))
    with ThreadPoolExecutor(3) as pool:
        for resposta in pool.map(lambda a: a(), acoes):
            recusado(pg, resposta, pid, cobranca, antes)
    zerar(pg)


def test_cancelamento_junto_com_aprovacao_nao_quebra(pg, equipe, avisos):  # noqa: F811
    """Ou a aprovação entra antes do cancelamento (as duas dívidas existiam juntas), ou é
    recusada; nunca fica pela metade: ou há dívida e ordem, ou nada."""
    pid, cobranca, _ = repassado_com_disputa(pg)
    divida = aprovar(pg, propor(pg, pid, MENOR)).json()["compensacao"]["id"]
    outra = propor(pg, pid, MENOR // 2)
    with ThreadPoolExecutor(2) as pool:
        corte = pool.submit(cancelar, pg, divida)
        nova = pool.submit(aprovar, pg, outra)
        corte.result()
        r = nova.result()
    assert r.status_code in (200, 409), r.text
    esperado = [MENOR] if r.status_code == 409 else [MENOR, MENOR // 2]
    assert devolvido(pg, cobranca) == esperado
    assert pg.pagto[1].compensacoes.listar(pedido_id=pid)[1] == len(esperado)
    zerar(pg)


def test_reducao_nao_estorna_o_cliente_de_novo(pg, equipe, avisos):  # noqa: F811
    if not tem_funcao_com_operador(pg):
        pytest.skip("Depende da compensacao_registrar_disputa com p_operador.")
    pid, cobranca, divida_id, novo, antigo = compensada_e_depois_reduzida(pg)
    lista = pg.pagto[0].get(PAINEL, headers=pg.token("med_a")).json()["itens"]
    assert [(d["id"], d["suspensa"]) for d in lista] == [(divida_id, True)]
    cancelar = f"{PAINEL}/{divida_id}/cancelar"
    r = _post(pg, "adm_a", cancelar, {"motivo": "Valor reduzido pela contestação."})
    assert r.status_code == 200 and r.json()["compensacao"]["suspensa"] is False, r.text
    antes = livro(pg, pid)
    for _ in range(2):
        r = _post(pg, "med_a", PAINEL, novo)
        assert r.status_code == 409, r.text
        assert r.json()["codigo"] == "estorno_ja_ordenado"
    assert devolvido(pg, cobranca) == [PARTE]  # nenhum segundo estorno
    assert [o.valor_centavos for o in pg.pagto[2].ordens.do_pedido(pid)] == [PARTE]
    assert livro(pg, pid) == antes  # nada ficou pela metade
    assert pg.pagto[0].get(PAINEL, headers=pg.token("med_a")).json()["total"] == 1
    # Repetir o registro antigo continua idempotente.
    repetido = _post(pg, "med_a", PAINEL, antigo)
    assert repetido.json()["resultado"] == "ja_registrada", repetido.text
    assert devolvido(pg, cobranca) == [PARTE]
    zerar(pg)


# --- redução da dívida (191500) -----------------------------------------------------------------


def reduzir(c, divida_id, contestacao, valor, quem="adm_a"):
    corpo = {
        "contestacao_id": contestacao,
        "novo_valor_centavos": valor,
        "motivo": "Decisão reduzida pela contestação.",
    }
    return _post(c, quem, f"{PAINEL}/{divida_id}/reduzir", corpo)


def efeito(c, contestacao):
    ((valor,),) = linhas(
        c, "select efeito_financeiro from public.disputa_contestacoes where id = %s", (contestacao,)
    )
    return valor


def test_reduzir_nao_toca_no_cliente_e_e_idempotente_em_paralelo(pg, equipe, avisos):  # noqa: F811
    pid, cobranca, divida_id, novo, _ = compensada_e_depois_reduzida(pg)
    segunda = novo["contestacao_id"]
    assert reduzir(pg, divida_id, segunda, MENOR, "med_a").status_code == 403
    assert reduzir(pg, divida_id, segunda, MENOR, "cliente").status_code == 403
    ruim = reduzir(pg, divida_id, segunda, PARTE)
    assert ruim.status_code == 422 and ruim.json()["codigo"] == "valor_invalido", ruim.text
    ordens = [o.valor_centavos for o in pg.pagto[2].ordens.do_pedido(pid)]
    with ThreadPoolExecutor(3) as pool:
        saidas = list(pool.map(lambda _: reduzir(pg, divida_id, segunda, MENOR), range(3)))
    assert [r.status_code for r in saidas] == [200, 200, 200], [r.text for r in saidas]
    assert sorted(r.json()["resultado"] for r in saidas) == ["ja_reduzida", "ja_reduzida", "ok"]
    d = saidas[0].json()["compensacao"]
    assert (d["valor_centavos"], d["valor_original_centavos"], d["reduzido_centavos"]) == (
        MENOR,
        PARTE,
        PARTE - MENOR,
    )
    assert (d["restante_centavos"], d["suspensa"], d["status"]) == (MENOR, False, "aberta")
    assert devolvido(pg, cobranca) == [PARTE]  # nada novo ao cliente
    assert [o.valor_centavos for o in pg.pagto[2].ordens.do_pedido(pid)] == ordens
    assert efeito(pg, segunda) == "executado"
    outro = reduzir(pg, divida_id, segunda, MENOR - 1)
    assert outro.status_code == 409 and outro.json()["codigo"] == "conflito", outro.text
    minhas = pg.pagto[0].get("/v1/me/compensacoes", headers=pg.token("profissional")).json()
    assert [(m["valor_centavos"], m["restante_centavos"]) for m in minhas] == [(MENOR, MENOR)]
    zerar_reducoes(pg)


def test_reduzir_depois_de_descontado_devolve_o_excesso_ao_profissional(pg, equipe, avisos):  # noqa: F811
    """O banco aceita uma contestação por parte: a 2ª reduz depois de o desconto já ter saído."""
    pid, cobranca, disputa_id = repassado_com_disputa(pg)
    r = registrar_pela_contestacao(pg, pid, disputa_id, PARTE)()
    assert r.status_code == 200, r.text
    divida_id = r.json()["compensacao"]["id"]
    seguinte = concluido(pg)
    liberar(pg, seguinte)
    assert disponivel_do_profissional(pg, seguinte) == VALOR_ORCAMENTO - PARTE
    contexto = pg.pagto[1]
    assert contexto.compensacoes.obter(divida_id).status == "quitada"

    segunda = contestar(pg, pid, disputa_id, "profissional", MENOR)
    r = reduzir(pg, divida_id, segunda, MENOR)
    assert r.status_code == 200, r.text
    assert r.json()["devolvido_centavos"] == PARTE - MENOR
    d = r.json()["compensacao"]
    assert (d["valor_centavos"], d["compensado_centavos"], d["restante_centavos"]) == (
        MENOR,
        MENOR,
        0,
    )
    assert d["devolvido_reducao_centavos"] == PARTE - MENOR
    assert disponivel_do_profissional(pg, seguinte) == VALOR_ORCAMENTO - MENOR
    repetida = reduzir(pg, divida_id, segunda, MENOR)
    assert repetida.json()["resultado"] == "ja_reduzida", repetida.text
    assert disponivel_do_profissional(pg, seguinte) == VALOR_ORCAMENTO - MENOR
    assert devolvido(pg, cobranca) == [PARTE]
    assert contexto.ledger.lancamentos(pid) and contexto.ledger.lancamentos(seguinte)
    zerar_reducoes(pg)


def do_painel(c, quem="adm_a", **filtro):
    r = c.pagto[0].get(PAINEL, params=filtro, headers=c.token(quem))
    assert r.status_code == 200, r.text
    return r.json()


def visao(d):
    campos = ("status", "suspensa", "revisao", "pode_reduzir", "reducao_maxima_centavos")
    return tuple(d[x] for x in campos)


def test_quitada_revista_aparece_no_filtro_e_so_quem_pode_ve_a_acao(pg, equipe, avisos):  # noqa: F811
    pid, cobranca, disputa_id = repassado_com_disputa(pg)
    r = registrar_pela_contestacao(pg, pid, disputa_id, PARTE)()
    divida_id = r.json()["compensacao"]["id"]
    seguinte = concluido(pg)
    liberar(pg, seguinte)
    assert do_painel(pg, revisao_pendente=True)["total"] == 0
    segunda = contestar(pg, pid, disputa_id, "profissional", MENOR)

    achadas = do_painel(pg, revisao_pendente=True)
    assert achadas["total"] == 1
    (d,) = achadas["itens"]
    assert visao(d) == ("quitada", False, "reducao", True, MENOR)
    assert d["revisao_contestacao_id"] == segunda and d["pode_cancelar"] is True
    (sem_alcada,) = do_painel(pg, "med_a", revisao_pendente=True)["itens"]
    assert visao(sem_alcada) == ("quitada", False, "reducao", False, None)
    assert sem_alcada["pode_cancelar"] is False
    minhas = pg.pagto[0].get("/v1/me/compensacoes", headers=pg.token("profissional")).json()
    assert not {"revisao", "pode_reduzir", "revisao_contestacao_id"} & set(minhas[0])

    with ThreadPoolExecutor(3) as pool:
        saidas = list(pool.map(lambda _: reduzir(pg, divida_id, segunda, MENOR), range(3)))
    assert sorted(x.json()["resultado"] for x in saidas) == ["ja_reduzida", "ja_reduzida", "ok"]
    assert disponivel_do_profissional(pg, seguinte) == VALOR_ORCAMENTO - MENOR  # uma vez só
    assert devolvido(pg, cobranca) == [PARTE]
    depois = saidas[0].json()["compensacao"]
    assert visao(depois) == ("quitada", False, None, False, None)
    assert do_painel(pg, revisao_pendente=True)["total"] == 0
    zerar_reducoes(pg)


def test_reversao_pede_cancelar(pg, equipe, avisos):  # noqa: F811
    pid, _, disputa_id = repassado_com_disputa(pg)
    r = registrar_pela_contestacao(pg, pid, disputa_id, PARTE)()
    assert r.status_code == 200, r.text
    contestar(pg, pid, disputa_id, "profissional", 0, "revertida")
    (d,) = do_painel(pg, revisao_pendente=True)["itens"]
    assert visao(d) == ("aberta", True, "reversao", False, None)
    assert d["pode_cancelar"] is True
    zerar_reducoes(pg)


def sonda(c, divida_id, contestacao, valor) -> str:
    """O que o banco responderia a esta redução (desfeita em seguida)."""
    with c.local.admin() as con, con.transaction(force_rollback=True):
        ((resultado,),) = con.execute(
            "select resultado from public.compensacao_reduzir(%s, %s, %s, %s, %s)",
            (divida_id, contestacao, valor, "Sondagem da paridade.", c.ids["adm_a"]),
        ).fetchall()
    return resultado


def conferir_paridade(c, divida_id, contestacoes):
    """Se a tela oferece reduzir, o banco aceita exatamente até o máximo; se não oferece, o
    banco recusa qualquer valor com qualquer das contestações."""
    (d,) = [x for x in do_painel(c)["itens"] if x["id"] == divida_id]
    maximo, oferecida = d["reducao_maxima_centavos"], d["revisao_contestacao_id"]
    if d["pode_reduzir"]:
        assert sonda(c, divida_id, oferecida, maximo) == "ok", d
        if maximo + 1 < d["valor_centavos"]:
            assert sonda(c, divida_id, oferecida, maximo + 1) == "valor_invalido", d
    for contestacao in contestacoes:
        if d["pode_reduzir"] and contestacao == oferecida:
            continue
        for valor in (1, d["valor_centavos"] - 1):
            assert sonda(c, divida_id, contestacao, valor) != "ok", (contestacao, valor, d)
    return d


DIRETO = PARTE // 3  # estorno feito na própria decisão, antes do repasse


def com_estorno_direto(c):
    zerar_reducoes(c)
    pid, cobranca = agendado(c)
    check_in(c, pid)
    disputa = {"motivo": "mal_feito", "descricao": "Parede manchada.", "fotos": []}
    assert _post(c, "cliente", f"/v1/pedidos/{pid}/disputa", disputa).status_code == 201
    assert _post(c, "profissional", f"/v1/pedidos/{pid}/disputa/resposta", None).status_code == 200
    decisao = {
        "resultado": "reembolso_parcial",
        "valor_cliente_centavos": DIRETO,
        "justificativa": "Parte do serviço não foi entregue.",
    }
    r = _post(c, "med_a", f"/v1/admin/disputas/{pid}/decisao", decisao)
    assert r.status_code == 200, r.text
    liberar(c, pid, timedelta(days=15))
    ((disputa_id,),) = linhas(
        c,
        "select d.id::text from public.disputas d join public.contratos k on k.id = d.contrato_id "
        "where k.pedido_id = %s",
        (pid,),
    )
    primeira = contestar(c, pid, disputa_id, "cliente", DIRETO + PARTE)
    corpo = {"pedido_id": pid, "valor_centavos": PARTE, "motivo": "Revisão: dano comprovado."}
    r = _post(c, "med_a", PAINEL, corpo | {"contestacao_id": primeira})
    assert r.status_code == 200, r.text
    return pid, cobranca, disputa_id, r.json()["compensacao"]["id"], primeira


@pytest.mark.parametrize(
    ("novo_teto", "tipo", "maximo"),
    [
        (DIRETO + MENOR, "reducao", MENOR),
        (DIRETO, "reversao", None),
        (DIRETO // 2, "reversao", None),
    ],
)
def test_paridade_com_estorno_direto(pg, equipe, avisos, novo_teto, tipo, maximo):  # noqa: F811
    pid, _, disputa_id, divida_id, primeira = com_estorno_direto(pg)
    ((direto,),) = linhas(pg, "select public.compensacao_estornado_ao_cliente(%s)", (disputa_id,))
    assert direto == DIRETO
    segunda = contestar(pg, pid, disputa_id, "profissional", novo_teto)
    d = conferir_paridade(pg, divida_id, [primeira, segunda])
    assert (d["revisao"], d["pode_reduzir"], d["reducao_maxima_centavos"]) == (
        tipo,
        maximo is not None,
        maximo,
    )
    zerar_reducoes(pg)


def test_paridade_sem_efeito_financeiro(pg, equipe, avisos):  # noqa: F811
    pid, _, disputa_id, divida_id, primeira = com_estorno_direto(pg)
    segunda = contestar(pg, pid, disputa_id, "profissional", DIRETO + MENOR, efeito_="nenhum")
    d = conferir_paridade(pg, divida_id, [primeira, segunda])
    assert (d["revisao"], d["pode_reduzir"]) == (None, False)
    assert d["suspensa"] is True  # a regra do banco não mudou
    assert [x["id"] for x in do_painel(pg, revisao_pendente=True)["itens"]] == [divida_id]
    zerar_reducoes(pg)


def test_paridade_com_contestacao_superada(pg, equipe, avisos):  # noqa: F811
    pid, _, disputa_id, divida_id, primeira = com_estorno_direto(pg)
    baixa = contestar(pg, pid, disputa_id, "profissional", DIRETO + MENOR)
    # O app aceita uma contestação por parte; a 3ª decisão aqui representa outra revisão.
    alta = contestar(pg, pid, disputa_id, "med_a", DIRETO + PARTE)
    d = conferir_paridade(pg, divida_id, [primeira, baixa, alta])
    assert (d["revisao"], d["pode_reduzir"], d["suspensa"]) == (None, False, True)
    assert sonda(pg, divida_id, baixa, MENOR) == "decisao_substituida"
    assert sonda(pg, divida_id, alta, MENOR) == "contestacao_invalida"  # não baixa a base
    assert do_painel(pg, revisao_pendente=True)["total"] == 1  # continua achável
    zerar_reducoes(pg)


def test_sem_a_funcao_do_estorno_direto_a_lista_segue(pg, equipe, avisos):  # noqa: F811
    pid, _, disputa_id, divida_id, _ = com_estorno_direto(pg)
    contestar(pg, pid, disputa_id, "profissional", DIRETO + MENOR)
    ida = (
        "alter function public.compensacao_estornado_ao_cliente(uuid) rename to estornado_escondida"
    )
    volta = (
        "alter function public.estornado_escondida(uuid) rename to compensacao_estornado_ao_cliente"
    )
    with pg.local.admin() as con:
        con.execute(ida)
    try:
        assert [x["id"] for x in do_painel(pg)["itens"]] == [divida_id]
    finally:
        with pg.local.admin() as con:
            con.execute(volta)
    zerar_reducoes(pg)


def test_regresso_nao_se_reduz_por_contestacao(pg, equipe, avisos):  # noqa: F811
    pid, cobranca, disputa_id = repassado_com_disputa(pg)
    divida = aprovar(pg, propor(pg, pid, PARTE)).json()["compensacao"]["id"]
    contestacao = contestar(pg, pid, disputa_id, "cliente", MENOR)
    r = reduzir(pg, divida, contestacao, MENOR)
    assert r.status_code == 422 and r.json()["codigo"] == "contestacao_invalida", r.text
    assert efeito(pg, contestacao) == "pendente_financeiro"
    assert devolvido(pg, cobranca) == [PARTE]
    zerar_reducoes(pg)


def test_sem_a_191500_a_lista_segue_e_a_reducao_responde_503(pg, equipe, avisos):  # noqa: F811
    _, _, divida_id, novo, _ = compensada_e_depois_reduzida(pg)
    trocas = (
        ("alter table public.compensacoes_reducoes rename to reducoes_escondida",
         "alter table public.reducoes_escondida rename to compensacoes_reducoes"),
        ("alter function public.compensacao_reduzir(uuid,uuid,bigint,text,uuid) "
         "rename to reduzir_escondida",
         "alter function public.reduzir_escondida(uuid,uuid,bigint,text,uuid) "
         "rename to compensacao_reduzir"),
    )  # fmt: skip
    with pg.local.admin() as con:
        for ida, _volta in trocas:
            con.execute(ida)
    try:
        lista = pg.pagto[0].get(PAINEL, headers=pg.token("med_a")).json()["itens"]
        assert [(d["valor_centavos"], d["suspensa"]) for d in lista] == [(PARTE, True)]
        r = reduzir(pg, divida_id, novo["contestacao_id"], MENOR)
        assert r.status_code == 503 and r.json()["codigo"] == "indisponivel", r.text
    finally:
        with pg.local.admin() as con:
            for _ida, volta in trocas:
                con.execute(volta)
    zerar_reducoes(pg)


def zerar_reducoes(c):
    with c.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.compensacoes_reducoes")
    zerar(c)
