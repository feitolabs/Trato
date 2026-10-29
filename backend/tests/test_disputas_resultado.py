import pytest

from trato.disputas import Decisao, Divisao, Resultado, ResultadoInvalido, dividir_valor


def test_liberar_tudo():
    assert dividir_valor(10_000, Decisao(Resultado.LIBERAR_TUDO)) == Divisao(10_000, 0, 0)


def test_reembolso_total():
    assert dividir_valor(10_000, Decisao(Resultado.REEMBOLSO_TOTAL)) == Divisao(0, 10_000, 0)


def test_nova_visita_mantem_tudo_retido():
    assert dividir_valor(10_000, Decisao(Resultado.NOVA_VISITA)) == Divisao(0, 0, 10_000)


def test_parcial_por_bps():
    d = Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=2_500)
    assert dividir_valor(10_000, d) == Divisao(7_500, 2_500, 0)


def test_parcial_por_valor():
    d = Decisao(Resultado.REEMBOLSO_PARCIAL, valor_cliente_centavos=3_333)
    assert dividir_valor(10_000, d) == Divisao(6_667, 3_333, 0)


def test_arredondamento_piso_resto_com_profissional():
    # 1001 * 3333 // 10000 = 333 (piso); o resto fica com o profissional
    d = Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=3_333)
    r = dividir_valor(10_01, d)
    assert r.para_cliente == 333
    assert r.para_profissional == 1001 - 333


@pytest.mark.parametrize("valor", [1, 2, 99, 1001, 12_345, 999_999_999])
@pytest.mark.parametrize("bps", [1, 5_000, 3_333, 9_999])
def test_soma_sempre_igual_ao_congelado(valor, bps):
    d = Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=bps)
    try:
        r = dividir_valor(valor, d)
    except ResultadoInvalido:
        assert valor * bps // 10_000 == 0  # só falha quando o reembolso seria 0 centavo
        return
    assert r.para_profissional + r.para_cliente + r.retido == valor
    assert r.para_cliente > 0 and r.para_profissional > 0


@pytest.mark.parametrize(
    "decisao",
    [
        Decisao(Resultado.REEMBOLSO_PARCIAL),
        Decisao(
            Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=5_000, valor_cliente_centavos=1
        ),
        Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=0),
        Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=10_000),
        Decisao(Resultado.REEMBOLSO_PARCIAL, valor_cliente_centavos=0),
        Decisao(Resultado.REEMBOLSO_PARCIAL, valor_cliente_centavos=10_000),
        Decisao(Resultado.REEMBOLSO_PARCIAL, valor_cliente_centavos=10_001),
        Decisao(Resultado.REEMBOLSO_PARCIAL, percentual_cliente_bps=1_000.5),  # type: ignore[arg-type]
        Decisao(Resultado.LIBERAR_TUDO, percentual_cliente_bps=5_000),
        Decisao(Resultado.NOVA_VISITA, valor_cliente_centavos=100),
    ],
)
def test_decisoes_invalidas(decisao):
    with pytest.raises(ResultadoInvalido):
        dividir_valor(10_000, decisao)


@pytest.mark.parametrize("valor", [0, -1, 10.0, True])
def test_valor_congelado_invalido(valor):
    with pytest.raises(ResultadoInvalido):
        dividir_valor(valor, Decisao(Resultado.LIBERAR_TUDO))  # type: ignore[arg-type]
