"""TERMOS-M1: Tratinhos vencem por crédito (13.4), validade padrão de 90 dias (I.5) e devolução
proporcional com a validade original (13.8, I.9)."""

from __future__ import annotations

import threading
from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401 - `fluxo` é fixture
from test_moedas_pix_reserva import _cobrar, _ligar, _pagar

from trato.api.moedas import (
    ConfigMoedas,
    LancamentoMoeda,
    MoedasEmMemoria,
    PendenteMoeda,
    chave_reserva,
    debitar_uso_moedas,
    devolver_uso_moedas,
    liberar_bonus_pendentes,
    mes_ref,
    vencimento_de_credito_novo,
)
from trato.financeiro.ledger import CUSTODIA

DIA = timedelta(days=1)
U = "usuario-1"


def livro(*creditos: tuple[int, int | None]) -> MoedasEmMemoria:
    """Créditos (quantidade, vence em N dias a partir de AGORA; None = sem prazo)."""
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True))
    for i, (quantidade, dias) in enumerate(creditos):
        repo.lancar(
            LancamentoMoeda(
                U,
                "bonus_avaliacao",
                quantidade,
                f"c{i}",
                AGORA + timedelta(seconds=i),
                expira_em=None if dias is None else AGORA + dias * DIA,
            )
        )
    return repo


def gastar(repo, quantidade: int, dia: float = 1, cobranca: str = "cob") -> None:
    debitar_uso_moedas(
        repo,
        usuario_id=U,
        cobranca_id=cobranca,
        pedido_id="p",
        moedas=quantidade,
        agora=AGORA + dia * DIA,
    )


def saldo(repo, dia: float) -> int:
    return repo.saldo(U, AGORA + dia * DIA)


# --- 1) consumo por crédito -------------------------------------------------------------------


def test_defeito_credito_gasto_que_vence_nao_desconta_de_novo():
    repo = livro((100, 10), (100, 100))
    gastar(repo, 100)
    assert saldo(repo, 5) == 100
    assert saldo(repo, 11) == 100  # antes: 0 (o gasto continuava e o crédito dele sumia)


def test_vencimento_nunca_deixa_o_saldo_negativo():
    repo = livro((100, 10))
    gastar(repo, 80)
    assert saldo(repo, 5) == 20
    assert saldo(repo, 11) == 0  # antes: -80


def test_o_que_vence_primeiro_e_usado_primeiro_mesmo_creditado_depois():
    repo = livro((50, None), (50, 60), (50, 10))
    gastar(repo, 60)
    assert saldo(repo, 2) == 90
    assert saldo(repo, 11) == 90  # os 50 de 10 dias foram todos usados
    assert saldo(repo, 61) == 50  # sobraram 40 do de 60 dias, que venceram


def test_limite_exato_do_vencimento():
    repo = livro((100, 10))
    assert saldo(repo, 10 - 1 / 86_400) == 100
    assert saldo(repo, 10) == 0


def test_havendo_credito_valido_no_instante_do_gasto_e_dele_que_sai():
    repo = livro((100, 10), (100, 100))
    gastar(repo, 100, dia=10.01)  # o primeiro já tinha vencido
    assert saldo(repo, 11) == 0


def test_gasto_so_com_credito_vencido_nao_vira_divida():
    repo = livro((100, 10))
    gastar(repo, 100, dia=10.01)
    repo.lancar(LancamentoMoeda(U, "bonus_avaliacao", 30, "novo", AGORA + 20 * DIA))
    assert saldo(repo, 21) == 30


def test_gasto_sem_credito_abate_o_proximo():
    repo = livro((10, 100))
    gastar(repo, 30)
    assert saldo(repo, 2) == 0
    repo.lancar(LancamentoMoeda(U, "bonus_avaliacao", 50, "novo", AGORA + 3 * DIA))
    assert saldo(repo, 4) == 30


# --- 2) validade padrão ------------------------------------------------------------------------


