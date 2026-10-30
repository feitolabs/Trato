from dataclasses import replace
from datetime import UTC, datetime, timedelta

import pytest

from trato.pedidos.estados import (
    Acao,
    Ator,
    AtorNaoAutorizado,
    DecisaoDisputa,
    Estado,
    EstadoInvalido,
    ForaDoPrazo,
    Foto,
    Janela,
    Localizacao,
    MotivoDisputa,
    Papel,
    PrazoNaoConfigurado,
    PrazosPedido,
    ProvaAceite,
    ProvaAgenda,
    ProvaCancelamento,
    ProvaCheckIn,
    ProvaCheckOut,
    ProvaDisputa,
    ProvaInvalida,
    ProvaPagamento,
    ProvaRemarcacao,
    ProvaRetrabalho,
    ResultadoDisputa,
    abrir_pedido,
    acoes_permitidas,
    transicionar,
)

T0 = datetime(2026, 11, 2, 9, 0, tzinfo=UTC)
CLIENTE = Ator(Papel.CLIENTE, "c1")
PROF = Ator(Papel.PROFISSIONAL, "p1")
SISTEMA = Ator(Papel.SISTEMA, "sistema")
MEDIADOR = Ator(Papel.MEDIADOR, "m1")
# Prazos só de teste: no sistema real vêm da tabela de configuração.
PRAZOS = PrazosPedido(
    receber_orcamentos=timedelta(hours=1),
    pagamento=timedelta(hours=1),
    tolerancia_comparecimento=timedelta(hours=1),
    confirmacao_cliente=timedelta(hours=1),
    garantia=timedelta(days=1),
)
JANELA = Janela(T0 + timedelta(days=1), T0 + timedelta(days=1, hours=3))
FOTO = Foto("foto-1", T0)


def codigos():
    return iter(["1111", "2222", "3333", "4444"]).__next__


def ir(pedido, acao, ator, agora=T0, prova=None, prazos=PRAZOS):
    return transicionar(pedido, acao, ator, agora, prova, prazos, codigos()).pedido


def aberto():
    return abrir_pedido("ped1", CLIENTE, T0)


def aceito():
    return ir(aberto(), Acao.ACEITAR_ORCAMENTO, CLIENTE, prova=ProvaAceite("orc1", "p1"))


def pago():
    return ir(aceito(), Acao.CONFIRMAR_PAGAMENTO, SISTEMA, prova=ProvaPagamento("pi_1"))


def agendado():
    return ir(pago(), Acao.CONFIRMAR_AGENDA, PROF, prova=ProvaAgenda(JANELA))


def em_andamento():
    p = agendado()
    prova = ProvaCheckIn(FOTO, Localizacao(-19.9, -43.9), p.codigo_inicio)
    return ir(p, Acao.FAZER_CHECK_IN, PROF, JANELA.inicio, prova)


def em_confirmacao():
    p = em_andamento()
    prova = ProvaCheckOut(FOTO, p.codigo_conclusao)
    return ir(p, Acao.FAZER_CHECK_OUT, PROF, JANELA.fim, prova)


def concluido():
    return ir(em_confirmacao(), Acao.CONFIRMAR_CONCLUSAO, CLIENTE, JANELA.fim)


def disputa():
    prova = ProvaDisputa(MotivoDisputa.MAL_FEITO, "Vazamento")
    return ir(em_confirmacao(), Acao.ABRIR_DISPUTA, CLIENTE, JANELA.fim, prova)


# --- Transições válidas ---------------------------------------------------------------


def test_so_cliente_abre_pedido():
    assert aberto().estado is Estado.ABERTO
    with pytest.raises(AtorNaoAutorizado):
        abrir_pedido("x", PROF, T0)


def test_aceitar_orcamento():
    p = aceito()
    assert p.estado is Estado.ORCAMENTO_ACEITO
    assert p.profissional_id == "p1" and p.aceito_em == T0


def test_pagamento_confirmado_pelo_sistema_retem():
    assert pago().estado is Estado.PAGO_E_RETIDO


def test_confirmar_agenda_gera_codigo_de_inicio():
    p = agendado()
    assert p.estado is Estado.AGENDADO
    assert p.codigo_inicio == "1111" and p.janela == JANELA


