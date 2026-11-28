"""BE-1B (Termos 20.6): só a trava de saque por fraude adia a liberação, retendo no máximo o
limite, e volta sozinha ao reverter ou vencer. Memória."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import PROFISSIONAL, cab
from test_agendador import montar
from test_liberacao_automatica import concluido, repasses, saldo

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.medidas import aplicar, reverter
from trato.persistencia.medidas import Medida
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

VALOR = 92_500
D = timedelta(days=1)


def travar(amb, limite=None, dias=30, motivo="Fraude em apuração.") -> Medida:
    agora = amb.contexto.agora()
    medida, _ = aplicar(
        amb.contexto,
        Medida(
            usuario_id=PROFISSIONAL.id,
            tipo="trava_saque",
            motivo=motivo,
            clausulas=("20.6",),
            inicio_em=agora,
            fim_em=agora + timedelta(days=dias),
            efeito="Segue a cláusula 20.6.",
            como_contestar="Pelo atendimento.",
            aplicada_por="eq-mediador",
            motivo_fraude=limite is not None,
            limite_retencao_centavos=limite,
        ),
    )
    return medida


def liberar(amb) -> None:
    valor = saldo(amb)[0]
    acao = AcaoRotina(
        TipoAcaoRotina.LIBERAR_SALDO,
        "ped-1",
        f"liberacao:ped-1:{valor}",
        valor_centavos=valor,
        profissional_id=PROFISSIONAL.id,
    )
    ExecutorContexto(amb.contexto).executar(acao, amb.contexto.agora())


def test_trava_sem_fraude_nao_segura(amb):
    concluido(amb)
    travar(amb)
    liberar(amb)
    assert saldo(amb) == (0, VALOR)


@pytest.mark.parametrize("limite", [VALOR, VALOR * 10])
def test_limite_acima_do_saldo_adia_tudo_ate_reverter(amb, limite):
    concluido(amb)
    medida = travar(amb, limite)
    with pytest.raises(Adiada, match="retencao_por_fraude"):
        liberar(amb)
    agendador, _, _ = montar(amb)
    agendador.rodar_uma_vez()
    assert saldo(amb) == (VALOR, 0) and repasses(amb) == 0
    assert reverter(amb.contexto, medida, "eq-mediador")
    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    assert saldo(amb) == (0, VALOR) and repasses(amb) == 1


def test_libera_so_o_que_passa_do_limite_uma_vez_e_o_resto_ao_vencer(amb):
    concluido(amb)
    travar(amb, 20_000, dias=5)
    agendador, _, _ = montar(amb)
    for _ in range(3):
        agendador.rodar_uma_vez()
    assert saldo(amb) == (20_000, VALOR - 20_000) and repasses(amb) == 1
    amb.relogio.avancar(days=5, seconds=-1)
    agendador.rodar_uma_vez()
    assert saldo(amb) == (20_000, VALOR - 20_000)
    amb.relogio.avancar(seconds=1)  # no instante final já não vale
    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    assert saldo(amb) == (0, VALOR) and repasses(amb) == 2


def test_duas_travas_nao_somam_vale_o_maior_limite(amb):
    concluido(amb)
    travar(amb, 60_000, motivo="Primeira apuração.")
    amb.relogio.avancar(minutes=1)
    travar(amb, 10_000, motivo="Prejuízo revisto.")
    liberar(amb)
    assert saldo(amb) == (60_000, VALOR - 60_000)


def test_repetir_compara_fraude_e_limite(amb):
    primeira = travar(amb, 10_000)
    assert travar(amb, 10_000).id == primeira.id
    assert travar(amb, 12_000).id != primeira.id
    assert travar(amb).id != primeira.id


def _aplicar(amb, **extra):
    corpo = {
        "usuario_id": PROFISSIONAL.id,
        "tipo": "trava_saque",
        "motivo": "Fraude em apuração no pedido.",
        "clausulas": ["20.6"],
    } | extra
    return amb.cliente.post("/v1/admin/medidas", json=corpo, headers=cab("t-mediador"))


@pytest.mark.parametrize(
    "extra",
    [
        {"motivo_fraude": True},
        {"limite_retencao_centavos": 100},
        {"motivo_fraude": True, "limite_retencao_centavos": 100, "tipo": "restricao"},
        {"motivo_fraude": True, "limite_retencao_centavos": 100, "dias": 31},
        {"motivo_fraude": True, "limite_retencao_centavos": 0},
        {"motivo_fraude": True, "limite_retencao_centavos": 10.5},
    ],
)
def test_rota_recusa_dados_invalidos(amb, extra):
    from test_medidas import preparar

    preparar(amb)
    r = _aplicar(amb, **extra)
    assert r.status_code == 422, r.text
    assert amb.contexto.medidas.retencao_por_fraude(PROFISSIONAL.id, amb.contexto.agora()) is None


def test_rota_grava_com_prazo_padrao_de_30_dias(amb):
    from datetime import datetime

    from test_medidas import preparar

    preparar(amb)
    r = _aplicar(amb, motivo_fraude=True, limite_retencao_centavos=5_000)
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["motivo_fraude"] is True and corpo["limite_retencao_centavos"] == 5_000
    inicio, fim = (datetime.fromisoformat(corpo[c]) for c in ("inicio_em", "fim_em"))
    assert fim - inicio == 30 * D