@pytest.mark.parametrize("configurado,dias", [(None, 90), (45, 45)])
def test_credito_novo_de_avaliacao_tem_validade(configurado, dias):
    cfg = ConfigMoedas(ativo=True, validade_dias=configurado)
    assert vencimento_de_credito_novo(cfg, AGORA) == AGORA + dias * DIA


def test_bonus_liberado_sem_configuracao_vence_em_90_dias_e_o_antigo_nao_muda():
    repo = livro((10, None))  # crédito antigo sem prazo
    repo.salvar_config(ConfigMoedas(ativo=True, dias_liberacao_bonus=0))
    repo.criar_pendente(PendenteMoeda(U, "p", 50, AGORA, "bonus:p", AGORA))
    liberar_bonus_pendentes(repo, agora=AGORA, situacao_disputa=lambda _: "nenhuma")
    prazos = {i.chave_idempotencia: i.expira_em for i in repo.lancamentos_da_carteira(U)}
    assert prazos == {"c0": None, "bonus:p": AGORA + 90 * DIA}


# --- 3) devolução ------------------------------------------------------------------------------


def devolver(repo, parte: int, dia: float, base: int = 1_000, moedas: int = 100) -> bool:
    return devolver_uso_moedas(
        repo,
        usuario_id=U,
        cobranca_id="cob",
        pedido_id="p",
        moedas=moedas,
        agora=AGORA + dia * DIA,
        devolvido_centavos=parte,
        base_centavos=base,
    )


def estornos(repo) -> list[tuple[int, object]]:
    return [
        (i.quantidade, i.expira_em) for i in repo.lancamentos_da_carteira(U) if i.tipo == "estorno"
    ]


def test_devolucao_total_mantem_a_validade_de_cada_credito():
    repo = livro((60, 10), (40, 100))
    gastar(repo, 100)
    assert devolver(repo, 1_000, dia=2)
    assert estornos(repo) == [(60, AGORA + 10 * DIA), (40, AGORA + 100 * DIA)]
    assert saldo(repo, 3) == 100 and saldo(repo, 11) == 40


def test_devolucao_de_credito_vencido_vira_credito_novo_de_30_dias():
    repo = livro((60, 10), (40, 100))
    gastar(repo, 100)
    assert devolver(repo, 1_000, dia=20)
    assert estornos(repo) == [(60, AGORA + 50 * DIA), (40, AGORA + 100 * DIA)]
    assert saldo(repo, 49) == 100 and saldo(repo, 51) == 40


def test_estorno_parcial_devolve_a_proporcao_e_nunca_passa_do_total():
    repo = livro((100, 100))
    gastar(repo, 100)
    assert devolver(repo, 250, dia=2) and saldo(repo, 3) == 25
    assert not devolver(repo, 250, dia=3)  # o mesmo aviso de novo
    assert devolver(repo, 600, dia=3) and saldo(repo, 4) == 60  # acumulado, não somado
    assert not devolver(repo, 250, dia=4)  # aviso antigo chegando atrasado
    assert devolver(repo, 1_000, dia=4) and saldo(repo, 5) == 100
    assert not devolver(repo, 5_000, dia=5)
    assert sum(q for q, _ in estornos(repo)) == 100


def test_proporcao_arredonda_para_baixo_e_fecha_no_total():
    repo = livro((7, 100))
    gastar(repo, 7)
    assert not devolver(repo, 1, dia=2, moedas=7)
    assert devolver(repo, 999, dia=2, moedas=7) and saldo(repo, 3) == 6
    assert devolver(repo, 1_000, dia=3, moedas=7) and saldo(repo, 4) == 7


def test_devolucao_parcial_em_duas_vezes_percorre_os_creditos_em_ordem():
    repo = livro((60, 10), (40, 100))
    gastar(repo, 100)
    devolver(repo, 500, dia=2)
    devolver(repo, 1_000, dia=3)
    por_prazo: dict[object, int] = {}
    for quantidade, prazo in estornos(repo):
        por_prazo[prazo] = por_prazo.get(prazo, 0) + quantidade
    assert por_prazo == {AGORA + 10 * DIA: 60, AGORA + 100 * DIA: 40}


