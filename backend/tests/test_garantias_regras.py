from datetime import UTC, datetime, timedelta

import pytest

from trato.garantias import (
    ConfigGarantia,
    ErroGarantia,
    ErroRetrabalho,
    abrir_garantia,
    abrir_retrabalho,
    deve_virar_nao_atendido,
    garantia_ativa_agora,
    marcar_nao_atendido_se_vencido,
    transicionar,
)
from trato.garantias import EstadoRetrabalho as E

T0 = datetime(2026, 3, 1, 12, 0, tzinfo=UTC)
SEG = timedelta(seconds=1)
CFG = ConfigGarantia(garantia_dias_por_categoria={"pintura": 90})
CFG_FINANCIADA = ConfigGarantia(garantia_financiada_habilitada=True)


def test_padrao_30_dias_e_categoria_sobrescreve():
    assert abrir_garantia(T0, "eletrica", CFG).dias == 30
    assert abrir_garantia(T0, None, CFG).dias == 30
    g = abrir_garantia(T0, "pintura", CFG)
    assert g.dias == 90 and g.fim_em == T0 + timedelta(days=90)


def test_config_nao_fixa_no_codigo():
    cfg = ConfigGarantia(garantia_dias_padrao=10, prazo_atendimento_dias=2)
    g = abrir_garantia(T0, "x", cfg)
    assert g.fim_em == T0 + timedelta(days=10)
    assert abrir_retrabalho(g, "defeito", T0, cfg).atender_ate == T0 + timedelta(days=2)


def test_config_invalida():
    with pytest.raises(ValueError):
        ConfigGarantia(garantia_dias_padrao=0)
    with pytest.raises(ValueError):
        ConfigGarantia(garantia_dias_por_categoria={"a": -1})


def test_data_sem_fuso_recusada():
    with pytest.raises(ErroGarantia):
        abrir_garantia(datetime(2026, 3, 1), None, CFG)  # noqa: DTZ001


def test_limites_da_garantia():
    g = abrir_garantia(T0, None, CFG)
    assert not garantia_ativa_agora(g, T0 - SEG)
    assert garantia_ativa_agora(g, T0)
    assert garantia_ativa_agora(g, g.fim_em)
    assert not garantia_ativa_agora(g, g.fim_em + SEG)


def test_abre_retrabalho_com_prazo_de_7_dias():
    g = abrir_garantia(T0, None, CFG)
    r = abrir_retrabalho(g, " vazamento ", T0 + timedelta(days=3), CFG)
    assert r.estado is E.ABERTO and r.descricao == "vazamento"
    assert r.atender_ate == T0 + timedelta(days=10)


def test_retrabalho_no_ultimo_instante_e_um_segundo_depois():
    g = abrir_garantia(T0, None, CFG)
    assert abrir_retrabalho(g, "x", g.fim_em, CFG)
    with pytest.raises(ErroRetrabalho, match="garantia"):
        abrir_retrabalho(g, "x", g.fim_em + SEG, CFG)


def test_descricao_vazia():
    g = abrir_garantia(T0, None, CFG)
    with pytest.raises(ErroRetrabalho):
        abrir_retrabalho(g, "  ", T0, CFG)


def test_um_em_curso_por_vez_e_novo_apos_resolvido():
    g = abrir_garantia(T0, None, CFG)
    r = abrir_retrabalho(g, "a", T0, CFG)
    with pytest.raises(ErroRetrabalho, match="em curso"):
        abrir_retrabalho(g, "b", T0, CFG, existentes=[r])
    r = transicionar(r, E.ACEITO, T0)
    r = transicionar(r, E.EM_EXECUCAO, T0)
    r = transicionar(r, E.RESOLVIDO, T0 + timedelta(days=1))
    assert r.atendido_em == T0 + timedelta(days=1)
    assert abrir_retrabalho(g, "b", T0 + timedelta(days=2), CFG, existentes=[r])


