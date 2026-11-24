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
    MENSAGENS = "mensagens"


class Evento(StrEnum):
    ORCAMENTO_RECEBIDO = "orcamento.recebido"
    PEDIDO_NOVO = "pedido.novo"
    PEDIDO_DIRECIONADO = "pedido.direcionado"
    PEDIDO_URGENTE = "pedido.urgente"
    ORCAMENTO_ACEITO = "orcamento.aceito"
    ORCAMENTO_RECUSADO = "orcamento.recusado"
    ORCAMENTO_NAO_ESCOLHIDO = "orcamento.nao_escolhido"
    PAGAMENTO_CONFIRMADO = "pagamento.confirmado"
    LEMBRETE_AGENDAMENTO = "agenda.lembrete"
    CODIGO_INICIO = "agenda.codigo_inicio"
    CHECK_IN_SEM_CODIGO = "agenda.check_in_sem_codigo"
    CLIENTE_AUSENTE = "agenda.cliente_ausente"
    A_CAMINHO = "agenda.a_caminho"
    REAGENDAMENTO_PROPOSTO = "agenda.reagendamento_proposto"
    INDICACAO_LIBERADA = "indicacao.liberada"
    RECORRENCIA_ATUALIZADA = "recorrencia.atualizada"
    RECORRENCIA_VISITA = "recorrencia.visita"
    REAGENDAMENTO_RESPONDIDO = "agenda.reagendamento_respondido"
    CONCLUSAO_PARA_CONFIRMAR = "execucao.confirmar_conclusao"
    SERVICO_INICIADO = "execucao.iniciado"
    CODIGO_CONCLUSAO = "execucao.codigo_conclusao"
    CLIENTE_CONFIRMOU = "execucao.cliente_confirmou"
    ADITIVO_APROVADO = "execucao.aditivo_aprovado"
    ADITIVO_PAGO = "execucao.aditivo_pago"
    NOTA_MATERIAL = "execucao.nota_material"
    RETRABALHO_RESOLVIDO = "garantia.retrabalho_resolvido"
    ADITIVO_PENDENTE = "execucao.aditivo_pendente"
    DISPUTA_ABERTA = "disputa.aberta"
    DISPUTA_RESPONDIDA = "disputa.respondida"
    DISPUTA_DECIDIDA = "disputa.decidida"
    LEMBRETE_RESPOSTA_DISPUTA = "disputa.lembrete_resposta"
    RETRABALHO = "garantia.retrabalho"
    AVALIACAO = "avaliacao.recebida"
    MENSAGEM_NOVA = "mensagem.nova"
    EXCLUSIVIDADE_OFERTA = "exclusividade.oferta"
    EXCLUSIVIDADE_ACEITA = "exclusividade.aceita"
    EXCLUSIVIDADE_RECUSADA = "exclusividade.recusada"
    EXCLUSIVIDADE_EXPIRADA_SEM_RESPOSTA = "exclusividade.expirada_sem_resposta"
    EXCLUSIVIDADE_EXPIRADA_48H_PROFISSIONAL = "exclusividade.expirada_sem_atendimento"
    EXCLUSIVIDADE_EXPIRADA_48H_CLIENTE = "exclusividade.pedido_reaberto"
    EXCLUSIVIDADE_CANCELADA = "exclusividade.cancelada"


@dataclass(frozen=True)
class ModeloEvento:
    categoria: Categoria
    titulo: str
    corpo: str
    tela: str  # tela do app: vira o deep link
    essencial: bool = False  # sempre aparece na caixa de entrada, mesmo com a categoria desligada
    somente_app: bool = False  # só a lista do app: sem push nem e-mail