def test_remarcar_com_aceite_da_outra_parte():
    nova = Janela(JANELA.inicio + timedelta(days=1), JANELA.fim + timedelta(days=1))
    p = ir(agendado(), Acao.REMARCAR, CLIENTE, prova=ProvaRemarcacao(nova, "p1"))
    assert p.estado is Estado.AGENDADO and p.janela == nova
    p = ir(agendado(), Acao.REMARCAR, PROF, prova=ProvaRemarcacao(nova, "c1"))
    assert p.janela == nova


def test_check_in_inicia_servico():
    p = em_andamento()
    assert p.estado is Estado.EM_ANDAMENTO and p.codigo_conclusao is not None


def test_check_out_vai_para_confirmacao():
    assert em_confirmacao().estado is Estado.EM_CONFIRMACAO


def test_cliente_confirma_conclusao():
    p = concluido()
    assert p.estado is Estado.CONCLUIDO and p.concluido_em == JANELA.fim


def test_conclusao_automatica_depois_do_prazo():
    p = em_confirmacao()
    depois = p.check_out_em + PRAZOS.confirmacao_cliente
    assert ir(p, Acao.CONCLUIR_POR_PRAZO, SISTEMA, depois).estado is Estado.CONCLUIDO


def test_pedido_sem_orcamento_expira():
    p = ir(aberto(), Acao.EXPIRAR_PEDIDO, SISTEMA, T0 + PRAZOS.receber_orcamentos)
    assert p.estado is Estado.CANCELADO


def test_pagamento_nao_feito_volta_para_aberto():
    p = ir(aceito(), Acao.EXPIRAR_PAGAMENTO, SISTEMA, T0 + PRAZOS.pagamento)
    assert p.estado is Estado.ABERTO
    assert p.profissional_id is None and p.orcamento_id is None


def test_ausencia_do_profissional_cancela():
    p = agendado()
    depois = JANELA.fim + PRAZOS.tolerancia_comparecimento
    assert ir(p, Acao.REGISTRAR_AUSENCIA, SISTEMA, depois).estado is Estado.CANCELADO


@pytest.mark.parametrize(
    ("construir", "ator"),
    [
        (aberto, CLIENTE),
        (aceito, CLIENTE),
        (pago, CLIENTE),
        (pago, PROF),
        (agendado, CLIENTE),
        (agendado, PROF),
    ],
)
def test_cancelar_antes_do_inicio(construir, ator):
    p = ir(construir(), Acao.CANCELAR, ator, prova=ProvaCancelamento("mudei de ideia"))
    assert p.estado is Estado.CANCELADO


@pytest.mark.parametrize("construir", [agendado, em_andamento, em_confirmacao])
def test_cliente_abre_disputa_e_lembra_estado_anterior(construir):
    origem = construir()
    prova = ProvaDisputa(MotivoDisputa.ABANDONO, "Sumiu", (FOTO,))
    p = ir(origem, Acao.ABRIR_DISPUTA, CLIENTE, JANELA.fim, prova)
    assert p.estado is Estado.EM_DISPUTA
    assert p.estado_antes_da_disputa is origem.estado


def test_disputa_encerrada_por_acordo_conclui():
    assert ir(disputa(), Acao.ENCERRAR_DISPUTA_POR_ACORDO, CLIENTE).estado is Estado.CONCLUIDO


@pytest.mark.parametrize(
    ("resultado", "esperado"),
    [
        (ResultadoDisputa.LIBERAR_TUDO, Estado.CONCLUIDO),
        (ResultadoDisputa.REEMBOLSO_PARCIAL, Estado.CONCLUIDO),
        (ResultadoDisputa.REEMBOLSO_TOTAL, Estado.CANCELADO),
        (ResultadoDisputa.NOVA_VISITA, Estado.RETRABALHO),
    ],
)
def test_mediador_decide_disputa(resultado, esperado):
    p = ir(disputa(), Acao.DECIDIR_DISPUTA, MEDIADOR, prova=DecisaoDisputa(resultado, "Provas"))
    assert p.estado is esperado


