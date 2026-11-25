"""Ressalvas da Segurança no B43: ReDoS no perfil, slugs do catálogo e aviso do piso."""

from __future__ import annotations

import logging
import re
import time
from pathlib import Path
from types import SimpleNamespace

from trato.api.servicos import garantia_minima_do_pedido
from trato.garantias.config import SLUGS_DURAVEIS, SLUGS_NAO_DURAVEIS
from trato.seguranca.mascaramento import mascarar

RAIZ = Path(__file__).resolve().parents[3]


def _melhor_ms(texto: str, vezes: int = 5) -> float:
    """Melhor de N execuções: o ruído de uma máquina ocupada só piora, nunca melhora."""
    melhor = float("inf")
    for _ in range(vezes):
        inicio = time.perf_counter()
        mascarar(texto)
        melhor = min(melhor, (time.perf_counter() - inicio) * 1000)
    return melhor


def test_perfil_com_muitos_espacos_nao_e_quadratico():
    for molde in ("ig{}", "x insta{}!", "ig{}@"):
        pequeno = _melhor_ms(molde.format(" " * 1000))
        grande = _melhor_ms(molde.format(" " * 4000))
        # 4x a entrada: linear dá ~4x; quadrático daria ~16x. Piso de 1 ms evita razão de ruído.
        assert grande < 6 * max(pequeno, 1.0), (molde, pequeno, grande)
        assert grande < 300, (molde, grande)


def test_perfil_ainda_mascara_variacoes():
    for texto in ("ig: fulano123", "insta fulano_tal", "instagram = @fulano.tal", "ig @fulano123"):
        assert mascarar(texto).exibido != texto, texto


def _slugs_do_catalogo() -> set[str]:
    achados: set[str] = set()
    completo = RAIZ / "supabase" / "seeds" / "seed_categorias_completas.sql"
    for linha in completo.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*\(\d+,\s*'(?:[^']|'')*',\s*'([a-z0-9-]+)',\s*\d+,", linha)
        if m:
            achados.add(m.group(1))
    parametros = (RAIZ / "supabase" / "seeds" / "parametros.sql").read_text(encoding="utf-8")
    achados |= set(re.findall(r"'cat\d+_slug',\s*'([a-z0-9-]+)'", parametros))
    return achados


def test_todo_slug_do_catalogo_tem_decisao_de_garantia():
    slugs = _slugs_do_catalogo()
    assert len(slugs) >= 20, "o seed do catálogo mudou de formato; ajuste o leitor do teste"
    sem_decisao = slugs - SLUGS_DURAVEIS - SLUGS_NAO_DURAVEIS
    assert not sem_decisao, (
        f"Categoria nova sem decisão de garantia (durável ou não) em garantias/config.py: "
        f"{sorted(sem_decisao)}"
    )


def test_piso_ausente_registra_aviso_sem_mudar_o_comportamento(caplog):
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace()))
    contexto = SimpleNamespace(pedidos=SimpleNamespace(dados_do_pedido=lambda _id: None))
    with caplog.at_level(logging.WARNING, logger="trato.api.servicos"):
        assert garantia_minima_do_pedido(request, contexto, "ped-secreto-123") is None
    assert any("Piso de garantia não aplicado" in r.message for r in caplog.records)
    assert not any("ped-secreto-123" in r.getMessage() for r in caplog.records)


def test_regras_novas_de_perfil_e_digitos_isolados_nao_sao_quadraticas():
    for molde in ("ig fulano{}", "9 {}", "nove {}", "zap{}", "i g{}x", "{}ig"):
        base = {"ig fulano{}": " ", "9 {}": "9 ", "nove {}": "nove ", "zap{}": " ", "i g{}x": " "}
        unidade = base.get(molde, " ")
        pequeno = _melhor_ms(molde.format(unidade * 1000))
        grande = _melhor_ms(molde.format(unidade * 4000))
        assert grande < 6 * max(pequeno, 1.0), (molde, pequeno, grande)
        assert grande < 300, (molde, grande)