def test_estorno_antigo_ja_lancado_conta_como_devolvido():
    repo = livro((100, 100))
    gastar(repo, 100)
    repo.lancar(LancamentoMoeda(U, "estorno", 100, "estorno-uso:cob", AGORA + 2 * DIA))
    assert not devolver(repo, 1_000, dia=3) and saldo(repo, 4) == 100


def test_sem_debito_nao_ha_devolucao():
    repo = livro((100, 100))
    assert not devolver(repo, 1_000, dia=2) and estornos(repo) == []


def test_oito_devolucoes_ao_mesmo_tempo_nao_passam_do_gasto():
    for _ in range(20):
        repo = livro((60, 10), (40, 100))
        gastar(repo, 100)
        barreira = threading.Barrier(8)

        def rodar(parte: int, repo=repo, barreira=barreira) -> None:
            barreira.wait()
            devolver(repo, parte, dia=2)

        partes = [100, 300, 500, 700, 900, 1_000, 1_000, 200]
        fios = [threading.Thread(target=rodar, args=(p,)) for p in partes]
        [f.start() for f in fios]
        [f.join(10) for f in fios]
        assert sum(q for q, _ in estornos(repo)) == 100 and saldo(repo, 3) == 100


# --- pelo fluxo do pedido ----------------------------------------------------------------------


def _pago_com_moedas(f: Fluxo):
    repo = _ligar(f)
    pid = f.aceitar()
    cob = _cobrar(f, pid).json()
    _pagar(f, cob["cobranca_id"])
    assert repo.saldo(CLIENTE.id, AGORA) < 5_000
    local = f.servico.cobrancas.obter(cob["cobranca_id"])
    return repo, pid, local, 5_000 - repo.saldo(CLIENTE.id, AGORA)


def _reembolsar(f: Fluxo, pid: str, centavos: int, operacao: str) -> None:
    f.servico.aplicar_dinheiro(
        f.ctx,
        f.ctx.pedidos.obter(pid),
        operacao=operacao,
        devolver_ao_cliente=centavos,
        repartir=False,
    )


def test_reembolso_parcial_do_pedido_devolve_tratinhos_na_proporcao(fluxo: Fluxo):  # noqa: F811
    repo, pid, cobranca, usadas = _pago_com_moedas(fluxo)
    base = fluxo.servico._servico_da_cobranca(fluxo.ctx, cobranca)
    metade = cobranca.valor_centavos // 2
    antes = repo.saldo(CLIENTE.id, AGORA)
    _reembolsar(fluxo, pid, metade, "parcial")
    esperado = usadas * metade // base
    assert repo.saldo(CLIENTE.id, AGORA) == antes + esperado
    assert repo.reserva_status(chave_reserva(cobranca.id)) == "confirmada"  # parcial não libera
    _reembolsar(fluxo, pid, metade, "parcial")  # repetição da mesma operação
    assert repo.saldo(CLIENTE.id, AGORA) == antes + esperado


def test_estorno_total_apos_pagamento_tardio_libera_a_reserva_reaberta(fluxo: Fluxo):  # noqa: F811
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    repo.devolver_reserva(chave_reserva(cob["cobranca_id"]))
    _pagar(fluxo, cob["cobranca_id"])
    reaberta = chave_reserva(f"reabertura:{cob['cobranca_id']}")
    assert repo.reserva_status(reaberta) == "confirmada" and repo.orcamento_usado(mes_ref(AGORA))

    _reembolsar(fluxo, pid, fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid), "total")

    assert repo.reserva_status(reaberta) == "devolvida"
    assert repo.orcamento_usado(mes_ref(AGORA)) == 0
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000