def test_retrabalho_dentro_da_garantia_e_novo_check_out():
    c = concluido()
    prova = ProvaRetrabalho("Voltou a vazar", (FOTO,))
    r = ir(c, Acao.PEDIR_RETRABALHO, CLIENTE, c.concluido_em + timedelta(hours=5), prova)
    assert r.estado is Estado.RETRABALHO and r.codigo_conclusao is not None
    saida = ProvaCheckOut(FOTO, r.codigo_conclusao)
    r = ir(r, Acao.FAZER_CHECK_OUT, PROF, c.concluido_em + timedelta(hours=6), saida)
    assert r.estado is Estado.EM_CONFIRMACAO
    r = ir(r, Acao.CONFIRMAR_CONCLUSAO, CLIENTE, c.concluido_em + timedelta(hours=7))
    assert r.estado is Estado.CONCLUIDO
    assert r.concluido_em == c.concluido_em  # garantia não é renovada


def test_evento_de_auditoria():
    p = em_andamento()
    t = transicionar(
        p, Acao.FAZER_CHECK_OUT, PROF, JANELA.fim, ProvaCheckOut(FOTO, p.codigo_conclusao)
    )
    assert (t.evento.de, t.evento.para) == (Estado.EM_ANDAMENTO, Estado.EM_CONFIRMACAO)
    assert t.evento.ator == PROF and t.evento.pedido_id == "ped1"


def test_acoes_permitidas():
    assert acoes_permitidas(aberto(), Papel.CLIENTE) == {Acao.ACEITAR_ORCAMENTO, Acao.CANCELAR}
    assert acoes_permitidas(agendado(), Papel.PROFISSIONAL) >= {Acao.FAZER_CHECK_IN}
    assert acoes_permitidas(concluido(), Papel.PROFISSIONAL) == set()


# --- Quem ----------------------------------------------------------------------------


def test_profissional_nao_aceita_orcamento():
    with pytest.raises(AtorNaoAutorizado, match="Profissional não pode aceitar o orçamento"):
        ir(aberto(), Acao.ACEITAR_ORCAMENTO, PROF, prova=ProvaAceite("o", "p1"))


def test_cliente_nao_faz_check_in():
    p = agendado()
    prova = ProvaCheckIn(FOTO, Localizacao(0, 0), p.codigo_inicio)
    with pytest.raises(AtorNaoAutorizado):
        ir(p, Acao.FAZER_CHECK_IN, CLIENTE, JANELA.inicio, prova)


def test_profissional_de_outro_pedido_nao_faz_check_in():
    p = agendado()
    prova = ProvaCheckIn(FOTO, Localizacao(0, 0), p.codigo_inicio)
    with pytest.raises(AtorNaoAutorizado, match="profissional contratado"):
        ir(p, Acao.FAZER_CHECK_IN, Ator(Papel.PROFISSIONAL, "outro"), JANELA.inicio, prova)


def test_cliente_de_outro_pedido_nao_confirma():
    with pytest.raises(AtorNaoAutorizado, match="cliente deste pedido"):
        ir(em_confirmacao(), Acao.CONFIRMAR_CONCLUSAO, Ator(Papel.CLIENTE, "outro"))


def test_cliente_nao_confirma_pagamento_sozinho():
    with pytest.raises(AtorNaoAutorizado):
        ir(aceito(), Acao.CONFIRMAR_PAGAMENTO, CLIENTE, prova=ProvaPagamento("pi_1"))


def test_so_mediador_decide_disputa():
    decisao = DecisaoDisputa(ResultadoDisputa.LIBERAR_TUDO, "x")
    for ator in (CLIENTE, PROF, SISTEMA):
        with pytest.raises(AtorNaoAutorizado):
            ir(disputa(), Acao.DECIDIR_DISPUTA, ator, prova=decisao)


def test_mediador_nao_decide_pedido_em_que_e_parte():
    p = replace(disputa(), cliente_id="m1")
    with pytest.raises(AtorNaoAutorizado, match="é parte"):
        decisao = DecisaoDisputa(ResultadoDisputa.LIBERAR_TUDO, "x")
        ir(p, Acao.DECIDIR_DISPUTA, MEDIADOR, prova=decisao)


def test_profissional_nao_abre_disputa():
    prova = ProvaDisputa(MotivoDisputa.DANO, "x")
    with pytest.raises(AtorNaoAutorizado):
        ir(em_andamento(), Acao.ABRIR_DISPUTA, PROF, prova=prova)


# --- Quando (estado de origem) -------------------------------------------------------


