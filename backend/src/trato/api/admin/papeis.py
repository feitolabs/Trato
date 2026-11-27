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
    CONVERSAS_LER = "conversas_ler"  # só com motivo e vínculo no pedido (Termos 11.3)
    DISPUTAS_VER = "disputas_ver"
    DISPUTAS_DECIDIR = "disputas_decidir"
    DISPUTAS_SEGUNDA_PESSOA = "disputas_segunda_pessoa"
    COMPENSACOES_CANCELAR = "compensacoes_cancelar"  # só líder de suporte e administrador
    REGRESSO_PROPOR = "regresso_propor"  # propor regresso e reenviar o aviso (17.4)
    REGRESSO_APROVAR = "regresso_aprovar"  # aprovar ou recusar: líder e administrador
    LGPD_APAGAR_PROVAS = "lgpd_apagar_provas"  # DPO e administrador
    LGPD_PEDIDOS_GERENCIAR = "lgpd_pedidos_gerenciar"  # pedidos de titular LGPD (14.9)
    LGPD_REVISAO_AUTOMATIZADA = "lgpd_revisao_automatizada"  # revisão automatizada (14.10)
    PAGAMENTOS_VER = "pagamentos_ver"
    PAGAMENTOS_CONCILIAR = "pagamentos_conciliar"
    USUARIOS_BUSCAR = "usuarios_buscar"
    USUARIOS_STATUS = "usuarios_status"  # bloquear, restringir e reativar contas (só administrador)
    DADOS_PESSOAIS_REVELAR = "dados_pessoais_revelar"
    PEDIDOS_BUSCAR = "pedidos_buscar"
    CONFIG_VER = "config_ver"
    CONFIG_PROPOR = "config_propor"
    CONFIG_APROVAR = "config_aprovar"
    AUDITORIA_VER = "auditoria_ver"
    AUDITORIA_VERIFICAR_CADEIA = "auditoria_verificar_cadeia"
    CATEGORIAS_EDITAR = "categorias_editar"
    SUPORTE_VER = "suporte_ver"
    MEDIDAS_APLICAR = "medidas_aplicar"  # aplicar, reverter e rever medida de conta (20)
    CONTA_RETORNO_ANALISAR = (
        "conta_retorno_analisar"  # listar impedimentos/retornos, analisar e recusar (20.9)
    )
    CONTA_RETORNO_APROVAR = "conta_retorno_aprovar"  # aprovar retorno e revogar impedimento (20.9)
    SAC_RESPONDER = "sac_responder"  # registrar contato, assumir, responder e encerrar chamado
    INCIDENTES_VER = "incidentes_ver"  # incidentes de segurança (9.3 a 9.6)
    INCIDENTES_TRATAR = "incidentes_tratar"  # abrir, registrar medida e mudar o andamento
    INCIDENTES_ENCERRAR = "incidentes_encerrar"  # encerrar pode soltar o valor retido
    AVALIACOES_MODERAR = "avaliacoes_moderar"  # ocultar/reverter avaliação e decidir revisão (12.6)
    MATERIAIS_CONTESTACAO_ANALISAR = "materiais_contestacao_analisar"  # contestação de nota (6.9)
    MATERIAIS_CONTESTACAO_APROVAR = "materiais_contestacao_aprovar"  # 4 olhos financeiro (6.9)
    DASHBOARD_VER = "dashboard_ver"
    RISCO_VER = "risco_ver"
    RISCO_DECIDIR = "risco_decidir"
    NOTIFICACOES_ENVIAR = "notificacoes_enviar"
    CUPONS_GERENCIAR = "cupons_gerenciar"
    MOEDAS_CONFIGURAR = "moedas_configurar"  # alterar a configuração dos Tratinhos
    EQUIPE_GERENCIAR = "equipe_gerenciar"
    RELATORIOS_EXPORTAR = "relatorios_exportar"


P = PapelEquipe
X = Permissao

