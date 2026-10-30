"""Catálogo de eventos do domínio que viram notificação.

Texto curto e sem prometer o que o Trato não faz (D13: ver a lista de textos proibidos em
harness/DECISOES.md). O código de início NUNCA vai no texto nem no `dados`: a notificação só
leva o usuário até a tela onde ele aparece.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class Categoria(StrEnum):
    """Grupo que a pessoa liga/desliga nas preferências."""

    ORCAMENTOS = "orcamentos"
    PAGAMENTOS = "pagamentos"
    AGENDA = "agenda"
    EXECUCAO = "execucao"
    DISPUTAS = "disputas"
    AVALIACOES = "avaliacoes"


class Evento(StrEnum):
    ORCAMENTO_RECEBIDO = "orcamento.recebido"
    ORCAMENTO_ACEITO = "orcamento.aceito"
    PAGAMENTO_CONFIRMADO = "pagamento.confirmado"
    LEMBRETE_AGENDAMENTO = "agenda.lembrete"
    CODIGO_INICIO = "agenda.codigo_inicio"
    CONCLUSAO_PARA_CONFIRMAR = "execucao.confirmar_conclusao"
    ADITIVO_PENDENTE = "execucao.aditivo_pendente"
    DISPUTA_ABERTA = "disputa.aberta"
    DISPUTA_RESPONDIDA = "disputa.respondida"
    DISPUTA_DECIDIDA = "disputa.decidida"
    LEMBRETE_RESPOSTA_DISPUTA = "disputa.lembrete_resposta"
    RETRABALHO = "garantia.retrabalho"
    AVALIACAO = "avaliacao.recebida"


@dataclass(frozen=True)
class ModeloEvento:
    categoria: Categoria
    titulo: str
    corpo: str
    tela: str  # tela do app: vira o deep link
    essencial: bool = False  # sempre aparece na caixa de entrada, mesmo com a categoria desligada


MODELOS: dict[Evento, ModeloEvento] = {
    Evento.ORCAMENTO_RECEBIDO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Novo orçamento",
        "Você recebeu um orçamento para o seu pedido.",
        "orcamentos",
    ),
    Evento.ORCAMENTO_ACEITO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Orçamento aceito",
        "O cliente aceitou o seu orçamento.",
        "pedido",
        essencial=True,
    ),
    Evento.PAGAMENTO_CONFIRMADO: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Pagamento confirmado",
        "O parceiro de pagamento confirmou o pagamento do pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.LEMBRETE_AGENDAMENTO: ModeloEvento(
        Categoria.AGENDA,
        "Serviço agendado",
        "Seu serviço está chegando. Veja os detalhes.",
        "pedido",
    ),
    Evento.CODIGO_INICIO: ModeloEvento(
        Categoria.AGENDA,
        "Código de início disponível",
        "Abra o pedido para ver o código que o profissional vai pedir na chegada.",
        "pedido",
        essencial=True,
    ),
    Evento.CONCLUSAO_PARA_CONFIRMAR: ModeloEvento(
        Categoria.EXECUCAO,
        "Confirme o serviço",
        "O profissional terminou. Confirme se está tudo certo.",
        "pedido",
        essencial=True,
    ),
    Evento.ADITIVO_PENDENTE: ModeloEvento(
        Categoria.EXECUCAO,
        "Aditivo aguardando você",
        "Há uma mudança de valor ou escopo esperando a sua resposta.",
        "pedido",
        essencial=True,
    ),
    Evento.DISPUTA_ABERTA: ModeloEvento(
        Categoria.DISPUTAS,
        "Reclamação aberta",
        "Uma reclamação foi aberta neste pedido.",
        "disputa",
        essencial=True,
    ),
    Evento.DISPUTA_RESPONDIDA: ModeloEvento(
        Categoria.DISPUTAS,
        "Reclamação respondida",
        "A outra parte respondeu à reclamação.",
        "disputa",
        essencial=True,
    ),
    Evento.DISPUTA_DECIDIDA: ModeloEvento(
        Categoria.DISPUTAS,
        "Reclamação analisada",
        "A análise da reclamação terminou.",
        "disputa",
        essencial=True,
    ),
    Evento.LEMBRETE_RESPOSTA_DISPUTA: ModeloEvento(
        Categoria.DISPUTAS,
        "Responda a reclamação",
        "O prazo para responder à reclamação está acabando.",
        "disputa",
        essencial=True,
    ),
    Evento.RETRABALHO: ModeloEvento(
        Categoria.DISPUTAS,
        "Retrabalho pedido",
        "O cliente pediu um retrabalho neste serviço.",
        "pedido",
        essencial=True,
    ),
    Evento.AVALIACAO: ModeloEvento(
        Categoria.AVALIACOES, "Nova avaliação", "Você recebeu uma avaliação.", "avaliacao"
    ),
}


def deep_link(base: str, tela: str, pedido_id: str | None) -> str:
    return f"{base}{tela}/{pedido_id}" if pedido_id else f"{base}{tela}"
