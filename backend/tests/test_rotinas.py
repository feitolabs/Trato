from datetime import UTC, date, datetime, timedelta

import pytest

from trato.pedidos.estados import Acao, Estado, Janela, Papel, Pedido
from trato.rotinas.dias_uteis import eh_dia_util, somar_dias_uteis
from trato.rotinas.regras import (
    ConfigRotinas,
    DisputaMonitorada,
    Lembrete,
    PedidoMonitorado,
    TipoAcaoRotina,
    lembretes,
    liberacoes_por_prazo,
    prazo_confirmacao,
    rotinas_do_instante,
    transicoes_por_prazo,
)

H = timedelta(hours=1)
D = timedelta(days=1)
T0 = datetime(2026, 11, 2, 9, 0, tzinfo=UTC)  # segunda-feira

# Valores só de teste: no sistema real vêm da tabela de configuração.
CFG = ConfigRotinas(
    validade_pedido=48 * H,
    validade_pedido_urgente=2 * H,
    prazo_pagamento=2 * H,
    tolerancia_comparecimento=1 * H,
    prazo_confirmacao_cliente=48 * H,
    prazo_confirmacao_cliente_acima_do_limite=72 * H,
    limite_valor_prazo_maior_centavos=150_000,
    prazo_liberacao=7 * D,
    janela_reclamacao=7 * D,
    prazo_resposta_disputa=48 * H,
    prazo_decisao_disputa_dias_uteis=5,
    lembrete_confirmacao_apos=24 * H,
    lembrete_resposta_disputa_antecedencia=12 * H,
    lembrete_decisao_disputa_antecedencia=24 * H,
    lembrete_aditivo_apos=12 * H,
)


def pedido(estado, **campos):
    base = {"id": "ped1", "cliente_id": "c1", "aberto_em": T0, "profissional_id": "p1"}
    return Pedido(estado=estado, **{**base, **campos})


def item(estado, extras=None, **campos):
    return PedidoMonitorado(pedido(estado, **campos), **(extras or {}))


# --- Dias úteis -----------------------------------------------------------------------


def test_dias_uteis_pula_fim_de_semana():
    assert somar_dias_uteis(date(2026, 11, 2), 5) == date(2026, 11, 9)  # seg -> seg
    assert somar_dias_uteis(date(2026, 11, 6), 1) == date(2026, 11, 9)  # sex -> seg
    assert somar_dias_uteis(date(2026, 11, 7), 1) == date(2026, 11, 9)  # sáb -> seg
    assert somar_dias_uteis(date(2026, 11, 2), 0) == date(2026, 11, 2)


def test_dias_uteis_pula_feriado():
    feriados = frozenset({date(2026, 11, 3), date(2026, 11, 5)})
    assert somar_dias_uteis(date(2026, 11, 2), 2, feriados) == date(2026, 11, 6)
    assert not eh_dia_util(date(2026, 11, 3), feriados)


def test_dias_uteis_negativo_e_erro():
    with pytest.raises(ValueError):
        somar_dias_uteis(date(2026, 11, 2), -1)


# --- Expiração ------------------------------------------------------------------------


def test_pedido_sem_orcamento_expira_no_limite_exato_e_nao_antes():
    x = item(Estado.ABERTO)
    assert transicoes_por_prazo(T0 + 48 * H - timedelta(seconds=1), [x], CFG) == []
    [a] = transicoes_por_prazo(T0 + 48 * H, [x], CFG)
    assert (a.tipo, a.acao) == (TipoAcaoRotina.TRANSICIONAR, Acao.EXPIRAR_PEDIDO)


def test_pedido_urgente_usa_validade_urgente():
    x = item(Estado.ABERTO, {"urgente": True})
    assert transicoes_por_prazo(T0 + 1 * H, [x], CFG) == []
    assert len(transicoes_por_prazo(T0 + 2 * H, [x], CFG)) == 1


def test_pedido_com_orcamento_nao_expira():
    x = item(Estado.ABERTO, {"orcamentos_recebidos": 1})
    assert transicoes_por_prazo(T0 + 100 * D, [x], CFG) == []


def test_pagamento_pendente_vencido_volta_para_aberto():
    x = item(Estado.ORCAMENTO_ACEITO, aceito_em=T0)
    assert transicoes_por_prazo(T0 + 2 * H - timedelta(seconds=1), [x], CFG) == []
    [a] = transicoes_por_prazo(T0 + 2 * H, [x], CFG)
    assert a.acao is Acao.EXPIRAR_PAGAMENTO


def test_ausencia_do_profissional_depois_da_tolerancia():
    janela = Janela(T0 + D, T0 + D + 3 * H)
    x = item(Estado.AGENDADO, janela=janela)
    assert transicoes_por_prazo(janela.fim + 59 * timedelta(minutes=1), [x], CFG) == []
    [a] = transicoes_por_prazo(janela.fim + H, [x], CFG)
    assert a.acao is Acao.REGISTRAR_AUSENCIA


