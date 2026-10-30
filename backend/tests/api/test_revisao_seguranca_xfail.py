"""Reproduz os achados CRÍTICOS e ALTOS de docs/revisao-seguranca.md.

Todos estão marcados `xfail(strict=True)`: hoje FALHAM (o problema existe). Quando alguém corrigir,
o teste passa de "falha esperada" para XPASS e o `strict` derruba a suíte, lembrando de tirar a
marca. Nenhum código-fonte foi alterado por esta revisão.
"""

from __future__ import annotations

import re
from dataclasses import replace
from datetime import timedelta
from pathlib import Path

import pytest
from conftest import AGORA, cab
from test_fluxo_pagamento_e2e import VALOR, Fluxo, _abrir_e_responder_disputa, fluxo  # noqa: F401

from trato import disputas
from trato.api.admin.rotas_disputas import _planejar_dinheiro
from trato.disputas import Decisao, Resultado
from trato.financeiro.ledger import (
    CLIENTE,
    CUSTODIA,
    ChaveReutilizada,
    Livro,
    TipoLancamento,
    registrar_cobranca,
)
from trato.pedidos.estados import Estado, Janela

RAIZ = Path(__file__).resolve().parents[3]


# --- C1 (crítico): dinheiro em memória no modo postgres ------------------------------------


@pytest.mark.xfail(
    strict=True,
    raises=(AssertionError, ChaveReutilizada),
    reason="C1: em TRATO_PERSISTENCIA=postgres o ledger, as disputas e os eventos do webhook "
    "ficam em memória (api/fabrica.py:76-79): reiniciar ou ter 2 workers perde/divide o dinheiro.",
)
def test_c1_modo_postgres_nao_guarda_dinheiro_em_memoria():
    from trato.api.fabrica import criar_contexto_postgres
    from trato.api.memoria import DisputasEmMemoria, EventosWebhookEmMemoria, LedgerEmMemoria
    from trato.config import Config
    from trato.persistencia.conexao import Banco

    banco = Banco("postgresql://sem-conexao/x", abrir=False)  # não conecta
    config = Config(trato_codigo_segredo="x", supabase_jwt_secret="x", _env_file=None)  # noqa: S106
    contexto = criar_contexto_postgres(banco, config)

    assert not isinstance(contexto.ledger, LedgerEmMemoria)
    assert not isinstance(contexto.disputas, DisputasEmMemoria)
    assert not isinstance(contexto.eventos_webhook, EventosWebhookEmMemoria)


# --- A1 (alto): código de 4 dígitos sem limite de tentativas ----------------------------------


def test_a1_codigo_certo_e_recusado_depois_de_muitos_erros(amb):
    amb.semear_pedido(
        Estado.AGENDADO,
        codigo_inicio="4321",
        janela=Janela(AGORA + timedelta(hours=1), AGORA + timedelta(hours=3)),
    )

    def tentar(codigo: str):
        prova = {
            "foto": {"arquivo_id": "f1", "tirada_em": (AGORA - timedelta(minutes=5)).isoformat()},
            "localizacao": {"latitude": -19.9, "longitude": -43.9},
            "codigo_inicio": codigo,
        }
        return amb.cliente.post(
            "/v1/pedidos/ped-1/acoes/fazer_check_in", json={"prova": prova}, headers=cab("t-prof")
        )

    respostas = []
    for n in range(30):  # 30 palpites errados seguidos
        respostas.append(tentar(f"{n:04d}" if f"{n:04d}" != "4321" else "9999").status_code)

    # Os primeiros erros ainda respondem 422; depois o limite (espera/bloqueio) responde 429.
    assert respostas[0] == 422
    assert set(respostas) <= {422, 429}
    assert respostas.count(422) < 30
    # O código CERTO também é recusado enquanto está bloqueado.
    assert tentar("4321").status_code in (403, 423, 429)


# --- A2 (alto): equipe sem permissão lê o dinheiro dos pedidos --------------------------------


@pytest.mark.parametrize("caminho", ["saldo", "extrato"])
def test_a2_equipe_sem_permissao_nao_le_financeiro(amb, caminho):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.semear_dinheiro()

    # "t-equipe" não existe na tabela `equipe` neste ambiente: não tem permissão nenhuma.
    r = amb.cliente.get(f"/v1/pedidos/ped-1/{caminho}", headers=cab("t-equipe"))

    assert r.status_code == 403


