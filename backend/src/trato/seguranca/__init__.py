"""Segurança do backend: mascaramento, antifraude, limite de taxa, cabeçalhos e upload (Fase 8).

`registrar_rotas(app)` liga tudo ao app (e as rotas de LGPD de `trato.lgpd`). A importação é
preguiçosa de propósito: `persistencia.conversas` importa `seguranca.mascaramento`, e carregar as
rotas aqui criaria um ciclo.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def registrar_rotas(app: FastAPI) -> FastAPI:
    from trato.seguranca.instalacao import instalar_seguranca

    return instalar_seguranca(app)
