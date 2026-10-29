from datetime import UTC, datetime, timedelta

import pytest

from trato.disputas import (
    AlcadaInvalida,
    Ator,
    ConfigDisputa,
    Decisao,
    Estado,
    Motivo,
    PrazoExpirado,
    Resultado,
    ResultadoInvalido,
    TransicaoInvalida,
    abrir,
)

CFG = ConfigDisputa(48, 5, 72)
T0 = datetime(2026, 10, 28, 10, 0, tzinfo=UTC)
TETO = 100_000


def nova(valor=50_000, motivo=Motivo.MAL_FEITO):
    return abrir(
        Ator.CLIENTE, valor, motivo, concluido_em=T0, agora=T0 + timedelta(hours=1), config=CFG
    )


def em_analise(valor=50_000):
    d = nova(valor)
    return d.responder(Ator.PROFISSIONAL, d.aberta_em + timedelta(hours=2))


# --- abrir ---------------------------------------------------------------


@pytest.mark.parametrize("motivo", list(Motivo))
def test_abrir_com_cada_motivo(motivo):
    d = nova(motivo=motivo)
    assert d.estado is Estado.ABERTA and d.motivo is motivo
    assert d.valor_congelado == 50_000


@pytest.mark.parametrize("ator", [Ator.PROFISSIONAL, Ator.ANALISTA, Ator.SISTEMA])
def test_so_cliente_abre(ator):
    with pytest.raises(TransicaoInvalida):
        abrir(ator, 1000, Motivo.DANO, T0, T0, CFG)


def test_abrir_fora_da_janela_de_72h_nao_recusa_a_reclamacao():
    """D13: a janela só decide o congelamento do repasse, não renuncia ao direito de reclamar."""
    tarde = abrir(Ator.CLIENTE, 1000, Motivo.DANO, T0, T0 + timedelta(hours=73), CFG)
    no_prazo = abrir(Ator.CLIENTE, 1000, Motivo.DANO, T0, T0 + timedelta(hours=72), CFG)

    assert tarde.estado is Estado.ABERTA
    assert tarde.abertura_dentro_da_janela_de_congelamento is False
    assert no_prazo.abertura_dentro_da_janela_de_congelamento is True


@pytest.mark.parametrize("valor", [0, -5, 10.5, True])
def test_abrir_valor_invalido(valor):
    with pytest.raises(ResultadoInvalido):
        abrir(Ator.CLIENTE, valor, Motivo.DANO, T0, T0, CFG)


# --- responder / sem resposta ---------------------------------------------


def test_profissional_responde_no_prazo():
    d = nova()
    r = d.responder(Ator.PROFISSIONAL, d.prazos.resposta_ate)  # limite inclusivo
    assert r.estado is Estado.EM_ANALISE and not r.sem_resposta
    assert d.estado is Estado.ABERTA  # imutável


def test_responder_depois_de_48h_falha():
    d = nova()
    with pytest.raises(PrazoExpirado):
        d.responder(Ator.PROFISSIONAL, d.prazos.resposta_ate + timedelta(seconds=1))


@pytest.mark.parametrize("ator", [Ator.CLIENTE, Ator.ANALISTA, Ator.SISTEMA])
def test_so_profissional_responde(ator):
    with pytest.raises(TransicaoInvalida):
        nova().responder(ator, T0 + timedelta(hours=2))


def test_responder_duas_vezes_falha():
    d = em_analise()
    with pytest.raises(TransicaoInvalida):
        d.responder(Ator.PROFISSIONAL, d.respondida_em)


def test_sistema_encerra_sem_resposta_apos_prazo():
    d = nova()
    r = d.encerrar_sem_resposta(Ator.SISTEMA, d.prazos.resposta_ate + timedelta(seconds=1))
    assert r.estado is Estado.EM_ANALISE and r.sem_resposta


def test_sistema_nao_encerra_antes_do_prazo():
    d = nova()
    with pytest.raises(TransicaoInvalida):
        d.encerrar_sem_resposta(Ator.SISTEMA, d.prazos.resposta_ate)


def test_so_sistema_encerra_sem_resposta():
    d = nova()
    with pytest.raises(TransicaoInvalida):
        d.encerrar_sem_resposta(Ator.ANALISTA, d.prazos.resposta_ate + timedelta(hours=1))


# --- decidir: os 4 resultados --------------------------------------------


def decidir(d, decisao, analista="ana"):
    return d.decidir(Ator.ANALISTA, analista, decisao, d.aberta_em + timedelta(days=2), TETO)


def test_resultado_liberar_tudo():
    r = decidir(em_analise(), Decisao(Resultado.LIBERAR_TUDO))
    assert r.estado is Estado.DECIDIDA
    assert (r.divisao.para_profissional, r.divisao.para_cliente) == (50_000, 0)


