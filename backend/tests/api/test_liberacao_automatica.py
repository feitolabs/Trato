"""TERMOS-BE-LIBERA (5.8, 8.6, 15.3): o agendador, com a configuração real da API, libera o
saldo e lembra do fim da janela. Memória."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import datetime, timedelta

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_agendador import montar
from test_ausencia_cliente import painel
from test_fluxo_pagamento_e2e import _abrir_e_responder_disputa, fluxo  # noqa: F401
from test_provas_ausencia import com_retencao

from trato.agendador.executor import Adiada, ExecutorContexto, config_rotinas_da_api
from trato.api.admin.rotas_disputas import _na_situacao
from trato.disputas import Ator, Decisao, Motivo, Resultado, abrir
from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.financeiro.ledger import TipoLancamento
from trato.pedidos.estados import Estado
from trato.persistencia.cancelamentos import EM_ANALISE, PROPOSTA, Cancelamento
from trato.persistencia.contestacoes_decisao import ContestacaoDecisao
from trato.persistencia.sac import Chamado, MensagemChamado
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

H = timedelta(hours=1)
D = timedelta(days=1)
VALOR = 92_500


def configurar(amb, **mudancas) -> None:
    config = amb.contexto.config
    config._config = replace(config.carregar(), **mudancas)


def concluido(amb, ha=10 * D, dias: int | None = 7) -> None:
    configurar(amb, prazo_liberacao_dias=dias)
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - ha)
    amb.semear_dinheiro(taxa=7_500)


def saldo(amb) -> tuple[int, int]:
    s = amb.contexto.ledger.saldos_pedido("ped-1", PROFISSIONAL.id)
    return s.a_liberar, s.liberado


def repasses(amb) -> int:
    lancamentos = amb.contexto.ledger.lancamentos("ped-1")
    return sum(i.tipo is TipoLancamento.REPASSE for i in lancamentos)


def test_sem_prazo_publicado_nao_libera_e_a_tela_nao_promete(amb):
    concluido(amb, ha=90 * D, dias=None)
    assert config_rotinas_da_api(amb.contexto).prazo_liberacao is None
    agendador, _, _ = montar(amb)
    assert agendador.rodar_uma_vez().executadas == 0 and saldo(amb) == (VALOR, 0)
    carteira = amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-prof")).json()
    assert carteira["proxima_liberacao_em"] is None


@pytest.mark.parametrize("dias,espera", [(7, 7 * D), (0, 72 * H), (1, 72 * H)])
def test_libera_no_limite_a_mesma_data_da_tela_e_nao_repete(amb, dias, espera):
    concluido(amb, ha=timedelta(0), dias=dias)
    carteira = amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-prof")).json()
    previsto = (AGORA + espera).isoformat().replace("+00:00", "Z")
    assert carteira["proxima_liberacao_em"] == previsto
    agendador, _, _ = montar(amb)
    amb.relogio.agora = AGORA + espera - timedelta(seconds=1)
    assert agendador.rodar_uma_vez().executadas == 0
    amb.relogio.agora = AGORA + espera
    assert agendador.rodar_uma_vez().executadas == 1
    assert saldo(amb) == (0, VALOR)
    assert agendador.rodar_uma_vez().executadas == 0
    outro, _, _ = montar(amb)  # outra instância, sem o registro da primeira
    assert outro.rodar_uma_vez().executadas == 0 and repasses(amb) == 1


def disputa_aberta(amb) -> None:
    config = amb.contexto.config.carregar().disputas
    nova = abrir(Ator.CLIENTE, 100_000, Motivo.MAL_FEITO, AGORA - 10 * D, AGORA - 10 * D, config)
    amb.contexto.disputas.salvar("ped-1", nova)


def cartao(amb, status=StatusContestacao.ABERTA) -> None:
    amb.contexto.contestacoes.salvar(
        Contestacao("dp_1", 100_000, status, AGORA, AGORA, pedido_id="ped-1")
    )


def caso(amb, status) -> None:
    amb.contexto.cancelamentos.registrar(
        Cancelamento("ped-1", CLIENTE.id, "cliente_ausente", status, AGORA - 10 * D)
    )


@pytest.mark.parametrize(
    "impedir",
    [
        disputa_aberta,
        cartao,
        lambda amb: cartao(amb, StatusContestacao.EM_ANALISE),
        lambda amb: caso(amb, EM_ANALISE),
        lambda amb: caso(amb, PROPOSTA),
    ],
    ids=["disputa", "cartao_aberta", "cartao_em_analise", "desistencia", "retencao"],
)
def test_com_caso_em_aberto_nao_libera_nem_marca(amb, impedir):
    concluido(amb)
    impedir(amb)
    agendador, _, registro = montar(amb)
    resultado = agendador.rodar_uma_vez()
    assert (resultado.executadas, resultado.falhas) == (0, 0)
    assert saldo(amb) == (VALOR, 0) and registro.ja_executadas() == frozenset()


def test_cartao_ganho_libera_no_ciclo_seguinte(amb):
    concluido(amb)
    cartao(amb)
    agendador, _, _ = montar(amb)
    assert agendador.rodar_uma_vez().executadas == 0
    cartao(amb, StatusContestacao.GANHA)
    assert agendador.rodar_uma_vez().executadas == 1 and saldo(amb) == (0, VALOR)


def test_decisao_contestada_segura_ate_a_resposta(amb):
    concluido(amb)
    disputa_aberta(amb)
    aberta = amb.contexto.disputas.obter("ped-1")
    decidida = replace(
        aberta,
        estado=type(aberta.estado).DECIDIDA,
        decisao=Decisao(Resultado.LIBERAR_TUDO),
        decidido_por="eq-med",
        decidido_em=AGORA - 30 * D,  # o prazo para contestar já passou
    )
    amb.contexto.disputas.salvar("ped-1", decidida)
    repo = amb.contexto.contestacoes_decisao
    item, _ = repo.inserir(
        ContestacaoDecisao(
            "disputa-1", "ped-1", CLIENTE.id, "Faltou olhar.", "app", AGORA, AGORA, AGORA
        )
    )
    agendador, _, _ = montar(amb)
    assert agendador.rodar_uma_vez().executadas == 0 and saldo(amb) == (VALOR, 0)
    repo.atualizar(replace(item, status="mantida"), "aberta")
    assert agendador.rodar_uma_vez().executadas == 1 and saldo(amb) == (0, VALOR)


def acao(valor=VALOR) -> AcaoRotina:
    return AcaoRotina(
        TipoAcaoRotina.LIBERAR_SALDO,
        "ped-1",
        f"liberacao:ped-1:{valor}",
        valor_centavos=valor,
        profissional_id=PROFISSIONAL.id,
    )


def test_acao_velha_nao_libera_valor_que_mudou(amb):
    concluido(amb)
    with pytest.raises(Adiada, match="saldo_mudou"):
        ExecutorContexto(amb.contexto).executar(acao(VALOR + 1), AGORA)
    assert saldo(amb) == (VALOR, 0)


def test_compensacao_roda_na_mesma_liberacao_uma_vez(amb, monkeypatch):
    concluido(amb)
    chamadas: list[tuple[str, str]] = []
    monkeypatch.setattr(
        amb.contexto.compensacoes, "aplicar", lambda p, chave: chamadas.append((p, chave))
    )
    agendador, _, _ = montar(amb)
    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    (repasse,) = [
        i for i in amb.contexto.ledger.lancamentos("ped-1") if i.tipo is TipoLancamento.REPASSE
    ]
    assert chamadas == [("ped-1", f"repasse:{repasse.id}")]


def test_execucoes_ao_mesmo_tempo_geram_um_repasse(amb):
    concluido(amb)
    executor = ExecutorContexto(amb.contexto)
    erros: list[Exception] = []

    def rodar() -> None:
        try:
            executor.executar(acao(), AGORA)
        except Exception as erro:  # noqa: BLE001 - o teste confere que não houve
            erros.append(erro)

    fios = [threading.Thread(target=rodar) for _ in range(6)]
    [f.start() for f in fios]
    [f.join(10) for f in fios]
    assert erros == [] and repasses(amb) == 1 and saldo(amb) == (0, VALOR)


@pytest.mark.parametrize("falta,avisa", [(13 * H, 0), (12 * H, 1), (1 * H, 1), (-1 * H, 0)])
def test_lembrete_antes_do_fim_da_janela_com_a_configuracao_real(amb, falta, avisa):
    prazo = amb.contexto.config.carregar().prazos_pedido.confirmacao_cliente
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - (prazo - falta))
    agendador, notif, _ = montar(amb)

    def lembretes():
        return [
            n
            for n in notif.repo.listar(CLIENTE.id, False, 20)
            if n.tipo == "execucao.confirmar_conclusao" and "termina em" in (n.corpo or "")
        ]

    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    assert len(lembretes()) == avisa


def test_antecedencia_zero_desliga_e_janela_curta_avisa_na_metade(amb):
    prazo = amb.contexto.config.carregar().prazos_pedido.confirmacao_cliente
    configurar(amb, lembrete_confirmacao_antecedencia_horas=0)
    assert config_rotinas_da_api(amb.contexto).lembrete_confirmacao_apos is None
    configurar(amb, lembrete_confirmacao_antecedencia_horas=10_000)
    assert config_rotinas_da_api(amb.contexto).lembrete_confirmacao_apos == prazo / 2


# --- LIB2A: 5.8 (confirmação) e 8.7 (prazo para contestar) ----------------------------------------


def liberado_de(f, pid) -> int:
    return f.ctx.ledger.saldos_pedido(pid, PROFISSIONAL.id).liberado


def carteira(f):
    r = f.chamar("GET", "/v1/profissionais/me/saldo", "t-prof")
    return r.json()["proxima_liberacao_em"]


def agendador_de(f):
    configurar(f.amb, prazo_liberacao_dias=0)
    return montar(f.amb)[0]


def test_confirmacao_do_cliente_libera_sem_esperar_o_congelamento(fluxo):  # noqa: F811
    agendador = agendador_de(fluxo)
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    concluido_em = fluxo.ctx.pedidos.obter(pid).concluido_em
    assert datetime.fromisoformat(carteira(fluxo)) == concluido_em
    agendador.rodar_uma_vez()
    valor = liberado_de(fluxo, pid)
    assert valor > 0
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) == valor


def test_silencio_ate_o_fim_da_janela_confirma_e_libera(fluxo):  # noqa: F811
    agendador = agendador_de(fluxo)
    pid = fluxo.ate_em_confirmacao()
    prazo = fluxo.ctx.config.carregar().prazos_pedido.confirmacao_cliente
    fim = fluxo.ctx.pedidos.obter(pid).check_out_em + prazo
    fluxo.amb.relogio.agora = fim - timedelta(seconds=1)
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) == 0
    fluxo.amb.relogio.agora = fim
    agendador.rodar_uma_vez()  # confirma
    agendador.rodar_uma_vez()  # libera
    assert fluxo.pedido(pid)["estado"] == "concluido" and liberado_de(fluxo, pid) > 0


def test_relato_aberto_segura(fluxo):  # noqa: F811
    agendador = agendador_de(fluxo)
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    fluxo.amb.relogio.avancar(days=60)
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) == 0


def test_disputa_decidida_segura_ate_acabar_o_prazo_de_contestar(fluxo):  # noqa: F811
    agendador = agendador_de(fluxo)
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    decisao = {"resultado": "liberar_tudo", "justificativa": "Serviço entregue."}
    url = f"/v1/pedidos/{pid}/disputa/decisao"
    assert fluxo.chamar("POST", url, "t-mediador", decisao).status_code == 200
    url = f"/v1/pedidos/{pid}/disputa/contestacoes"
    limite = datetime.fromisoformat(fluxo.chamar("GET", url, "t-cliente").json()["contestar_ate"])
    assert datetime.fromisoformat(carteira(fluxo)) == limite + timedelta(microseconds=1)
    fluxo.amb.relogio.agora = limite
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) == 0
    corpo = {"o_que_faltou": "A análise não considerou as fotos."}
    assert fluxo.chamar("POST", url, "t-cliente", corpo).status_code == 201
    fluxo.amb.relogio.avancar(days=30)
    agendador.rodar_uma_vez()  # pendente: continua retido e sem data
    assert liberado_de(fluxo, pid) == 0 and carteira(fluxo) is None
    repo = fluxo.ctx.contestacoes_decisao
    (item,) = repo.listar(pedido_id=pid)[0]
    repo.atualizar(replace(item, status="mantida"), "aberta")
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) > 0


# --- DIN3: acordo (8.2) e retenção de ausência (8.7) ------------------------------------------------


def test_acordo_fecha_a_disputa_e_libera_uma_vez(fluxo):  # noqa: F811
    agendador = agendador_de(fluxo)
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    r = fluxo.acao(pid, "encerrar_disputa_por_acordo", "t-cliente")
    assert r.status_code == 200, r.text
    disputa = fluxo.ctx.disputas.obter(pid)
    assert disputa.estado.value == "acordo" and disputa.encerrada and disputa.decisao is None
    assert _na_situacao(disputa, None, "decididas")  # sai da fila de abertas do painel
    assert not _na_situacao(disputa, None, "abertas")
    agendador.rodar_uma_vez()
    valor = liberado_de(fluxo, pid)
    assert valor > 0
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) == valor


def test_acordo_antigo_sem_registro_fechado_tambem_libera(fluxo):  # noqa: F811
    agendador = agendador_de(fluxo)
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    antiga = fluxo.ctx.disputas.obter(pid)
    fluxo.acao(pid, "encerrar_disputa_por_acordo", "t-cliente")
    fluxo.ctx.disputas.salvar(pid, antiga)  # como ficou gravado antes da correção
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) > 0


def test_retencao_confirmada_libera_depois_do_prazo_de_contestar(fluxo):  # noqa: F811
    configurar(fluxo.amb, prazo_liberacao_dias=0)
    pid, _, _ = com_retencao(fluxo)
    fluxo.amb.relogio.avancar(days=10)
    assert painel(fluxo, pid, rota="confirmar").status_code == 200
    agendador = montar(fluxo.amb)[0]
    limite = datetime.fromisoformat(carteira(fluxo)) - timedelta(microseconds=1)
    fluxo.amb.relogio.agora = limite
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) == 0
    fluxo.amb.relogio.agora = limite + timedelta(seconds=1)
    agendador.rodar_uma_vez()
    valor = liberado_de(fluxo, pid)
    assert valor > 0 and fluxo.pedido(pid)["estado"] == "cancelado"
    agendador.rodar_uma_vez()
    assert liberado_de(fluxo, pid) == valor


def test_retencao_com_chargeback_segura(fluxo):  # noqa: F811
    configurar(fluxo.amb, prazo_liberacao_dias=0)
    pid, _, _ = com_retencao(fluxo)
    fluxo.amb.relogio.avancar(days=10)
    assert painel(fluxo, pid, rota="confirmar").status_code == 200
    agora = fluxo.amb.relogio.agora
    fluxo.ctx.contestacoes.salvar(
        Contestacao("dp_r", 100, StatusContestacao.ABERTA, agora, agora, pedido_id=pid)
    )
    fluxo.amb.relogio.avancar(days=30)
    montar(fluxo.amb)[0].rodar_uma_vez()
    assert liberado_de(fluxo, pid) == 0


# --- RETEM (8.8 e 9.6): relato de dano ou de segurança segura o valor --------------------------------


def incidente(amb) -> None:
    amb.contexto.chamados.incidentes.add("ped-1")


def chamado_de_seguranca(amb, status="aberto"):
    chamado = Chamado(
        "seguranca", "Dano no imóvel", "app", AGORA, AGORA, usuario_id=CLIENTE.id,
        pedido_id="ped-1", status=status,
    )  # fmt: skip
    return amb.contexto.sac.abrir(chamado, MensagemChamado("usuario", "Quebrou.", AGORA))[0]


def denuncia(amb, severidade="alta", pedido="ped-1", texto="x") -> None:
    amb.contexto.denuncias.registrar(
        PROFISSIONAL.id, pedido, "denuncia_chat", severidade, texto, AGORA
    )


@pytest.mark.parametrize(
    "relatar",
    [
        incidente,
        chamado_de_seguranca,
        denuncia,
        lambda amb: denuncia(amb, pedido=None, texto="Pedido ped-1: de novo"),
    ],
    ids=["incidente", "chamado", "denuncia", "denuncia_sem_vinculo"],
)
def test_relato_aberto_segura_sem_marcar_e_sem_prometer_data(amb, relatar):
    concluido(amb)
    relatar(amb)
    agendador, _, registro = montar(amb)
    resultado = agendador.rodar_uma_vez()
    assert (resultado.executadas, resultado.falhas) == (0, 0)
    assert saldo(amb) == (VALOR, 0) and registro.ja_executadas() == frozenset()
    carteira_ = amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-prof")).json()
    assert carteira_["proxima_liberacao_em"] is None
    with pytest.raises(Adiada, match="relato_de_seguranca"):
        ExecutorContexto(amb.contexto).executar(acao(), AGORA)


def test_analise_terminada_libera_uma_vez(amb):
    concluido(amb)
    incidente(amb)
    agendador, _, _ = montar(amb)
    assert agendador.rodar_uma_vez().executadas == 0
    amb.contexto.chamados.incidentes.clear()
    assert agendador.rodar_uma_vez().executadas == 1
    assert agendador.rodar_uma_vez().executadas == 0 and repasses(amb) == 1


@pytest.mark.parametrize(
    "sem_efeito",
    [
        lambda amb: chamado_de_seguranca(amb, "encerrado"),
        lambda amb: denuncia(amb, "media"),
        lambda amb: denuncia(amb, pedido="outro-pedido"),
    ],
    ids=["chamado_encerrado", "denuncia_media", "outro_pedido"],
)
def test_o_que_nao_e_relato_aberto_do_pedido_nao_segura(amb, sem_efeito):
    concluido(amb)
    sem_efeito(amb)
    assert montar(amb)[0].rodar_uma_vez().executadas == 1 and saldo(amb) == (0, VALOR)