def test_transicoes_validas_e_invalidas():
    g = abrir_garantia(T0, None, CFG)
    r = abrir_retrabalho(g, "a", T0, CFG)
    for invalido in (E.EM_EXECUCAO, E.RESOLVIDO, E.REATRIBUIDO, E.ABERTO):
        with pytest.raises(ErroRetrabalho, match="inválida"):
            transicionar(r, invalido, T0)
    aceito = transicionar(r, E.ACEITO, T0)
    with pytest.raises(ErroRetrabalho):
        transicionar(aceito, E.RESOLVIDO, T0)
    resolvido = transicionar(transicionar(aceito, E.EM_EXECUCAO, T0), E.RESOLVIDO, T0)
    for novo in E:
        with pytest.raises(ErroRetrabalho):
            transicionar(resolvido, novo, T0)


def test_prazo_vence_so_depois_de_atender_ate():
    g = abrir_garantia(T0, None, CFG)
    r = abrir_retrabalho(g, "a", T0, CFG)
    assert not deve_virar_nao_atendido(r, r.atender_ate)  # último instante
    assert deve_virar_nao_atendido(r, r.atender_ate + SEG)
    assert marcar_nao_atendido_se_vencido(r, r.atender_ate) is r
    assert marcar_nao_atendido_se_vencido(r, r.atender_ate + SEG).estado is E.NAO_ATENDIDO


def test_aceito_tambem_vence_mas_em_execucao_nao():
    g = abrir_garantia(T0, None, CFG)
    r = transicionar(abrir_retrabalho(g, "a", T0, CFG), E.ACEITO, T0)
    tarde = r.atender_ate + SEG
    assert deve_virar_nao_atendido(r, tarde)
    assert not deve_virar_nao_atendido(transicionar(r, E.EM_EXECUCAO, T0), tarde)


def test_nao_atendido_manual_antes_do_prazo_recusado():
    g = abrir_garantia(T0, None, CFG)
    r = abrir_retrabalho(g, "a", T0, CFG)
    with pytest.raises(ErroRetrabalho, match="venceu"):
        transicionar(r, E.NAO_ATENDIDO, r.atender_ate)


def test_reatribuir_exige_outro_profissional_e_bloqueia_novo_ate_ser_reatribuido():
    g = abrir_garantia(T0, None, CFG)
    r = abrir_retrabalho(g, "a", T0, CFG)
    na = marcar_nao_atendido_se_vencido(r, r.atender_ate + SEG)
    with pytest.raises(ErroRetrabalho, match="profissional"):
        transicionar(na, E.REATRIBUIDO, T0, config=CFG_FINANCIADA)
    with pytest.raises(ErroRetrabalho, match="em curso"):
        abrir_retrabalho(g, "b", T0 + timedelta(days=8), CFG, existentes=[na])
    reatrib = transicionar(na, E.REATRIBUIDO, T0, outro_profissional_id="p2", config=CFG_FINANCIADA)
    assert reatrib.estado is E.REATRIBUIDO and reatrib.outro_profissional_id == "p2"
    with pytest.raises(ErroRetrabalho):
        transicionar(reatrib, E.RESOLVIDO, T0)


def test_garantia_financiada_vem_desligada_por_padrao():
    assert ConfigGarantia().garantia_financiada_habilitada is False
    with pytest.raises(ValueError):
        ConfigGarantia(garantia_financiada_habilitada="sim")  # type: ignore[arg-type]


def test_reatribuir_com_custo_para_o_trato_exige_a_configuracao_ligada():
    g = abrir_garantia(T0, None, CFG)
    r = abrir_retrabalho(g, "a", T0, CFG)
    na = marcar_nao_atendido_se_vencido(r, r.atender_ate + SEG)

    for config in (None, CFG):
        with pytest.raises(ErroRetrabalho, match="suporte e análise de problemas"):
            transicionar(na, E.REATRIBUIDO, T0, outro_profissional_id="p2", config=config)
