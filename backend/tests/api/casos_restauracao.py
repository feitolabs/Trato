"""Casos da regra de restauração (migration 20261127133600), usados em memória e na paridade com
o Postgres. Item: (quantidade, tipo, dia da criação, dia do vencimento, chave); o encerramento
é no dia -40 e a conta é feita no dia 0. Origem: tabela de casos do Banco (DB-SEG-M6B)."""

from __future__ import annotations


def uso(q, quando, chave="uso:c1", tipo="uso"):
    return (-q, tipo, quando, None, chave)


def volta(q, quando, vence, chave="estorno-uso:c1:30:0", tipo="estorno"):
    return (q, tipo, quando, vence, chave)


A = (100, "ajuste", -100, -20, "A")
XU = uso(30, -50, "exclusividade-uso:x1", "exclusividade_uso")
XV = "exclusividade-estorno:x1"

CASOS = {
    "estorno depois com a validade original": ([A, uso(30, -50), volta(30, -30, -20)], 100),
    "estorno com validade nova": ([A, uso(30, -50), volta(30, -10, 20)], 70),
    "gasto e estorno depois": ([A, uso(30, -35), volta(30, -30, -20)], 100),
    "gasto depois sem estorno": ([A, uso(30, -35)], 70),
    "estorno parcial": ([A, uso(30, -50), volta(10, -30, -20, "estorno-uso:c1:10:0")], 80),
    "estornado e gasto de novo": (
        [A, uso(30, -50), volta(30, -30, -20), uso(30, -25, "uso:c2")], 70),
    "dois ciclos": (
        [A, uso(30, -50), volta(30, -30, -20), uso(30, -27, "uso:c2"),
         volta(30, -25, -20, "estorno-uso:c2:30:0")], 100),
    "gasto de lote novo estornado": (
        [A, (50, "ajuste", -35, -25, "B"), uso(30, -33), volta(30, -30, -25)], 100),
    "estorno misto": (
        [A, (50, "ajuste", -35, -20, "B"), uso(120, -33),
         volta(120, -30, -20, "estorno-uso:c1:120:0")], 100),
    "estorno sem gasto": ([A, volta(30, -30, -20, "estorno-uso:zz:30:0")], 100),
    "estorno repetido": (
        [A, uso(30, -50), volta(30, -30, -20), volta(30, -29, -20, "estorno-uso:c1:60:0")], 100),
    "exclusividade estornada": ([A, XU, volta(30, -30, -20, XV, "exclusividade_estorno")], 100),
    "exclusividade 2a parcela": (
        [A, XU, volta(30, -30, -20, XV + ":2", "exclusividade_estorno")], 100),
    "validade no futuro": ([(100, "ajuste", -100, 30, "A"), uso(30, -50), volta(30, -30, 30)], 0),
    "estorno antes do encerramento": ([A, uso(30, -60), volta(30, -50, -20)], 100),
    "estorno abate divida": (
        [A, uso(130, -50), volta(130, -30, -20, "estorno-uso:c1:130:0")], 100),
    "chave sem sufixo": ([A, uso(30, -50), volta(30, -30, -20, "estorno-uso:c1")], 100),
    "chave de outra cobranca": (
        [A, uso(30, -50), volta(30, -30, -20, "estorno-uso:c10:30:0")], 70),
    "ajuste com chave de estorno": (
        [A, uso(30, -50), volta(30, -30, -20, "estorno-uso:c1:30:0", "ajuste")], 70),
    "credito novo vencido": ([A, (50, "ajuste", -35, -5, "B")], 100),
}  # fmt: skip


def com_sufixo(chave: str, sufixo: str) -> str:
    """Chave única no banco entre casos, sem perder a ligação devolução -> gasto."""
    for prefixo in ("estorno-uso:", "exclusividade-estorno:", "exclusividade-uso:", "uso:", ""):
        if chave.startswith(prefixo):
            return prefixo + sufixo + chave[len(prefixo) :]
    return chave