MODELOS: dict[Evento, ModeloEvento] = {
    Evento.ORCAMENTO_RECEBIDO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Novo orçamento",
        "Você recebeu um orçamento para o seu pedido.",
        "orcamentos",
    ),
    Evento.PEDIDO_NOVO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Novo pedido perto de você",
        "Há um novo pedido aberto na sua região.",
        "pedido_aberto",
    ),
    Evento.PEDIDO_DIRECIONADO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Pedido de orçamento direto para você",
        "Um cliente pediu um orçamento diretamente para você.",
        "pedido_aberto",
    ),
    Evento.PEDIDO_URGENTE: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Pedido urgente disponível",
        "Um cliente precisa de atendimento rápido. Veja se pode atender agora.",
        "pedido_aberto",
        essencial=True,
    ),
    Evento.ORCAMENTO_ACEITO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Orçamento aceito",
        "O cliente aceitou o seu orçamento.",
        "pedido",
        essencial=True,
    ),
    Evento.ORCAMENTO_RECUSADO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Orçamento recusado",
        "O cliente recusou o seu orçamento.",
        "pedido_aberto",
    ),
    # Quando o cliente aceita OUTRO orçamento do pedido. Sem nome do cliente nem do vencedor, sem
    # valores e sem promessa. Mesma categoria, preferência e destino do ORCAMENTO_RECUSADO.
    Evento.ORCAMENTO_NAO_ESCOLHIDO: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Cliente escolheu outro orçamento",
        "Desta vez não foi o seu orçamento. Veja outros pedidos abertos.",
        "pedido_aberto",
    ),
    Evento.PAGAMENTO_CONFIRMADO: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Pagamento confirmado",
        "Pagamento confirmado. Combine o início com o profissional.",
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
    Evento.CHECK_IN_SEM_CODIGO: ModeloEvento(
        Categoria.AGENDA,
        "Serviço iniciado sem código",
        "O profissional iniciou o serviço sem o código e registrou foto, localização e "
        "justificativa.",
        "pedido",
        essencial=True,
    ),
    Evento.RECORRENCIA_ATUALIZADA: ModeloEvento(
        Categoria.AGENDA,
        "Serviço recorrente",
        "Há uma novidade no seu serviço recorrente. Veja no app.",
        "recorrencias",
    ),
    Evento.RECORRENCIA_VISITA: ModeloEvento(
        Categoria.AGENDA,
        "Próxima visita do serviço recorrente",
        "Sua próxima visita está chegando. Aprove o orçamento e pague para confirmar.",
        "pedido",
        essencial=True,
    ),
    Evento.INDICACAO_LIBERADA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Tratinhos de indicação liberados",
        "Seus Tratinhos da indicação já estão na carteira.",
        "indique-e-ganhe",
    ),
    Evento.REAGENDAMENTO_PROPOSTO: ModeloEvento(
        Categoria.AGENDA,
        "Pedido de reagendamento",
        "A outra parte propôs um novo horário para o serviço. Responda no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.REAGENDAMENTO_RESPONDIDO: ModeloEvento(
        Categoria.AGENDA,
        "Reagendamento respondido",
        "O pedido de reagendamento recebeu uma resposta. Veja o pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.A_CAMINHO: ModeloEvento(
        Categoria.AGENDA,
        "Seu profissional está a caminho",
        "Seu profissional avisou que está a caminho.",
        "pedido",
        essencial=True,
    ),
    Evento.CLIENTE_AUSENTE: ModeloEvento(
        Categoria.AGENDA,
        "Profissional no local",
        "O profissional registrou chegada no endereço e aguarda seu retorno.",
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
    Evento.SERVICO_INICIADO: ModeloEvento(
        Categoria.EXECUCAO,
        "Serviço iniciado",
        "O profissional começou o serviço.",
        "pedido",
        essencial=True,
        somente_app=True,
    ),
    Evento.CODIGO_CONCLUSAO: ModeloEvento(
        Categoria.EXECUCAO,
        "Código de conclusão disponível",
        "Passe este código ao profissional quando o serviço estiver pronto. "
        "Não envie por mensagem.",
        "pedido",
        essencial=True,
        somente_app=True,
    ),
    Evento.CLIENTE_CONFIRMOU: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Serviço confirmado pelo cliente",
        "O cliente confirmou o serviço.",
        "pedido",
        essencial=True,
        somente_app=True,
    ),
    Evento.ADITIVO_APROVADO: ModeloEvento(
        Categoria.EXECUCAO,
        "Aditivo aprovado",
        "O cliente aprovou o aditivo do serviço.",
        "pedido",
        essencial=True,
        somente_app=True,
    ),
    Evento.ADITIVO_PAGO: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Aditivo pago",
        "O cliente pagou o aditivo. O valor fica retido até o cliente confirmar o serviço.",
        "pedido",
        essencial=True,
        somente_app=True,
    ),
    Evento.NOTA_MATERIAL: ModeloEvento(
        Categoria.EXECUCAO,
        "Nota de material enviada",
        "O profissional enviou uma nota de material. Veja os itens e o valor.",
        "pedido",
        essencial=True,
        somente_app=True,
    ),
    Evento.RETRABALHO_RESOLVIDO: ModeloEvento(
        Categoria.DISPUTAS,
        "Retrabalho resolvido",
        "O profissional informou que resolveu o problema. Confirme se está tudo certo.",
        "pedido",
        essencial=True,
        somente_app=True,
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
    # O texto da mensagem NUNCA vai na notificação (pode ter dado pessoal): só o aviso.
    Evento.MENSAGEM_NOVA: ModeloEvento(
        Categoria.MENSAGENS,
        "Nova mensagem",
        "Você recebeu uma mensagem. Abra a conversa para ler.",
        "mensagens",
        essencial=True,
    ),
    Evento.EXCLUSIVIDADE_OFERTA: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Pedido de prioridade no seu serviço",
        "Um profissional quer fazer seu serviço com prioridade. Sem compromisso.",
        "pedido",
        essencial=True,
    ),
    Evento.EXCLUSIVIDADE_ACEITA: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Prioridade aceita",
        "O cliente aceitou a prioridade que você ganhou avaliando. "
        "Você tem 48h para enviar seu orçamento.",
        "pedido_aberto",
        essencial=True,
    ),
    Evento.EXCLUSIVIDADE_RECUSADA: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Prioridade recusada",
        "O cliente preferiu ver outros orçamentos. Seus 100 Tratinhos voltaram.",
        "pedido",
        essencial=True,
    ),
    Evento.EXCLUSIVIDADE_EXPIRADA_SEM_RESPOSTA: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Oferta de prioridade expirada",
        "O prazo de resposta acabou e a prioridade que você ganhou avaliando expirou. "
        "Seus 100 Tratinhos voltaram.",
        "pedido",
        essencial=True,
    ),
    Evento.EXCLUSIVIDADE_EXPIRADA_48H_PROFISSIONAL: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Prioridade de 48h encerrada",
        "As 48h da prioridade que você ganhou avaliando terminaram sem envio de orçamento.",
        "pedido",
        essencial=True,
    ),
    Evento.EXCLUSIVIDADE_EXPIRADA_48H_CLIENTE: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Pedido aberto para outros profissionais",
        "Seu pedido voltou a receber orçamentos de outros profissionais.",
        "pedido",
        essencial=True,
    ),
    Evento.EXCLUSIVIDADE_CANCELADA: ModeloEvento(
        Categoria.ORCAMENTOS,
        "Prioridade cancelada",
        "O pedido mudou antes do fim da prioridade que você ganhou avaliando. "
        "Seus 100 Tratinhos voltaram.",
        "pedido",
        essencial=True,
    ),
}


def deep_link(base: str, tela: str, pedido_id: str | None) -> str:
    return f"{base}{tela}/{pedido_id}" if pedido_id else f"{base}{tela}"
