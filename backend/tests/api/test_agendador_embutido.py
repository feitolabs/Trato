"""O agendador pode rodar dentro do processo da API (opt-in), sem derrubar a API se falhar."""

from __future__ import annotations

import threading

from trato.api.fabrica import iniciar_agendador_embutido
from trato.config import Config


class _AgendadorFalso:
    def __init__(self) -> None:
        self.rodou = threading.Event()

    def rodar_sempre(self, parar: threading.Event, intervalo: float) -> None:
        self.rodou.set()
        parar.wait(5)


class _BancoFalso:
    def __init__(self) -> None:
        self.fechado = threading.Event()

    def fechar(self) -> None:
        self.fechado.set()


def test_liga_o_laco_num_fio_e_fecha_o_banco_ao_parar():
    agendador, banco, parar = _AgendadorFalso(), _BancoFalso(), threading.Event()

    fio = iniciar_agendador_embutido(Config(), parar, montar=lambda: (agendador, banco, 0.01))

    assert fio is not None
    assert agendador.rodou.wait(2)
    parar.set()
    fio.join(timeout=2)
    assert banco.fechado.is_set()


def test_se_nao_conseguir_montar_a_api_segue_de_pe():
    def quebrado():
        raise SystemExit("Defina DATABASE_URL no .env.")

    assert iniciar_agendador_embutido(Config(), threading.Event(), montar=quebrado) is None