MATRIZ: dict[PapelEquipe, frozenset[Permissao]] = {
    P.ATENDENTE_N1: frozenset(
        {X.USUARIOS_BUSCAR, X.PEDIDOS_BUSCAR, X.SUPORTE_VER, X.SAC_RESPONDER}
    ),
    P.ATENDENTE_N2: frozenset(
        {X.USUARIOS_BUSCAR, X.PEDIDOS_BUSCAR, X.DISPUTAS_VER, X.SUPORTE_VER, X.SAC_RESPONDER}
    ),
    P.LIDER_SUPORTE: frozenset(
        {
            X.INCIDENTES_VER,
            X.MATERIAIS_CONTESTACAO_ANALISAR,
            X.MATERIAIS_CONTESTACAO_APROVAR,
            X.CONTA_RETORNO_ANALISAR,
            X.CONTA_RETORNO_APROVAR,
            X.AVALIACOES_MODERAR,
            X.INCIDENTES_TRATAR,
            X.INCIDENTES_ENCERRAR,
            X.USUARIOS_BUSCAR,
            X.PEDIDOS_BUSCAR,
            X.DISPUTAS_VER,
            X.DISPUTAS_DECIDIR,
            X.DISPUTAS_SEGUNDA_PESSOA,
            X.COMPENSACOES_CANCELAR,
            X.REGRESSO_PROPOR,
            X.REGRESSO_APROVAR,
            X.CONVERSAS_LER,
            X.MEDIDAS_APLICAR,
            X.SUPORTE_VER,
            X.SAC_RESPONDER,
            X.DASHBOARD_VER,
        }
    ),
    P.MEDIADOR: frozenset(
        {
            X.INCIDENTES_VER,
            X.MATERIAIS_CONTESTACAO_ANALISAR,
            X.CONTA_RETORNO_ANALISAR,
            X.AVALIACOES_MODERAR,
            X.INCIDENTES_TRATAR,
            X.PEDIDOS_BUSCAR,
            X.DISPUTAS_VER,
            X.DISPUTAS_DECIDIR,
            X.REGRESSO_PROPOR,
            X.CONVERSAS_LER,
            X.MEDIDAS_APLICAR,
        }
    ),
    P.CADASTRO: frozenset(
        {
            X.VERIFICACOES_VER,
            X.VERIFICACOES_DECIDIR,
            X.DOCUMENTOS_REVELAR,
            X.USUARIOS_BUSCAR,
            X.DADOS_PESSOAIS_REVELAR,
        }
    ),
    P.MODERADOR: frozenset(
        {
            X.USUARIOS_BUSCAR,
            X.PEDIDOS_BUSCAR,
            X.CATEGORIAS_EDITAR,
            X.NOTIFICACOES_ENVIAR,
            X.CUPONS_GERENCIAR,
        }
    ),
    P.FINANCEIRO: frozenset(
        {
            X.PAGAMENTOS_VER,
            X.PAGAMENTOS_CONCILIAR,
            X.PEDIDOS_BUSCAR,
            X.CONFIG_VER,
            X.CONFIG_PROPOR,
            X.DASHBOARD_VER,
            X.CUPONS_GERENCIAR,
            X.MOEDAS_CONFIGURAR,
            X.RELATORIOS_EXPORTAR,
        }
    ),
    P.SEGURANCA: frozenset(
        {
            X.INCIDENTES_VER,
            X.MATERIAIS_CONTESTACAO_ANALISAR,
            X.CONTA_RETORNO_ANALISAR,
            X.LGPD_REVISAO_AUTOMATIZADA,
            X.AVALIACOES_MODERAR,
            X.INCIDENTES_TRATAR,
            X.INCIDENTES_ENCERRAR,
            X.VERIFICACOES_VER,
            X.USUARIOS_BUSCAR,
            X.DADOS_PESSOAIS_REVELAR,
            X.AUDITORIA_VER,
            X.AUDITORIA_VERIFICAR_CADEIA,
            X.RISCO_VER,
            X.RISCO_DECIDIR,
            X.CONVERSAS_LER,
            X.MEDIDAS_APLICAR,
            X.REGRESSO_PROPOR,
        }
    ),
    P.JURIDICO: frozenset({X.CONFIG_VER, X.AUDITORIA_VER, X.AUDITORIA_VERIFICAR_CADEIA}),
    P.DPO: frozenset(
        {
            X.LGPD_APAGAR_PROVAS,
            X.LGPD_PEDIDOS_GERENCIAR,
            X.LGPD_REVISAO_AUTOMATIZADA,
            X.USUARIOS_BUSCAR,
            X.DADOS_PESSOAIS_REVELAR,
            X.AUDITORIA_VER,
            X.AUDITORIA_VERIFICAR_CADEIA,
        }
    ),
    # Administrador tem autonomia irrestrita em todas as permissões do sistema
    P.ADMINISTRADOR: frozenset(Permissao),
}
del P, X


def pode(papel: PapelEquipe, permissao: Permissao) -> bool:
    return permissao in MATRIZ[papel]