def test_sem_prazo_configurado_a_rotina_fica_desligada():
    vazio = ConfigRotinas()
    x = item(Estado.ABERTO)
    assert rotinas_do_instante(T0 + 999 * D, [x], vazio) == []


# --- Conclusão por prazo --------------------------------------------------------------


def test_prazo_de_confirmacao_depende_do_valor():
    assert prazo_confirmacao(150_000, CFG) == 48 * H  # no limite: ainda o menor
    assert prazo_confirmacao(150_001, CFG) == 72 * H
    assert prazo_confirmacao(0, ConfigRotinas()) is None


def test_cliente_sem_resposta_conclui_no_prazo_certo_por_valor():
    barato = item(Estado.EM_CONFIRMACAO, {"valor_servico_centavos": 100_000}, check_out_em=T0)
    caro = item(Estado.EM_CONFIRMACAO, {"valor_servico_centavos": 200_000}, check_out_em=T0)
    em_48h = T0 + 48 * H
    assert [a.acao for a in transicoes_por_prazo(em_48h, [barato, caro], CFG)] == [
        Acao.CONCLUIR_POR_PRAZO
    ]
    assert len(transicoes_por_prazo(T0 + 72 * H, [caro], CFG)) == 1


def test_disputa_aberta_impede_conclusao_por_prazo():
    x = item(Estado.EM_CONFIRMACAO, {"disputa_aberta": True}, check_out_em=T0)
    assert transicoes_por_prazo(T0 + 99 * D, [x], CFG) == []


def test_estados_sem_rotina_de_transicao():
    for estado in (Estado.EM_ANDAMENTO, Estado.PAGO_E_RETIDO, Estado.CONCLUIDO,
                   Estado.CANCELADO, Estado.EM_DISPUTA, Estado.RETRABALHO):  # fmt: skip
        assert transicoes_por_prazo(T0 + 999 * D, [item(estado)], CFG) == []


# --- Liberação ------------------------------------------------------------------------


def concluido(**extras):
    base = {"saldo_a_liberar_centavos": 9_250}
    return item(Estado.CONCLUIDO, {**base, **extras}, concluido_em=T0)


def test_libera_no_limite_exato_do_prazo_e_nao_antes():
    x = concluido()
    assert liberacoes_por_prazo(T0 + 7 * D - timedelta(seconds=1), [x], CFG) == []
    [a] = liberacoes_por_prazo(T0 + 7 * D, [x], CFG)
    assert a.tipo is TipoAcaoRotina.LIBERAR_SALDO
    assert (a.valor_centavos, a.profissional_id) == (9_250, "p1")


def test_prazo_de_liberacao_vem_da_configuracao_p1():
    curto = ConfigRotinas(prazo_liberacao=48 * H)
    assert len(liberacoes_por_prazo(T0 + 48 * H, [concluido()], curto)) == 1
    assert liberacoes_por_prazo(T0 + 47 * H, [concluido()], curto) == []


def test_disputa_aberta_bloqueia_liberacao():
    x = concluido(disputa_aberta=True)
    assert liberacoes_por_prazo(T0 + 99 * D, [x], CFG) == []


def test_so_libera_pedido_concluido_com_saldo():
    assert liberacoes_por_prazo(T0 + 99 * D, [concluido(saldo_a_liberar_centavos=0)], CFG) == []
    outros = item(Estado.EM_CONFIRMACAO, {"saldo_a_liberar_centavos": 100}, check_out_em=T0)
    assert liberacoes_por_prazo(T0 + 99 * D, [outros], CFG) == []
    em_disputa = item(Estado.EM_DISPUTA, {"saldo_a_liberar_centavos": 100})
    assert liberacoes_por_prazo(T0 + 99 * D, [em_disputa], CFG) == []


def test_sem_prazo_de_liberacao_nao_libera():
    assert liberacoes_por_prazo(T0 + 99 * D, [concluido()], ConfigRotinas()) == []


def test_janela_de_reclamacao_so_bloqueia_se_configurado_assim():
    cfg = ConfigRotinas(prazo_liberacao=48 * H, janela_reclamacao=7 * D)
    assert len(liberacoes_por_prazo(T0 + 48 * H, [concluido()], cfg)) == 1
    espera = ConfigRotinas(
        prazo_liberacao=48 * H, janela_reclamacao=7 * D, liberacao_espera_janela=True
    )
    assert liberacoes_por_prazo(T0 + 48 * H, [concluido()], espera) == []
    assert len(liberacoes_por_prazo(T0 + 7 * D, [concluido()], espera)) == 1


# --- Lembretes ------------------------------------------------------------------------


def test_lembrete_de_confirmacao_pendente():
    x = item(Estado.EM_CONFIRMACAO, check_out_em=T0)
    assert lembretes(T0 + 24 * H - timedelta(seconds=1), [x], CFG) == []
    [a] = lembretes(T0 + 24 * H, [x], CFG)
    assert (a.lembrete, a.destinatario) == (Lembrete.CONFIRMACAO_PENDENTE, Papel.CLIENTE)