def test_check_in_sem_agendar_e_invalido():
    prova = ProvaCheckIn(FOTO, Localizacao(0, 0), "1111")
    with pytest.raises(EstadoInvalido, match="com o pedido em Pago e retido"):
        ir(pago(), Acao.FAZER_CHECK_IN, PROF, prova=prova)


def test_nao_confirma_conclusao_em_andamento():
    with pytest.raises(EstadoInvalido):
        ir(em_andamento(), Acao.CONFIRMAR_CONCLUSAO, CLIENTE)


def test_nao_aceita_orcamento_duas_vezes():
    with pytest.raises(EstadoInvalido):
        ir(aceito(), Acao.ACEITAR_ORCAMENTO, CLIENTE, prova=ProvaAceite("o2", "p2"))


@pytest.mark.parametrize("acao", list(Acao))
def test_cancelado_e_final(acao):
    c = ir(aberto(), Acao.CANCELAR, CLIENTE, prova=ProvaCancelamento("x"))
    for ator in (CLIENTE, PROF, SISTEMA, MEDIADOR):
        with pytest.raises(Exception) as erro:  # noqa: B017 - qualquer TransicaoInvalida
            transicionar(c, acao, ator, T0, None, PRAZOS)
        assert type(erro.value).__module__ == "trato.pedidos.estados"


def test_cliente_nao_cancela_depois_do_inicio():
    with pytest.raises(EstadoInvalido):
        ir(em_andamento(), Acao.CANCELAR, CLIENTE, prova=ProvaCancelamento("x"))


def test_concluido_so_aceita_retrabalho():
    c = concluido()
    assert acoes_permitidas(c, Papel.CLIENTE) == {Acao.PEDIR_RETRABALHO}
    with pytest.raises(EstadoInvalido):
        ir(c, Acao.ABRIR_DISPUTA, CLIENTE, prova=ProvaDisputa(MotivoDisputa.DANO, "x"))


# --- Prova ---------------------------------------------------------------------------


def _check_in(**mudancas):
    p = agendado()
    base = ProvaCheckIn(FOTO, Localizacao(-19.9, -43.9), p.codigo_inicio)
    return p, replace(base, **mudancas)


def test_check_in_com_codigo_errado():
    p, prova = _check_in(codigo_inicio="0000")
    with pytest.raises(ProvaInvalida, match="código de início não confere"):
        ir(p, Acao.FAZER_CHECK_IN, PROF, JANELA.inicio, prova)


def test_check_in_sem_foto():
    p, prova = _check_in(foto=Foto("", T0))
    with pytest.raises(ProvaInvalida, match="foto do check-in"):
        ir(p, Acao.FAZER_CHECK_IN, PROF, JANELA.inicio, prova)


def test_check_in_com_localizacao_invalida():
    p, prova = _check_in(localizacao=Localizacao(95, 0))
    with pytest.raises(ProvaInvalida, match="Localização"):
        ir(p, Acao.FAZER_CHECK_IN, PROF, JANELA.inicio, prova)


def test_check_in_com_foto_do_futuro():
    p, prova = _check_in(foto=Foto("f", JANELA.inicio + timedelta(hours=1)))
    with pytest.raises(ProvaInvalida, match="futuro"):
        ir(p, Acao.FAZER_CHECK_IN, PROF, JANELA.inicio, prova)


def test_check_in_sem_prova():
    with pytest.raises(ProvaInvalida, match="ProvaCheckIn"):
        ir(agendado(), Acao.FAZER_CHECK_IN, PROF, JANELA.inicio)


def test_check_in_com_prova_de_outro_tipo():
    with pytest.raises(ProvaInvalida):
        ir(agendado(), Acao.FAZER_CHECK_IN, PROF, JANELA.inicio, ProvaCancelamento("x"))


def test_check_out_com_codigo_errado():
    with pytest.raises(ProvaInvalida, match="código de conclusão não confere"):
        ir(em_andamento(), Acao.FAZER_CHECK_OUT, PROF, JANELA.fim, ProvaCheckOut(FOTO, "0000"))


def test_check_out_sem_foto_final():
    p = em_andamento()
    prova = ProvaCheckOut(Foto("", T0), p.codigo_conclusao)
    with pytest.raises(ProvaInvalida, match="foto final"):
        ir(p, Acao.FAZER_CHECK_OUT, PROF, JANELA.fim, prova)


