"""Plugin mínimo do pytest para dividir os testes em N partes por arquivo (sharding).

Ativado apenas quando TRATO_PYTEST_SHARD=I/N está definido (1 <= I <= N).
Mantém exatamente a mesma coleta e ordem de conftest.py do `pytest -q`,
mantendo todos os testes de cada arquivo juntos e na ordem original, e
equilibrando o tempo entre as partes (com peso maior para testes de integração).
"""

from __future__ import annotations

import os
from collections import defaultdict


def _chave_arquivo(nodeid: str) -> str:
    return nodeid.split("::", 1)[0].replace("\\", "/")


def _peso_arquivo(caminho: str, qtd_testes: int) -> int:
    # Testes de integração usam Postgres embutido (pgserver) e são bem mais lentos.
    fator = 10 if "/integracao/" in f"/{caminho}" else 1
    return qtd_testes * fator


def pytest_collection_modifyitems(items: list) -> None:
    spec = os.environ.get("TRATO_PYTEST_SHARD", "").strip()
    if not spec:
        return
    partes = spec.split("/")
    if len(partes) != 2 or not all(p.isdigit() for p in partes):
        raise ValueError(f"TRATO_PYTEST_SHARD inválido: {spec!r} (use I/N, ex.: 1/4)")
    indice, total = int(partes[0]), int(partes[1])
    if total < 1 or not (1 <= indice <= total):
        raise ValueError(f"TRATO_PYTEST_SHARD fora do intervalo: {spec!r}")

    contagem_por_arquivo: dict[str, int] = defaultdict(int)
    for item in items:
        contagem_por_arquivo[_chave_arquivo(item.nodeid)] += 1

    # Greedy LPT determinístico: arquivos mais pesados primeiro no shard menos carregado.
    arquivos_ordenados = sorted(
        contagem_por_arquivo.items(),
        key=lambda par: (-_peso_arquivo(par[0], par[1]), par[0]),
    )
    cargas = [0] * total
    shard_do_arquivo: dict[str, int] = {}
    for caminho, qtd in arquivos_ordenados:
        menor_shard = min(range(total), key=lambda s: (cargas[s], s))
        shard_do_arquivo[caminho] = menor_shard
        cargas[menor_shard] += _peso_arquivo(caminho, qtd)

    alvo = indice - 1
    # Preserva exatamente a ordem original dos itens (e dentro de cada arquivo).
    items[:] = [item for item in items if shard_do_arquivo[_chave_arquivo(item.nodeid)] == alvo]
