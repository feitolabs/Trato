"""TERMOS-BE-87 (8.7): contestar a decisão da disputa. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import pytest
from conftest import CLIENTE, PROFISSIONAL
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import VALOR, _abrir_e_responder_disputa, fluxo  # noqa: F401
from test_provas_ausencia import auditoria
from test_termos_be2 import enviados, ouvir

from trato.financeiro import periodo
from trato.persistencia.contestacoes_decisao import ContestacoesDecisaoEmMemoria
from trato.rotinas import dias_uteis

TEXTO = "A análise não considerou as fotos tiradas depois."
RESPOSTA = "Revi as fotos e o histórico do pedido."


def decidido(f, bps: int = 2_500) -> str:
    com_equipe(f.amb)
    pid = f.ate_em_confirmacao()
    _abrir_e_responder_disputa(f, pid)
    corpo = {"resultado": "reembolso_parcial", "percentual_cliente_bps": bps}
    corpo["justificativa"] = "Mancha confirmada nas fotos."
    r = f.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-mediador", corpo)
    assert r.status_code == 200, r.text
    return pid


def contestar(f, pid, quem="t-cliente", texto=TEXTO, anexos=()):
    corpo = {"o_que_faltou": texto, "anexos": list(anexos)}
    return f.chamar("POST", f"/v1/pedidos/{pid}/disputa/contestacoes", quem, corpo)


def ver(f, pid, quem="t-cliente"):
    return f.chamar("GET", f"/v1/pedidos/{pid}/disputa/contestacoes", quem)


def analisar(f, cid, quem="t-lider", resultado="mantida", nova=None, valor=None, texto=RESPOSTA):
    corpo = {"resultado": resultado, "resposta": texto}
    if nova:
        corpo["nova_decisao"] = nova
    if valor is not None:
        corpo["novo_valor_reembolso_centavos"] = valor
    return f.chamar("POST", f"/v1/admin/contestacoes-disputa/{cid}/decisao", quem, corpo)


def segunda(f, cid, quem="t-admin", aprovar=True):
    corpo = {"aprovar": aprovar, "motivo": "Conferi a análise e as provas."}
    return f.chamar("POST", f"/v1/admin/contestacoes-disputa/{cid}/aprovacao", quem, corpo)


def dinheiro(f, pid):
    return (len(f.ctx.ledger.lancamentos(pid)), list(f.fake.chamadas), f.pedido(pid)["estado"])


# --- a parte contesta -----------------------------------------------------------------------------


@pytest.mark.parametrize("quem", ["t-cliente", "t-prof"])
def test_cada_parte_contesta_e_as_duas_sao_avisadas(fluxo, quem):
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid = decidido(fluxo)
    antes = ver(fluxo, pid, quem).json()
    assert antes["pode_contestar"] is True and antes["itens"] == []
    r = contestar(fluxo, pid, quem)
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["status"] == "aberta" and corpo["protocolo"].startswith("CDS-")
    assert enviados(email, "Decisão contestada") == sorted([CLIENTE.id, PROFISSIONAL.id])
    outro = "t-prof" if quem == "t-cliente" else "t-cliente"
    (visto,) = ver(fluxo, pid, outro).json()["itens"]
    assert visto["minha"] is False and visto["o_que_faltou"] is None and visto["anexos"] == []
    assert ver(fluxo, pid, quem).json()["pode_contestar"] is False
    assert contestar(fluxo, pid, outro, "Também discordo da divisão.").status_code == 201


def test_reenvio_devolve_a_mesma_e_texto_diferente_conflita(fluxo):
    pid = decidido(fluxo)
    primeira = contestar(fluxo, pid).json()
    r = contestar(fluxo, pid)
    assert r.status_code == 200 and r.json()["id"] == primeira["id"]
    r = contestar(fluxo, pid, texto="Outro argumento completamente novo.")
    assert r.status_code == 409 and r.json()["codigo"] == "ja_contestada"


def test_prazo_de_cinco_dias_uteis_pela_hora_de_brasilia(fluxo):
    pid = decidido(fluxo)
    limite = datetime.fromisoformat(ver(fluxo, pid).json()["contestar_ate"])
    feriados = fluxo.ctx.config.carregar().disputas.feriados
    hoje = fluxo.ctx.agora().astimezone(periodo.BRASILIA).date()
    local = limite.astimezone(periodo.BRASILIA)
    assert local.date() == dias_uteis.somar_dias_uteis(hoje, 5, feriados)
    assert (local.hour, local.minute, local.second) == (23, 59, 59)
    fluxo.amb.relogio.agora = limite
    assert contestar(fluxo, pid).status_code == 201  # no último instante vale
    fluxo.amb.relogio.avancar(seconds=1)
    r = contestar(fluxo, pid, "t-prof")
    assert r.status_code == 409 and r.json()["codigo"] == "prazo_encerrado"
    assert ver(fluxo, pid, "t-prof").json()["pode_contestar"] is False
    assert contestar(fluxo, pid).status_code == 200  # reenvio depois do prazo não falha


def test_so_as_partes_e_so_disputa_decidida(fluxo):
    com_equipe(fluxo.amb)
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    r = contestar(fluxo, pid)
    assert r.status_code == 409 and r.json()["codigo"] == "sem_decisao"
    assert ver(fluxo, pid).json() == {"pode_contestar": False, "contestar_ate": None, "itens": []}
    assert contestar(fluxo, pid, "t-outro-cliente").status_code == 404
    assert contestar(fluxo, pid, "t-mediador").status_code == 403
    aberto = fluxo.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]  # sem contrato
    quem_mais = ("t-outro-cliente", "t-prof")
    fluxo.amb.contexto.auth.bloqueados.update(("t-cliente", *quem_mais))
    # 20.10: o bloqueado passa só no próprio pedido contratado (aqui ainda sem decisão)
    r = contestar(fluxo, pid)
    assert r.status_code == 409 and r.json()["codigo"] == "sem_decisao", r.text
    assert ver(fluxo, pid).json() == {"pode_contestar": False, "contestar_ate": None, "itens": []}
    recusas = [(aberto, "t-cliente"), ("pedido-que-nao-existe", "t-cliente")]
    recusas += [(pid, quem) for quem in quem_mais]
    for alvo, quem in recusas:
        for r in (contestar(fluxo, alvo, quem), ver(fluxo, alvo, quem)):
            assert r.status_code == 403, (alvo, quem, r.text)
            assert r.json()["codigo"] == "conta_bloqueada", (alvo, quem, r.text)


def test_anexo_que_nao_e_da_parte_e_recusado(fluxo):
    pid = decidido(fluxo)
    r = contestar(fluxo, pid, anexos=["arquivo-de-outra-pessoa"])
    assert r.status_code == 422 and r.json()["codigo"] == "anexo_invalido"


def test_pelo_atendimento_vale_a_data_do_chamado(fluxo):
    pid = decidido(fluxo)
    fluxo.amb.relogio.avancar(hours=1)
    chamado = {"categoria": "contestacao", "assunto": "Decisão", "texto": "Quero contestar."}
    fluxo.amb.contexto.auth.bloqueados.add("t-cliente")
    r = fluxo.chamar("POST", "/v1/sac/chamados", "t-cliente", chamado)
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    fluxo.amb.relogio.avancar(days=30)  # a equipe registra depois do prazo
    corpo = {"pedido_id": pid, "contestante_id": CLIENTE.id, "chamado_id": cid}
    corpo["o_que_faltou"] = TEXTO
    url = "/v1/admin/contestacoes-disputa"
    alheio = corpo | {"contestante_id": PROFISSIONAL.id}
    r = fluxo.chamar("POST", url, "t-lider", alheio)
    assert r.status_code == 422 and r.json()["codigo"] == "chamado_invalido"
    assert fluxo.chamar("POST", url, "t-financeiro", corpo).status_code == 403
    r = fluxo.chamar("POST", url, "t-lider", corpo)
    assert r.status_code == 201, r.text
    assert r.json()["canal"] == "sac" and r.json()["atrasada"] is True
    assert fluxo.chamar("POST", url, "t-lider", corpo).status_code == 200
    assert len(auditoria(fluxo, "disputas.contestacao_registrada")) == 1


# --- a equipe decide ------------------------------------------------------------------------------


def test_quem_decidiu_a_disputa_nao_analisa(fluxo):
    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    r = analisar(fluxo, cid, "t-mediador")
    assert r.status_code == 403 and r.json()["codigo"] == "analista_impedido"
    assert analisar(fluxo, cid, "t-financeiro").status_code == 403


def test_mantida_encerra_sem_aprovacao_e_sem_mover_dinheiro(fluxo):
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    antes = dinheiro(fluxo, pid)
    r = analisar(fluxo, cid)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "mantida" and r.json()["efeito_financeiro"] == "nenhum"
    assert dinheiro(fluxo, pid) == antes
    assert enviados(email, "Contestação analisada") == sorted([CLIENTE.id, PROFISSIONAL.id])
    assert analisar(fluxo, cid).status_code == 200  # reenvio
    assert analisar(fluxo, cid, texto="Outra resposta diferente.").status_code == 409
    assert len(auditoria(fluxo, "disputas.contestacao_decidida")) == 1
    (item,) = ver(fluxo, pid, "t-prof").json()["itens"]
    assert item["resposta"] == RESPOSTA


def test_mudanca_de_valor_espera_segunda_pessoa(fluxo):
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    antes = dinheiro(fluxo, pid)
    r = analisar(fluxo, cid, "t-lider", "alterada", "reembolso_parcial", 60_000)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "aguardando_aprovacao" and r.json()["decidida_em"] is None
    assert enviados(email, "Contestação analisada") == []
    (item,) = ver(fluxo, pid).json()["itens"]
    assert item["status"] == "em_analise" and item["resposta"] is None
    assert item["nova_decisao"] is None
    r = segunda(fluxo, cid, "t-lider")
    assert r.status_code == 403 and r.json()["codigo"] == "segunda_pessoa"
    assert segunda(fluxo, cid, "t-mediador").status_code == 403
    r = segunda(fluxo, cid)
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert (corpo["status"], corpo["efeito_financeiro"]) == ("alterada", "pendente_financeiro")
    assert corpo["aprovada_por"] == "eq-admin" and corpo["analista_id"] == "eq-lider"
    assert corpo["decisao_original"]["reembolso_centavos"] == 25_000
    assert corpo["decisao_vigente"]["reembolso_centavos"] == 60_000
    assert dinheiro(fluxo, pid) == antes  # nada se move sozinho
    assert segunda(fluxo, cid).status_code == 200  # reenvio
    assert len(auditoria(fluxo, "disputas.contestacao_aprovada")) == 1
    assert enviados(email, "Contestação analisada") == sorted([CLIENTE.id, PROFISSIONAL.id])


def test_devolvida_volta_para_a_analise(fluxo):
    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    analisar(fluxo, cid, "t-lider", "alterada", "reembolso_total")
    r = segunda(fluxo, cid, aprovar=False)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "em_analise" and r.json()["nova_decisao"] is None
    assert analisar(fluxo, cid).json()["status"] == "mantida"


def test_revertida_e_so_quando_muda_tudo_de_lado(fluxo):
    pid = decidido(fluxo)
    primeiro = contestar(fluxo, pid).json()["id"]
    analisar(fluxo, primeiro, "t-lider", "alterada", "reembolso_total")
    segunda(fluxo, primeiro)
    outro = contestar(fluxo, pid, "t-prof", "A outra parte também discorda.").json()["id"]
    r = analisar(fluxo, outro, "t-lider", "alterada", "liberar_tudo")
    assert r.status_code == 422 and r.json()["codigo"] == "resultado_incoerente"
    r = analisar(fluxo, outro, "t-lider", "revertida", "liberar_tudo")
    assert r.json()["status"] == "aguardando_aprovacao", r.text
    assert segunda(fluxo, outro).json()["status"] == "revertida"


@pytest.mark.parametrize(
    "resultado,nova,valor,codigo",
    [
        ("mantida", "liberar_tudo", None, "decisao_invalida"),
        ("alterada", None, None, "decisao_invalida"),
        ("alterada", "reembolso_parcial", None, "decisao_invalida"),
        ("alterada", "liberar_tudo", 10, "decisao_invalida"),
        ("alterada", "reembolso_parcial", VALOR + 1, "decisao_invalida"),
        ("alterada", "reembolso_parcial", 25_000, "sem_mudanca"),
        ("revertida", "reembolso_total", None, "resultado_incoerente"),
    ],
)
def test_decisao_invalida(fluxo, resultado, nova, valor, codigo):
    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    r = analisar(fluxo, cid, "t-lider", resultado, nova, valor)
    assert r.status_code == 422 and r.json()["codigo"] == codigo, r.text


def test_aprovacao_respeita_a_alcada(fluxo):
    from trato.api.admin.memoria import EquipeEmMemoria
    from trato.api.admin.repositorios import MembroEquipe

    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    analisar(fluxo, cid, "t-admin", "alterada", "reembolso_total")
    membros = list(fluxo.amb.admin.equipe._itens.values())
    fluxo.amb.admin.equipe = EquipeEmMemoria(
        [MembroEquipe(m.usuario_id, m.papel, alcada_centavos=1) for m in membros]
    )
    r = segunda(fluxo, cid, "t-lider")
    assert r.status_code == 403 and r.json()["codigo"] == "alcada", r.text


def test_decisoes_ao_mesmo_tempo_so_uma_vale(fluxo):
    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    textos = [f"Resposta concorrente número {n}." for n in range(6)]
    with ThreadPoolExecutor(6) as grupo:
        saidas = list(grupo.map(lambda t: analisar(fluxo, cid, texto=t).status_code, textos))
    assert sorted(saidas) == [200] + [409] * 5
    assert len(auditoria(fluxo, "disputas.contestacao_decidida")) == 1


def test_lista_filtra_por_status_e_efeito(fluxo):
    pid = decidido(fluxo)
    cid = contestar(fluxo, pid).json()["id"]
    url = "/v1/admin/contestacoes-disputa"
    r = fluxo.chamar("GET", f"{url}?status=aberta", "t-mediador")
    assert r.status_code == 200 and [i["id"] for i in r.json()["itens"]] == [cid], r.text
    assert r.json()["itens"][0]["contestante_papel"] == "cliente"
    r = fluxo.chamar("GET", f"{url}?efeito_financeiro=pendente_financeiro", "t-mediador")
    assert r.json()["total"] == 0
    assert fluxo.chamar("GET", f"{url}/{cid}", "t-mediador").json()["decidida_por"] == "eq-med"
    assert fluxo.chamar("GET", f"{url}/nao-existe", "t-mediador").status_code == 404
    assert fluxo.chamar("GET", url, "t-cliente").status_code == 403


# --- sem a tabela ---------------------------------------------------------------------------------


class SemTabela(ContestacoesDecisaoEmMemoria):
    def disponivel(self) -> bool:
        return False


def test_sem_a_tabela_503_e_o_resto_segue(fluxo):
    pid = decidido(fluxo)
    fluxo.ctx.contestacoes_decisao = SemTabela()
    url = "/v1/admin/contestacoes-disputa"
    for r in (
        contestar(fluxo, pid),
        ver(fluxo, pid),
        fluxo.chamar("GET", url, "t-mediador"),
        fluxo.chamar("GET", f"{url}/x", "t-mediador"),
        analisar(fluxo, "x"),
        segunda(fluxo, "x"),
    ):
        assert r.status_code == 503 and r.json()["codigo"] == "indisponivel", r.text
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}", "t-cliente").status_code == 200
