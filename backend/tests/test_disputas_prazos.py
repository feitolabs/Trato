from datetime import UTC, date, datetime, timedelta

import pytest

from trato.disputas import ConfigDisputa, adicionar_dias_uteis, calcular_prazos, dentro_da_janela

CFG = ConfigDisputa(
    prazo_resposta_horas=48, prazo_decisao_dias_uteis=5, prazo_congelar_repasse_horas=72
)


def dt(ano, mes, dia, h=10):
    return datetime(ano, mes, dia, h, 0, tzinfo=UTC)


def test_resposta_em_horas_corridas():
    p = calcular_prazos(dt(2026, 10, 28), CFG)  # quarta
    assert p.resposta_ate == dt(2026, 10, 30)


def test_decisao_5_dias_uteis_pula_fim_de_semana():
    # quarta 28/10 + 5 úteis = quarta 04/11
    assert calcular_prazos(dt(2026, 10, 28), CFG).decisao_ate == dt(2026, 11, 4)


def test_decisao_aberta_no_sabado_conta_a_partir_de_segunda():
    # sábado 31/10: úteis = seg 2, ter 3, qua 4, qui 5, sex 6
    assert calcular_prazos(dt(2026, 10, 31), CFG).decisao_ate == dt(2026, 11, 6)


def test_feriado_nao_conta():
    cfg = ConfigDisputa(48, 5, 72, feriados=[date(2026, 11, 2)])  # segunda
    assert calcular_prazos(dt(2026, 10, 28), cfg).decisao_ate == dt(2026, 11, 5)


def test_zero_dias_uteis_devolve_o_inicio():
    assert adicionar_dias_uteis(dt(2026, 10, 28), 0) == dt(2026, 10, 28)


def test_dias_negativos_e_datetime_ingenuo_rejeitados():
    with pytest.raises(ValueError):
        adicionar_dias_uteis(dt(2026, 10, 28), -1)
    with pytest.raises(ValueError):
        calcular_prazos(datetime(2026, 10, 28), CFG)


def test_prazos_vem_da_config_nao_do_codigo():
    cfg = ConfigDisputa(24, 2, 12)
    p = calcular_prazos(dt(2026, 10, 28), cfg)
    assert p.resposta_ate == dt(2026, 10, 29)
    assert p.decisao_ate == dt(2026, 10, 30)


def test_config_rejeita_valor_invalido():
    with pytest.raises(ValueError):
        ConfigDisputa(-1, 5, 72)
    with pytest.raises(ValueError):
        ConfigDisputa(48.5, 5, 72)  # type: ignore[arg-type]


def test_janela_de_abertura_limite_inclusivo():
    concl = dt(2026, 10, 28)
    assert dentro_da_janela(concl, concl + timedelta(hours=72), CFG)
    assert not dentro_da_janela(concl, concl + timedelta(hours=72, seconds=1), CFG)
