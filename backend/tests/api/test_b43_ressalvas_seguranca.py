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


def _tempo_ms(texto: str) -> float:
    inicio = time.perf_counter()
    mascarar(texto)
    return (time.perf_counter() - inicio) * 1000


def test_perfil_com_muitos_espacos_nao_e_quadratico():
    for entrada in ("ig" + " " * 2000, "x " + "insta" + " " * 5000 + "!", "ig" + " " * 2000 + "@"):
        assert _tempo_ms(entrada) < 20, entrada[:10]


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
