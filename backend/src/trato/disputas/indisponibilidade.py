"""Termos 22.3: falha do app ou do Parceiro de Pagamento prorroga, pelo tempo da falha, os
prazos dos atos afetados. Funções puras sobre intervalos `(inicio, fim)`; `fim=None`: ainda
ativa."""

from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime, timedelta

Intervalo = tuple[datetime, datetime | None]


def unir(intervalos: Iterable[Intervalo]) -> list[Intervalo]:
    """Junta o que se sobrepõe ou encosta (de qualquer origem): nada conta em dobro."""
    saida: list[Intervalo] = []
    for inicio, fim in sorted(intervalos, key=lambda i: i[0]):
        if saida and (saida[-1][1] is None or inicio <= saida[-1][1]):
            antes_inicio, antes_fim = saida[-1]
            maior = None if antes_fim is None or fim is None else max(antes_fim, fim)
            saida[-1] = (antes_inicio, maior)
        else:
            saida.append((inicio, fim))
    return saida


def prorrogar(desde: datetime, prazo: timedelta, falhas: Iterable[Intervalo]) -> datetime | None:
    """Novo vencimento de um prazo que corre de `desde` por `prazo`: soma o tempo de falha
    dentro dele, inclusive o que cai na própria prorrogação. `None`: há falha ativa alcançando
    o prazo, que fica suspenso."""
    limite = desde + prazo
    for inicio, fim in unir(falhas):
        if inicio > limite:
            break
        if fim is None:
            return None
        if fim > desde:
            limite += fim - max(inicio, desde)
    return limite


def cobre(inicio_evento: datetime, fim_evento: datetime, falhas: Iterable[Intervalo]) -> bool:
    """Alguma falha alcançou o período do evento?"""
    return any(
        inicio <= fim_evento and (fim is None or fim > inicio_evento) for inicio, fim in falhas
    )


def ultimo_inicio_vencido(
    agora: datetime, prazo: timedelta, falhas: Iterable[Intervalo]
) -> datetime:
    """Quem começou até este instante já teve `prazo` inteiro sem falha até `agora`."""
    resta, cursor = prazo, agora
    for inicio, fim in reversed(unir(falhas)):
        if inicio >= cursor:
            continue
        fim = cursor if fim is None else min(fim, cursor)
        livre = cursor - fim
        if livre >= resta:
            break
        resta -= livre
        cursor = inicio
    return cursor - resta


def estender(falhas: list[Intervalo], desde: datetime, ate: datetime, agora: datetime) -> datetime:
    """O vencimento `ate` de um prazo iniciado em `desde`, já prorrogado, para conferir e para
    mostrar. Falha ainda ativa conta até `agora`, e o prazo alcançado por ela não vence."""
    if ate <= desde:
        return ate
    comecadas = [(i, f) for i, f in falhas if f is not None or i < agora]
    novo = prorrogar(desde, ate - desde, [(i, f if f else agora) for i, f in comecadas])
    if novo is None:  # impossível: não há intervalo aberto aqui
        return ate
    if novo <= agora and any(f is None and i <= novo for i, f in comecadas):
        novo = agora + timedelta(microseconds=1)
    return novo
