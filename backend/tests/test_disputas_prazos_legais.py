from datetime import UTC, datetime, timedelta

import pytest

from trato.disputas import ConfigDisputa, prazos_legais_informativos

T0 = datetime(2026, 3, 2, 12, 0, tzinfo=UTC)


def cfg(**legais: int) -> ConfigDisputa:
    return ConfigDisputa(
        prazo_resposta_horas=48,
        prazo_decisao_dias_uteis=5,
        prazo_congelar_repasse_horas=72,
        prazos_legais=legais,
    )


def test_sem_configuracao_nao_informa_prazo_algum():
    assert prazos_legais_informativos(T0, cfg()) == ()


def test_prazos_legais_viram_datas_informativas_vindas_da_configuracao():
    achados = prazos_legais_informativos(T0, cfg(vicio_aparente=10, arrependimento=3))

    assert [(p.nome, p.ate) for p in achados] == [
        ("arrependimento", T0 + timedelta(days=3)),
        ("vicio_aparente", T0 + timedelta(days=10)),
    ]
    assert all(p.informativo for p in achados)


def test_janela_de_congelamento_e_prazo_legal_sao_independentes():
    a = cfg(vicio_aparente=90)
    b = ConfigDisputa(48, 5, 24, prazos_legais={"vicio_aparente": 90})

    assert prazos_legais_informativos(T0, a) == prazos_legais_informativos(T0, b)


@pytest.mark.parametrize("dias", [0, -1, True, 1.5])
def test_prazo_legal_invalido_e_recusado(dias):
    with pytest.raises(ValueError):
        cfg(x=dias)