def test_sem_lembrete_de_confirmacao_depois_do_prazo():
    x = item(Estado.EM_CONFIRMACAO, check_out_em=T0)
    assert lembretes(T0 + 48 * H, [x], CFG) == []  # nessa hora a rotina conclui


def test_lembrete_de_resposta_da_disputa_48h():
    disputa = DisputaMonitorada(aberta_em=T0)
    x = item(Estado.EM_DISPUTA, {"disputa": disputa, "disputa_aberta": True})
    assert lembretes(T0 + 36 * H - timedelta(seconds=1), [x], CFG) == []
    [a] = lembretes(T0 + 36 * H, [x], CFG)
    assert (a.lembrete, a.destinatario) == (Lembrete.RESPOSTA_DISPUTA, Papel.PROFISSIONAL)
    assert [
        b for b in lembretes(T0 + 48 * H, [x], CFG) if b.lembrete is Lembrete.RESPOSTA_DISPUTA
    ] == []


def test_disputa_respondida_nao_lembra_o_profissional():
    disputa = DisputaMonitorada(aberta_em=T0, respondida=True)
    x = item(Estado.EM_DISPUTA, {"disputa": disputa, "disputa_aberta": True})
    assert lembretes(T0 + 40 * H, [x], CFG) == []


def test_lembrete_de_decisao_em_dias_uteis_com_feriado():
    disputa = DisputaMonitorada(aberta_em=T0)  # segunda 09:00; 5 dias úteis = segunda 09/11
    x = item(Estado.EM_DISPUTA, {"disputa": disputa, "disputa_aberta": True})
    limite = datetime(2026, 11, 9, 9, tzinfo=UTC)
    assert lembretes(limite - 24 * H - timedelta(seconds=1), [x], CFG) == []
    # as duas primeiras ações são de resposta ao profissional; filtra o mediador
    aviso = [a for a in lembretes(limite - 24 * H, [x], CFG) if a.destinatario is Papel.MEDIADOR]
    assert len(aviso) == 1
    feriados = frozenset({date(2026, 11, 3)})  # empurra o limite para terça 10/11
    adiado = [a for a in lembretes(limite - 24 * H, [x], CFG, feriados)
              if a.destinatario is Papel.MEDIADOR]  # fmt: skip
    assert adiado == []


def test_lembrete_de_aditivo_aguardando():
    x = item(Estado.EM_ANDAMENTO, {"aditivo_pendente_desde": T0})
    assert lembretes(T0 + 12 * H - timedelta(seconds=1), [x], CFG) == []
    [a] = lembretes(T0 + 12 * H, [x], CFG)
    assert (a.lembrete, a.destinatario) == (Lembrete.ADITIVO_AGUARDANDO, Papel.CLIENTE)


# --- Idempotência e ordem -------------------------------------------------------------


def varios():
    return [
        item(Estado.ABERTO, id="a"),
        concluido_com_id("b"),
        item(Estado.EM_CONFIRMACAO, id="c", check_out_em=T0),
    ]


def concluido_com_id(id_):
    return item(Estado.CONCLUIDO, {"saldo_a_liberar_centavos": 500}, id=id_, concluido_em=T0)


def test_rodar_duas_vezes_no_mesmo_instante_da_a_mesma_lista():
    agora = T0 + 8 * D
    primeira = rotinas_do_instante(agora, varios(), CFG)
    segunda = rotinas_do_instante(agora, varios(), CFG)
    assert primeira == segunda
    chaves = [a.chave for a in primeira]
    assert len(chaves) == len(set(chaves)) and len(chaves) == 3


def test_acoes_ja_executadas_nao_voltam():
    agora = T0 + 8 * D
    feitas = frozenset(a.chave for a in rotinas_do_instante(agora, varios(), CFG))
    assert rotinas_do_instante(agora, varios(), CFG, ja_executadas=feitas) == []


def test_chave_estavel_entre_instantes():
    antes = rotinas_do_instante(T0 + 8 * D, [concluido()], CFG)
    depois = rotinas_do_instante(T0 + 9 * D, [concluido()], CFG)
    assert [a.chave for a in antes] == [a.chave for a in depois]


def test_depois_de_executar_o_estado_muda_e_a_acao_some():
    agora = T0 + 8 * D
    assert len(rotinas_do_instante(agora, [concluido()], CFG)) == 1
    liberado = concluido(saldo_a_liberar_centavos=0)
    assert rotinas_do_instante(agora, [liberado], CFG) == []


def test_ordem_e_deterministica():
    agora = T0 + 8 * D
    itens = varios()
    assert rotinas_do_instante(agora, itens, CFG) == rotinas_do_instante(agora, itens[::-1], CFG)


def test_instante_sem_fuso_e_recusado():
    with pytest.raises(ValueError, match="fuso"):
        rotinas_do_instante(datetime(2026, 11, 2), [], CFG)  # noqa: DTZ001
