"""Garantia e retrabalho (F4.8). Python puro: sem banco, relógio injetável."""

from trato.garantias.config import ConfigGarantia
from trato.garantias.garantia import ErroGarantia, Garantia, abrir_garantia, garantia_ativa_agora
from trato.garantias.retrabalho import (
    ErroRetrabalho,
    EstadoRetrabalho,
    Retrabalho,
    abrir_retrabalho,
    deve_virar_nao_atendido,
    marcar_nao_atendido_se_vencido,
    transicionar,
)

__all__ = [
    "ConfigGarantia",
    "ErroGarantia",
    "ErroRetrabalho",
    "EstadoRetrabalho",
    "Garantia",
    "Retrabalho",
    "abrir_garantia",
    "abrir_retrabalho",
    "deve_virar_nao_atendido",
    "garantia_ativa_agora",
    "marcar_nao_atendido_se_vencido",
    "transicionar",
]
