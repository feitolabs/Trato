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


def test_com_banco_compartilhado_nao_abre_outro_pool_e_nao_fecha_o_da_api():
    """Produção: API e agendador usam o MESMO pool (o pooler do Supabase aceita 15 conexões)."""
    agendador, compartilhado, parar = _AgendadorFalso(), _BancoFalso(), threading.Event()

    fio = iniciar_agendador_embutido(
        Config(), parar, montar=lambda: (agendador, compartilhado, 0.01), banco=compartilhado
    )

    assert fio is not None
    assert agendador.rodou.wait(2)
    parar.set()
    fio.join(timeout=2)
    assert not compartilhado.fechado.is_set()  # quem fecha o pool compartilhado é a API


def test_pool_do_processo_vem_da_config_e_e_pequeno_por_padrao():
    cfg = Config(_env_file=None)
    assert (cfg.trato_banco_pool_min, cfg.trato_banco_pool_max) == (1, 3)
    # dois processos de API + 1 conexão da trava cada + uma 3ª máquina no deploy rolling < 15
    assert 3 * (cfg.trato_banco_pool_max + 1) <= 15
    assert Config(_env_file=None, trato_banco_pool_max=2).trato_banco_pool_max == 2