def test_acao_sem_prova_nao_aceita_prova():
    with pytest.raises(ProvaInvalida, match="não se envia prova"):
        ir(em_confirmacao(), Acao.CONFIRMAR_CONCLUSAO, CLIENTE, prova=ProvaCancelamento("x"))


def test_orcamento_sem_profissional():
    with pytest.raises(ProvaInvalida):
        ir(aberto(), Acao.ACEITAR_ORCAMENTO, CLIENTE, prova=ProvaAceite("o", ""))


def test_cliente_nao_contrata_a_si_mesmo():
    with pytest.raises(ProvaInvalida, match="a si mesmo"):
        ir(aberto(), Acao.ACEITAR_ORCAMENTO, CLIENTE, prova=ProvaAceite("o", "c1"))


def test_pagamento_sem_referencia():
    with pytest.raises(ProvaInvalida):
        ir(aceito(), Acao.CONFIRMAR_PAGAMENTO, SISTEMA, prova=ProvaPagamento(" "))


def test_agenda_no_passado_ou_invertida():
    for janela in (Janela(T0 - timedelta(hours=1), T0), Janela(T0 + timedelta(hours=2), T0)):
        with pytest.raises(ProvaInvalida):
            ir(pago(), Acao.CONFIRMAR_AGENDA, PROF, prova=ProvaAgenda(janela))


def test_remarcacao_sem_aceite_da_outra_parte():
    nova = Janela(JANELA.inicio + timedelta(days=1), JANELA.fim + timedelta(days=1))
    with pytest.raises(ProvaInvalida, match="aceite da outra parte"):
        ir(agendado(), Acao.REMARCAR, CLIENTE, prova=ProvaRemarcacao(nova, "c1"))


def test_disputa_exige_descricao():
    with pytest.raises(ProvaInvalida, match="descrição"):
        ir(em_andamento(), Acao.ABRIR_DISPUTA, CLIENTE, prova=ProvaDisputa(MotivoDisputa.DANO, " "))


def test_cancelamento_exige_motivo():
    with pytest.raises(ProvaInvalida, match="motivo"):
        ir(aberto(), Acao.CANCELAR, CLIENTE, prova=ProvaCancelamento(""))


def test_decisao_exige_justificativa():
    with pytest.raises(ProvaInvalida, match="justificativa"):
        ir(
            disputa(),
            Acao.DECIDIR_DISPUTA,
            MEDIADOR,
            prova=DecisaoDisputa(ResultadoDisputa.LIBERAR_TUDO, ""),
        )


# --- Prazo ---------------------------------------------------------------------------


def test_rotina_antes_do_prazo_e_recusada():
    with pytest.raises(ForaDoPrazo, match="ainda não venceu"):
        ir(
            aberto(),
            Acao.EXPIRAR_PEDIDO,
            SISTEMA,
            T0 + PRAZOS.receber_orcamentos - timedelta(seconds=1),
        )
    p = em_confirmacao()
    with pytest.raises(ForaDoPrazo):
        ir(p, Acao.CONCLUIR_POR_PRAZO, SISTEMA, p.check_out_em + timedelta(minutes=1))


def test_prazo_nao_configurado_nao_vira_numero_fixo():
    with pytest.raises(PrazoNaoConfigurado):
        ir(aberto(), Acao.EXPIRAR_PEDIDO, SISTEMA, T0 + timedelta(days=99), prazos=PrazosPedido())
    with pytest.raises(PrazoNaoConfigurado):
        ir(
            concluido(),
            Acao.PEDIR_RETRABALHO,
            CLIENTE,
            prova=ProvaRetrabalho("x"),
            prazos=PrazosPedido(),
        )


def test_retrabalho_fora_da_garantia():
    c = concluido()
    depois = c.concluido_em + PRAZOS.garantia + timedelta(seconds=1)
    with pytest.raises(ForaDoPrazo, match="garantia"):
        ir(c, Acao.PEDIR_RETRABALHO, CLIENTE, depois, ProvaRetrabalho("x"))


def test_data_sem_fuso_e_recusada():
    with pytest.raises(ValueError, match="fuso"):
        abrir_pedido("x", CLIENTE, datetime(2026, 1, 1))  # noqa: DTZ001