def test_resultado_reembolso_total():
    r = decidir(em_analise(), Decisao(Resultado.REEMBOLSO_TOTAL))
    assert r.estado is Estado.DECIDIDA
    assert (r.divisao.para_profissional, r.divisao.para_cliente) == (0, 50_000)


def test_resultado_reembolso_parcial():
    r = decidir(em_analise(), Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=4_000))
    assert r.estado is Estado.DECIDIDA
    assert (r.divisao.para_profissional, r.divisao.para_cliente) == (30_000, 20_000)


def test_resultado_nova_visita():
    r = decidir(em_analise(), Decisao(Resultado.NOVA_VISITA))
    assert r.estado is Estado.DECIDIDA
    assert (r.divisao.para_profissional, r.divisao.para_cliente, r.divisao.retido) == (0, 0, 50_000)


def test_decidir_sem_resposta_do_profissional_e_possivel():
    d = nova()
    d = d.encerrar_sem_resposta(Ator.SISTEMA, d.prazos.resposta_ate + timedelta(hours=1))
    assert decidir(d, Decisao(Resultado.REEMBOLSO_TOTAL)).estado is Estado.DECIDIDA


@pytest.mark.parametrize("ator", [Ator.CLIENTE, Ator.PROFISSIONAL, Ator.SISTEMA])
def test_so_analista_decide(ator):
    with pytest.raises(TransicaoInvalida):
        em_analise().decidir(ator, "x", Decisao(Resultado.LIBERAR_TUDO), T0, TETO)


def test_nao_decide_em_disputa_aberta():
    with pytest.raises(TransicaoInvalida):
        decidir(nova(), Decisao(Resultado.LIBERAR_TUDO))


def test_nao_decide_duas_vezes():
    r = decidir(em_analise(), Decisao(Resultado.LIBERAR_TUDO))
    with pytest.raises(TransicaoInvalida):
        decidir(r, Decisao(Resultado.REEMBOLSO_TOTAL))


def test_decisao_invalida_nao_muda_estado():
    d = em_analise()
    with pytest.raises(ResultadoInvalido):
        decidir(d, Decisao(Resultado.REEMBOLSO_PARCIAL))
    with pytest.raises(ResultadoInvalido):
        decidir(d, Decisao(Resultado.LIBERAR_TUDO), analista="")


def test_atrasada_depois_de_5_dias_uteis():
    d = em_analise()
    assert not d.atrasada(d.prazos.decisao_ate)
    assert d.atrasada(d.prazos.decisao_ate + timedelta(seconds=1))
    assert not decidir(d, Decisao(Resultado.LIBERAR_TUDO)).atrasada(
        d.prazos.decisao_ate + timedelta(days=9)
    )


# --- alçada ---------------------------------------------------------------


def acima():
    d = em_analise(valor=TETO + 1)
    return decidir(d, Decisao(Resultado.REEMBOLSO_TOTAL), analista="ana")


def test_no_teto_nao_precisa_de_segunda_pessoa():
    d = decidir(em_analise(valor=TETO), Decisao(Resultado.LIBERAR_TUDO))
    assert d.estado is Estado.DECIDIDA and d.aprovado_por is None


def test_acima_do_teto_espera_aprovacao_e_nao_paga():
    d = acima()
    assert d.estado is Estado.AGUARDANDO_APROVACAO
    assert d.divisao is None and d.decidido_por == "ana"


def test_aprovacao_por_outra_pessoa_conclui():
    d = acima().aprovar(Ator.ANALISTA, "bia", T0 + timedelta(days=3))
    assert d.estado is Estado.DECIDIDA
    assert d.aprovado_por == "bia" != d.decidido_por
    assert d.divisao.para_cliente == TETO + 1


@pytest.mark.parametrize("aprovador", ["ana", ""])
def test_aprovador_igual_ao_decisor_ou_vazio_falha(aprovador):
    with pytest.raises(AlcadaInvalida):
        acima().aprovar(Ator.ANALISTA, aprovador, T0)


@pytest.mark.parametrize("ator", [Ator.CLIENTE, Ator.PROFISSIONAL, Ator.SISTEMA])
def test_so_analista_aprova(ator):
    with pytest.raises(TransicaoInvalida):
        acima().aprovar(ator, "bia", T0)


def test_aprovar_fora_do_estado_falha():
    with pytest.raises(TransicaoInvalida):
        em_analise().aprovar(Ator.ANALISTA, "bia", T0)
    final = decidir(em_analise(), Decisao(Resultado.LIBERAR_TUDO))
    with pytest.raises(TransicaoInvalida):
        final.aprovar(Ator.ANALISTA, "bia", T0)
