"""BE-NOTA-12.3 (Termos 12.3): nota pública com peso maior nas avaliações mais recentes."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from trato.api.memoria_app import AvaliacoesEmMemoria, calcular_nota_publica
from trato.api.repositorios_app import Avaliacao

BASE = datetime(2026, 11, 1, 12, 0, tzinfo=UTC)


def _av(
    idx: int,
    nota_geral: int,
    *,
    nota_decimal: float | None = None,
    direcao: str = "cliente_para_profissional",
    status: str = "publicada",
    minutos: int | None = None,
    avaliado_id: str = "prof-1",
) -> Avaliacao:
    return Avaliacao(
        pedido_id=f"ped-{idx}",
        direcao=direcao,
        avaliador_id=f"cli-{idx}",
        avaliado_id=avaliado_id,
        nota_geral=nota_geral,
        comentario=None,
        etiquetas=(),
        criada_em=BASE + timedelta(minutes=idx if minutos is None else minutos),
        id=f"av-{idx:02d}",
        nota_decimal=nota_decimal,
        status=status,
    )


def test_nota_publica_sem_avaliacoes_retorna_none():
    repo = AvaliacoesEmMemoria()
    assert repo.media_recebida("prof-1") is None


def test_nota_publica_ate_n_avaliacoes_equivale_a_media_simples():
    repo = AvaliacoesEmMemoria()
    repo.salvar(_av(1, 5, nota_decimal=4.8))
    repo.salvar(_av(2, 4))
    assert repo.media_recebida("prof-1") == 4.4


def test_nota_publica_peso_maior_para_recentes_e_ignora_removidas_e_outra_direcao():
    repo = AvaliacoesEmMemoria()
    # 1 avaliação antiga com nota 1 e 5 recentes com nota 5:
    # média simples seria (1 + 25) / 6 = 4.33; com N=5 e P=2: (1*1 + 5*5*2) / (1 + 10) = 51/11 = 4.64
    repo.salvar(_av(1, 1))
    for i in range(2, 7):
        repo.salvar(_av(i, 5))
    # Avaliações removidas, em revisão ou na direção inversa não entram
    repo.salvar(_av(7, 1, status="descartada"))
    repo.salvar(_av(8, 1, status="em_revisao"))
    repo.salvar(_av(9, 1, direcao="profissional_para_cliente"))
    assert repo.media_recebida("prof-1") == 4.64


def test_nota_publica_respeita_n_e_peso_configurados_e_desempate_por_id():
    itens = [
        _av(1, 1, minutos=10),  # mesmo instante, id menor -> mais antiga
        _av(2, 5, minutos=10),  # mesmo instante, id maior -> mais recente
        _av(3, 5, minutos=20),
    ]
    # Com N=2 e P=3: av-03 (5*3) + av-02 (5*3) + av-01 (1*1) = 31 / 7 = 4.4285... -> 4.43
    assert calcular_nota_publica(itens, recentes_quantidade=2, recentes_peso=3) == 4.43
    # Com P=1: média simples = 11 / 3 = 3.67
    assert calcular_nota_publica(itens, recentes_quantidade=2, recentes_peso=1) == 3.67
