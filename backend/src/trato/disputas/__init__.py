"""Regras de disputa (escopo 3.5, decisão D7). Python puro: sem banco, sem relógio global."""

from trato.disputas.config import ConfigDisputa
from trato.disputas.erros import (
    AlcadaInvalida,
    DisputaErro,
    PrazoExpirado,
    ResultadoInvalido,
    TransicaoInvalida,
)
from trato.disputas.maquina import Ator, Disputa, Estado, Motivo, abrir
from trato.disputas.prazos import Prazos, adicionar_dias_uteis, calcular_prazos, dentro_da_janela
from trato.disputas.resultado import Decisao, Divisao, Resultado, dividir_valor

__all__ = [
    "AlcadaInvalida",
    "Ator",
    "ConfigDisputa",
    "Decisao",
    "Disputa",
    "DisputaErro",
    "Divisao",
    "Estado",
    "Motivo",
    "PrazoExpirado",
    "Prazos",
    "Resultado",
    "ResultadoInvalido",
    "TransicaoInvalida",
    "abrir",
    "adicionar_dias_uteis",
    "calcular_prazos",
    "dentro_da_janela",
    "dividir_valor",
]
