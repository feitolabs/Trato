"""Papéis da equipe e o que cada um pode fazer na API administrativa.

A matriz espelha a do painel (`admin/lib/nucleo/papeis.dart`). Quem barra de verdade é o backend:
o papel vem da tabela `equipe` a cada chamada (papel revogado ou inativo é negado na hora).
"""

from __future__ import annotations

from enum import StrEnum


class PapelEquipe(StrEnum):
    ATENDENTE_N1 = "atendente_n1"
    ATENDENTE_N2 = "atendente_n2"
    MEDIADOR = "mediador"
    FINANCEIRO = "financeiro"
    SEGURANCA = "seguranca"
    CADASTRO = "cadastro"
    MODERADOR = "moderador"
    JURIDICO = "juridico"
    DPO = "dpo"
    LIDER_SUPORTE = "lider_suporte"
    ADMINISTRADOR = "administrador"


class Permissao(StrEnum):
    VERIFICACOES_VER = "verificacoes_ver"
    VERIFICACOES_DECIDIR = "verificacoes_decidir"
    DOCUMENTOS_REVELAR = "documentos_revelar"
    DISPUTAS_VER = "disputas_ver"
    DISPUTAS_DECIDIR = "disputas_decidir"
    DISPUTAS_SEGUNDA_PESSOA = "disputas_segunda_pessoa"
    PAGAMENTOS_VER = "pagamentos_ver"
    USUARIOS_BUSCAR = "usuarios_buscar"
    DADOS_PESSOAIS_REVELAR = "dados_pessoais_revelar"
    PEDIDOS_BUSCAR = "pedidos_buscar"
    CONFIG_VER = "config_ver"
    CONFIG_PROPOR = "config_propor"
    CONFIG_APROVAR = "config_aprovar"
    AUDITORIA_VER = "auditoria_ver"
    AUDITORIA_VERIFICAR_CADEIA = "auditoria_verificar_cadeia"


P = PapelEquipe
X = Permissao

MATRIZ: dict[PapelEquipe, frozenset[Permissao]] = {
    P.ATENDENTE_N1: frozenset({X.USUARIOS_BUSCAR, X.PEDIDOS_BUSCAR}),
    P.ATENDENTE_N2: frozenset({X.USUARIOS_BUSCAR, X.PEDIDOS_BUSCAR, X.DISPUTAS_VER}),
    P.LIDER_SUPORTE: frozenset(
        {
            X.USUARIOS_BUSCAR,
            X.PEDIDOS_BUSCAR,
            X.DISPUTAS_VER,
            X.DISPUTAS_DECIDIR,
            X.DISPUTAS_SEGUNDA_PESSOA,
        }
    ),
    P.MEDIADOR: frozenset({X.PEDIDOS_BUSCAR, X.DISPUTAS_VER, X.DISPUTAS_DECIDIR}),
    P.CADASTRO: frozenset(
        {
            X.VERIFICACOES_VER,
            X.VERIFICACOES_DECIDIR,
            X.DOCUMENTOS_REVELAR,
            X.USUARIOS_BUSCAR,
            X.DADOS_PESSOAIS_REVELAR,
        }
    ),
    P.MODERADOR: frozenset({X.USUARIOS_BUSCAR, X.PEDIDOS_BUSCAR}),
    P.FINANCEIRO: frozenset({X.PAGAMENTOS_VER, X.PEDIDOS_BUSCAR, X.CONFIG_VER, X.CONFIG_PROPOR}),
    P.SEGURANCA: frozenset(
        {
            X.VERIFICACOES_VER,
            X.USUARIOS_BUSCAR,
            X.DADOS_PESSOAIS_REVELAR,
            X.AUDITORIA_VER,
            X.AUDITORIA_VERIFICAR_CADEIA,
        }
    ),
    P.JURIDICO: frozenset({X.CONFIG_VER, X.AUDITORIA_VER, X.AUDITORIA_VERIFICAR_CADEIA}),
    P.DPO: frozenset(
        {
            X.USUARIOS_BUSCAR,
            X.DADOS_PESSOAIS_REVELAR,
            X.AUDITORIA_VER,
            X.AUDITORIA_VERIFICAR_CADEIA,
        }
    ),
    P.ADMINISTRADOR: frozenset(
        {
            X.VERIFICACOES_VER,
            X.DISPUTAS_VER,
            X.DISPUTAS_DECIDIR,
            X.DISPUTAS_SEGUNDA_PESSOA,
            X.PAGAMENTOS_VER,
            X.USUARIOS_BUSCAR,
            X.PEDIDOS_BUSCAR,
            X.CONFIG_VER,
            X.CONFIG_PROPOR,
            X.CONFIG_APROVAR,
            X.AUDITORIA_VER,
            X.AUDITORIA_VERIFICAR_CADEIA,
        }
    ),
}
del P, X


def pode(papel: PapelEquipe, permissao: Permissao) -> bool:
    return permissao in MATRIZ[papel]