def test_a2_equipe_sem_permissao_nao_le_chat(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.contexto.conversas.abrir("ped-1", "pro-1")

    r = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-equipe"))

    assert r.status_code == 403


# --- A3 (alto): taxa recalculada na decisão, fora da versão congelada do contrato ------------


class _TaxaMutavel:
    """Simula a configuração vigente mudando DEPOIS do aceite do contrato."""

    def __init__(self, bps: int) -> None:
        self.bps = bps

    def calcular(self, valor: int) -> int:
        return (valor * self.bps + 5_000) // 10_000


@pytest.mark.xfail(
    strict=True,
    raises=(AssertionError, ChaveReutilizada),
    reason="A3: a decisão da disputa usa contexto.taxa.calcular() = versão VIGENTE na hora da "
    "decisão (api/admin/rotas_disputas.py:216, persistencia/app_extras.py:92), e não a "
    "taxa_bps_aplicada congelada no contrato.",
)
def test_a3_taxa_da_disputa_nao_muda_se_a_config_mudar_depois_do_aceite(amb):
    pedido = amb.semear_pedido(Estado.EM_DISPUTA, estado_antes_da_disputa=Estado.EM_CONFIRMACAO)
    livro = amb.contexto.ledger.livro
    registrar_cobranca(livro, "ped-1", 100_000, "cob-ped-1", AGORA)
    config = amb.contexto.config.carregar().disputas
    aberta = disputas.abrir(
        disputas.Ator.CLIENTE, 100_000, disputas.Motivo.MAL_FEITO, AGORA, AGORA, config
    )
    em_analise = replace(aberta, estado=disputas.Estado.EM_ANALISE)
    decidida = em_analise.decidir(
        disputas.Ator.ANALISTA, "eq-1", Decisao(Resultado.LIBERAR_TUDO), AGORA, 10**9
    )

    def taxa_lancada(bps: int) -> int:
        amb.contexto.taxa = _TaxaMutavel(bps)
        novos = _planejar_dinheiro(amb.contexto, pedido, decidida)
        return sum(n.valor for n in novos if n.tipo is TipoLancamento.TAXA)

    # Contrato aceito com 10%. Depois a configuração vira 25%: o contrato NÃO pode mudar.
    assert taxa_lancada(1_000) == taxa_lancada(2_500)


# --- A4 (alto): ledger Python x ledger do banco --------------------------------------------


@pytest.mark.xfail(
    strict=True,
    raises=(AssertionError, ChaveReutilizada),
    reason="A4: o enum TipoLancamento do Python tem tipos (liberacao, gorjeta) que o CHECK de "
    "public.lancamentos.tipo não aceita (migration F3.5:158-160): ao ligar o ledger ao banco, "
    "a liberação do repasse falha com check_violation.",
)
def test_a4_tipos_do_ledger_python_cabem_no_check_do_banco():
    sql = (RAIZ / "supabase/migrations/20261029030200_f35_dinheiro_ledger.sql").read_text(
        encoding="utf-8"
    )
    tabela = sql[sql.index("create table public.lancamentos") :]
    trecho = re.search(r"tipo\s+text not null\s+check \(tipo in \(([^)]*)\)\)", tabela, re.S)
    assert trecho, "CHECK de lancamentos.tipo não encontrado"
    aceitos = set(re.findall(r"'(\w+)'", trecho.group(1)))
    assert {t.value for t in TipoLancamento} <= aceitos


@pytest.mark.xfail(
    strict=True,
    raises=(AssertionError, ChaveReutilizada),
    reason="A4: o gatilho do banco exige que o estorno INVERTA o lançamento original inteiro "
    "(ledger_conferir_equilibrio) e estorna_id é único; o Python faz estorno parcial "
    "(ledger.py estornar_pedido). Reembolso parcial de disputa não cabe no banco.",
)
def test_a4_estorno_parcial_do_python_cabe_no_banco():
    livro = Livro()
    registrar_cobranca(livro, "p", 10_000, "c", AGORA)
    from trato.financeiro.ledger import estornar_pedido

    novos = estornar_pedido(livro, "p", 2_500, "est", AGORA)
    originais = {i.id: i for i in livro.lancamentos if i.tipo is TipoLancamento.COBRANCA}
    # No banco um estorno só é válido se valor == valor do original (inversão exata).
    for n in novos:
        assert n.valor == originais[n.estorno_de].valor
    assert CLIENTE != CUSTODIA


# --- A5 (alto): trava de idempotência da decisão compara o campo errado -----------------------


@pytest.mark.xfail(
    strict=True,
    raises=(AssertionError, ChaveReutilizada),
    reason="A5: _planejar_dinheiro() procura `i.id.startswith('disputa/<pedido>/')`, mas `id` é "
    "um uuid; o que tem o prefixo é `chave` (api/admin/rotas_disputas.py:203). A trava nunca "
    "dispara: refazer a decisão depois de falha no meio planeja o dinheiro de novo.",
)
def test_a5_refazer_a_decisao_nao_planeja_dinheiro_de_novo(amb):
    pedido = amb.semear_pedido(Estado.EM_DISPUTA, estado_antes_da_disputa=Estado.EM_CONFIRMACAO)
    registrar_cobranca(amb.contexto.ledger.livro, "ped-1", 100_000, "cob-ped-1", AGORA)
    amb.contexto.taxa = _TaxaMutavel(1_000)
    config = amb.contexto.config.carregar().disputas
    aberta = disputas.abrir(
        disputas.Ator.CLIENTE, 100_000, disputas.Motivo.MAL_FEITO, AGORA, AGORA, config
    )
    decidida = replace(aberta, estado=disputas.Estado.EM_ANALISE).decidir(
        disputas.Ator.ANALISTA,
        "eq-1",
        Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=2_500),
        AGORA,
        10**9,
    )

    primeiro = _planejar_dinheiro(amb.contexto, pedido, decidida)
    amb.contexto.ledger.lancar_varios(primeiro)  # a falha veio DEPOIS daqui (ex.: banco caiu)
    assert primeiro

    assert _planejar_dinheiro(amb.contexto, pedido, decidida) == []


