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


# Termos 15.2: avisos de disputa e de pagamento/estorno não podem ser desligados.
CATEGORIAS_OBRIGATORIAS = frozenset({Categoria.DISPUTAS, Categoria.PAGAMENTOS})


class Evento(StrEnum):
    ORCAMENTO_RECEBIDO = "orcamento.recebido"
    PEDIDO_NOVO = "pedido.novo"
    PEDIDO_DIRECIONADO = "pedido.direcionado"
    PEDIDO_URGENTE = "pedido.urgente"
    ORCAMENTO_ACEITO = "orcamento.aceito"
    ORCAMENTO_RECUSADO = "orcamento.recusado"
    ORCAMENTO_NAO_ESCOLHIDO = "orcamento.nao_escolhido"
    PAGAMENTO_CONFIRMADO = "pagamento.confirmado"
    ESTORNO_SOLICITADO = "pagamento.estorno"
    DESISTENCIA_RECEBIDA = "pagamento.desistencia"
    PROFISSIONAL_CHEGOU = "agenda.profissional_chegou"
    SAC_ABERTO = "suporte.chamado_aberto"
    COMPENSACAO_REGISTRADA = "pagamento.compensacao_registrada"
    COMPENSACAO_CANCELADA = "pagamento.compensacao_cancelada"
    COMPENSACAO_REDUZIDA = "pagamento.compensacao_reduzida"
    INCIDENTE_CAUTELA_ATRASADA = "seguranca.cautela_atrasada"  # 9.6, para a equipe
    AVISO_MUDANCA_TERMOS = "conta.mudanca_termos"  # 23.2
    TERMOS_ACEITOS = "conta.termos_aceitos"  # 1.5: cópia dos Termos por e-mail
    AVISO_MUDANCA_TRATINHOS = "conta.mudanca_tratinhos"  # 13.11 e I.12
    AVISO_INATIVACAO = "conta.inativacao_prevista"  # 4.9
    INCIDENTE_SINAL_FRAUDE = "seguranca.sinal_antifraude"  # 9.5, para a equipe
    PEDIDO_CANCELADO_SEGURANCA = "pagamento.cancelado_seguranca"  # 9.5
    PEDIDO_CANCELADO_CONTA = "pagamento.cancelado_medida_conta"  # 20.6
    CHECKOUT_SEM_CODIGO = "pagamento.checkout_sem_codigo"  # 5.7
    SERIE_PAUSADA_CONTA = "pagamento.serie_pausada_medida_conta"  # 20.6
    SELO_RETIRADO = "conta.selo_retirado"  # 10.3
    SELO_RECONFERENCIA = "conta.selo_reconferencia"
    SELO_REGULARIZADO = "conta.selo_regularizado"
    MEDIDA_APLICADA = "conta.medida_aplicada"
    MEDIDA_ENCERRADA = "conta.medida_encerrada"
    SAC_RESPOSTA = "suporte.chamado_resposta"
    SAC_PRAZO = "suporte.chamado_prazo"
    EXCLUSIVIDADE_CLIENTE_NOVA = "exclusividade.cliente_reservou"
    EXCLUSIVIDADE_CLIENTE_FIM = "exclusividade.cliente_fim"
    EXCLUSIVIDADE_CLIENTE_DEVOLVIDA = "exclusividade.cliente_devolvida"
    AUSENCIA_JUSTIFICAR = "pagamento.ausencia_justificar"
    AUSENCIA_DECIDIDA = "pagamento.ausencia_decidida"
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
    DISPUTA_PEDIDO_INFORMACAO = "disputa.pedido_informacao"
    DISPUTA_CONTESTADA = "disputa.contestada"
    DISPUTA_CONTESTACAO_DECIDIDA = "disputa.contestacao_decidida"
    LEMBRETE_RESPOSTA_DISPUTA = "disputa.lembrete_resposta"
    RETRABALHO = "garantia.retrabalho"
    AVALIACAO = "avaliacao.recebida"
    AVALIACAO_OCULTADA = "conta.avaliacao_ocultada"  # 11.8, para o autor
    JANELA_ENCERRADA = "execucao.janela_encerrada"  # 15.3, conclusão por prazo
    TRATINHOS_VENCENDO = "pagamento.tratinhos_vencendo"  # 13.4 e I.5
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
    email_obrigatorio: bool = False  # os Termos pedem e-mail: a preferência não desliga


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
    Evento.EXCLUSIVIDADE_CLIENTE_NOVA: ModeloEvento(
        Categoria.AGENDA,
        "Pedido reservado para você",
        "Um cliente reservou este pedido para você por tempo limitado. Veja no aplicativo.",
        "pedido",
    ),
    Evento.EXCLUSIVIDADE_CLIENTE_FIM: ModeloEvento(
        Categoria.AGENDA,
        "Exclusividade encerrada",
        "O prazo terminou sem contratação. O pedido voltou a receber orçamentos.",
        "pedido",
    ),
    Evento.EXCLUSIVIDADE_CLIENTE_DEVOLVIDA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Tratinhos devolvidos",
        "A exclusividade foi encerrada e os seus Tratinhos voltaram ao saldo.",
        "pedido",
        essencial=True,
    ),
    # Atendimento: categoria que não se desliga (protocolo e prazo por escrito, 25.3).
    # Medidas de conta (20.4): o aviso sai sempre, por app e e-mail.
    Evento.DISPUTA_CONTESTADA: ModeloEvento(
        Categoria.DISPUTAS,
        "Decisão contestada",
        "A decisão da reclamação foi contestada. Outra pessoa vai analisar. Veja no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.DISPUTA_CONTESTACAO_DECIDIDA: ModeloEvento(
        Categoria.DISPUTAS,
        "Contestação analisada",
        "A contestação da decisão foi analisada. Veja a resposta no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.SELO_RETIRADO: ModeloEvento(
        Categoria.DISPUTAS,
        "Selo de verificação retirado",
        "O seu selo foi retirado até a regularização. Veja o motivo e como contestar.",
        "perfil",
        essencial=True,
    ),
    Evento.SELO_RECONFERENCIA: ModeloEvento(
        Categoria.DISPUTAS,
        "Nova conferência de identidade",
        "O Trato pediu uma nova conferência da sua identidade.",
        "perfil",
        essencial=True,
    ),
    Evento.SELO_REGULARIZADO: ModeloEvento(
        Categoria.DISPUTAS,
        "Selo regularizado",
        "O seu selo de verificação foi regularizado.",
        "perfil",
        essencial=True,
    ),
    Evento.MEDIDA_APLICADA: ModeloEvento(
        Categoria.DISPUTAS,
        "Medida na sua conta",
        "Uma medida foi aplicada à sua conta. Veja o motivo e como contestar.",
        "medidas",
        essencial=True,
    ),
    Evento.MEDIDA_ENCERRADA: ModeloEvento(
        Categoria.DISPUTAS,
        "Atualização da medida",
        "Uma medida da sua conta mudou. Veja no aplicativo.",
        "medidas",
        essencial=True,
    ),
    Evento.TERMOS_ACEITOS: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Cópia dos Termos de Uso aceitos",
        "Seu aceite dos Termos de Uso do Trato foi registrado.",
        "termos",
        essencial=True,
        email_obrigatorio=True,
    ),
    Evento.AVALIACAO_OCULTADA: ModeloEvento(
        Categoria.DISPUTAS,
        "Sua avaliação foi ocultada",
        "Uma avaliação que você escreveu foi ocultada. Veja o motivo e como contestar.",
        "pedido",
        essencial=True,
        email_obrigatorio=True,
    ),
    Evento.JANELA_ENCERRADA: ModeloEvento(
        Categoria.EXECUCAO,
        "Prazo de confirmação encerrado",
        "O prazo de confirmação terminou e o serviço foi concluído. Veja no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.TRATINHOS_VENCENDO: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Tratinhos perto de vencer",
        "Você tem Tratinhos perto de vencer. Veja o saldo no aplicativo.",
        "notificacoes",
        essencial=True,
    ),
    Evento.COMPENSACAO_REGISTRADA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Desconto em repasses futuros",
        "Um reembolso decidido será descontado dos próximos repasses. Veja o motivo.",
        "pedido",
        essencial=True,
    ),
    Evento.COMPENSACAO_REDUZIDA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Compensação reduzida",
        "O valor a descontar diminuiu. Veja no aplicativo.",
        "pedido",
        essencial=True,
    ),
    Evento.COMPENSACAO_CANCELADA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Compensação cancelada",
        "O desconto foi cancelado. Veja no aplicativo.",
        "pedido",
        essencial=True,
    ),
    Evento.SAC_ABERTO: ModeloEvento(
        Categoria.DISPUTAS,
        "Recebemos o seu contato",
        "O seu chamado foi aberto. Veja o protocolo no aplicativo.",
        "suporte",
        essencial=True,
    ),
    Evento.SAC_RESPOSTA: ModeloEvento(
        Categoria.DISPUTAS,
        "Resposta do atendimento",
        "Há novidade no seu chamado.",
        "suporte",
        essencial=True,
    ),
    Evento.SAC_PRAZO: ModeloEvento(
        Categoria.DISPUTAS,
        "Novo prazo do atendimento",
        "O prazo do seu chamado mudou. Veja o motivo no aplicativo.",
        "suporte",
        essencial=True,
    ),
    Evento.PROFISSIONAL_CHEGOU: ModeloEvento(
        Categoria.AGENDA,
        "O profissional chegou",
        "O profissional está no local. Responda pelo chat do pedido.",
        "pedido",
    ),
    Evento.AUSENCIA_JUSTIFICAR: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Justifique a ausência",
        "Foi registrado que você não estava no local. Justifique no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.PEDIDO_CANCELADO_SEGURANCA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Pedido cancelado por segurança",
        "O pedido foi cancelado por um relato de segurança. Veja no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.CHECKOUT_SEM_CODIGO: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Confirme o serviço ou relate um problema",
        "O profissional encerrou o serviço sem o seu Código Final. Confirme ou relate um "
        "problema no pedido.",
        "pedido",
        essencial=True,
        email_obrigatorio=True,
    ),
    Evento.PEDIDO_CANCELADO_CONTA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Pedido cancelado",
        "O pedido foi cancelado porque a conta da outra parte foi suspensa ou encerrada.",
        "pedido",
        essencial=True,
    ),
    Evento.SERIE_PAUSADA_CONTA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Serviço recorrente pausado",
        "O serviço recorrente foi pausado porque a conta da outra parte foi suspensa ou "
        "encerrada.",
        "pedido",
        essencial=True,
    ),
    Evento.INCIDENTE_SINAL_FRAUDE: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Relato de segurança com sinal",
        "Um relato de segurança tem sinal para conferir no painel.",
        "pedido",
        essencial=True,
    ),
    Evento.INCIDENTE_CAUTELA_ATRASADA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Incidente sem cautela no prazo",
        "Um incidente passou do prazo de 24 horas sem cautela adotada.",
        "pedido",
        essencial=True,
    ),
    Evento.AVISO_MUDANCA_TERMOS: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Os Termos de uso vão mudar",
        "Veja o que muda nos Termos de uso.",
        "notificacoes",
        essencial=True,
        email_obrigatorio=True,
    ),
    Evento.AVISO_MUDANCA_TRATINHOS: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Mudança nos Tratinhos",
        "Veja o que muda no programa.",
        "notificacoes",
        essencial=True,
        email_obrigatorio=True,  # 13.11 pede o app; 15.2 (aviso que afeta direitos) pede e-mail
    ),
    Evento.AVISO_INATIVACAO: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Sua conta está sem uso",
        "Veja o aviso sobre a sua conta.",
        "notificacoes",
        essencial=True,
        email_obrigatorio=True,
    ),
    Evento.AUSENCIA_DECIDIDA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Ausência analisada",
        "O registro de cliente ausente foi analisado. Veja no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.DESISTENCIA_RECEBIDA: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Desistência recebida",
        "A desistência deste pedido foi recebida. Veja a situação no pedido.",
        "pedido",
        essencial=True,
    ),
    Evento.ESTORNO_SOLICITADO: ModeloEvento(
        Categoria.PAGAMENTOS,
        "Estorno solicitado",
        "Pedimos ao parceiro de pagamento o estorno deste pedido.",
        "pedido",
        essencial=True,
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
    Evento.DISPUTA_PEDIDO_INFORMACAO: ModeloEvento(
        Categoria.DISPUTAS,
        "Pedido de informação na disputa",
        "A equipe do Trato pediu informações adicionais na disputa do seu pedido.",
        "disputa",
        essencial=True,
        email_obrigatorio=True,
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