# --- A2 (continuação): decisão de disputa pela rota do app ------------------------------------


def test_a2_equipe_sem_permissao_nao_decide_disputa(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    decisao = {"resultado": "reembolso_total", "justificativa": "teste"}

    # "t-equipe" não está na tabela `equipe` com DISPUTAS_DECIDIR neste ambiente.
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-equipe", decisao)

    assert r.status_code == 403


# --- A7 (alto): estorno no Stripe antes do ledger -------------------------------------------------


@pytest.mark.xfail(
    strict=True,
    raises=(AssertionError, ChaveReutilizada),
    reason="A7: aplicar_dinheiro() estorna no provedor e soma `estornado_centavos` ANTES de gravar "
    "no ledger (pagamentos/orquestrador.py:289-322). Se o ledger falha, o dinheiro já saiu e a "
    "retentativa dá ErroFluxo('Não há pagamento confirmado suficiente').",
)
def test_a7_falha_no_ledger_depois_do_estorno_pode_ser_repetida(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    decisao = {"resultado": "reembolso_total", "justificativa": "Serviço não feito."}
    original = fluxo.ctx.ledger.lancar_varios

    def falha(_lancamentos):
        raise RuntimeError("banco caiu")

    fluxo.ctx.ledger.lancar_varios = falha
    with pytest.raises(RuntimeError):
        fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-mediador", decisao)
    fluxo.ctx.ledger.lancar_varios = original  # o banco voltou

    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-mediador", decisao)

    assert r.status_code == 200
    assert VALOR == 100_000


# --- A6 (alto): transição sem compare-and-set -----------------------------------------------------


@pytest.mark.xfail(
    strict=True,
    raises=(AssertionError, ChaveReutilizada),
    reason="A6: PedidosPostgres._salvar atualiza `where id = %s and status <> %s` "
    "(persistencia/pedidos.py:204): não confere o estado ANTERIOR lido pela rota; duas "
    "requisições simultâneas passam na máquina de estados e a última grava por cima.",
)
def test_a6_atualizacao_do_pedido_confere_o_estado_anterior():
    fonte = (RAIZ / "backend/src/trato/persistencia/pedidos.py").read_text(encoding="utf-8")
    trecho = fonte[fonte.index("update public.pedidos set status") :][:200]
    # Esperado: `where id = %s and status = %s` (estado lido) e rowcount == 0 vira 409.
    assert re.search(r"and status = %s", trecho)


# --- A8 (alto): documentos de verificação lidos direto pela equipe ---------------------------------


def test_a8_equipe_nao_le_documentos_direto_no_storage():
    # As migrations já aplicadas não mudam: o fechamento vem em migration NOVA (em arquivo).
    novas = sorted((RAIZ / "supabase/migrations").glob("*_fix_acesso_*.sql"))
    assert novas, "migration nova do fix-acesso não encontrada"
    sql = "\n".join(p.read_text(encoding="utf-8") for p in novas)
    assert "drop policy if exists trato_verificacao_leitura on storage.objects" in sql
    assert "drop policy if exists verificacao_documentos_select on public.verificacao_documentos" in sql
