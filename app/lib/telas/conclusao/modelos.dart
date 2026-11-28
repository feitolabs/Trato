/// Modelos simples das telas 18 a 21 do protótipo
/// (Conclusão, Avaliação, Relatar problema, Garantia).
///
/// Nada aqui é regra. Prazos, textos de prazo e valores vêm do backend
/// (pacotes `garantias/` e `disputas/`, tabela de configuração). O app só mostra.
/// Valores em centavos inteiros.
library;

/// Tela 18: Conclusão com código.
class ResumoConclusao {
  const ResumoConclusao({
    required this.numeroPedido,
    required this.nomeProfissional,
    required this.legendaFotoAntes,
    required this.legendaFotoDepois,
    required this.orcamentoCentavos,
    required this.aditivoCentavos,
    required this.codigo,
    required this.avisoLiberacao,
    this.fotoAntes,
    this.fotoDepois,
    this.fotosCarregadas = false,
    this.checkOutSemCodigo = false,
    this.prazoConfirmacao,
    this.garantiaTexto,
    this.remoto = false,
    this.podeConfirmar = true,
    this.podeRelatarProblema = true,
    this.concluido = false,
  });

  /// A API permite `confirmar_conclusao`. Falso = a tela é só consulta (fotos e valores).
  final bool podeConfirmar;

  /// A API permite `abrir_disputa`.
  final bool podeRelatarProblema;

  /// O pedido está no estado `concluido` (só muda o título da consulta).
  final bool concluido;

  /// Serviço remoto: texto do código muda (não há chegada).
  final bool remoto;

  /// "Você tem 48 horas para confirmar, até 23/11 · 14:30." Nulo se o backend não deu a data.
  final String? prazoConfirmacao;

  /// "Garantia de 90 dias a partir da sua confirmação." Nulo se o backend não deu os dias.
  final String? garantiaTexto;

  /// Verdadeiro quando o profissional encerrou sem código de conclusão.
  final bool checkOutSemCodigo;

  final String numeroPedido;
  final String nomeProfissional;

  /// URL assinada da foto de chegada e da foto final que o profissional enviou (da API).
  final String? fotoAntes;
  final String? fotoDepois;

  /// Verdadeiro quando as fotos vieram da API: sem foto, a tela diz "Sem foto" em vez do
  /// marcador "[Foto antes]" do protótipo.
  final bool fotosCarregadas;

  /// Ex.: "Antes · 14h08".
  final String legendaFotoAntes;
  final String legendaFotoDepois;
  final int orcamentoCentavos;
  final int aditivoCentavos;

  /// Código de 4 dígitos que o cliente passa ao profissional.
  final String codigo;

  /// Texto do prazo de liberação automática e da garantia. VEM DE FORA: o protótipo diz
  /// "48 horas" e a decisão D6 diz 7 dias (dúvida P1 em harness/PENDENCIAS.md).
  final String avisoLiberacao;

  int get totalRetidoCentavos => orcamentoCentavos + aditivoCentavos;
}

/// Tela 19: Avaliação.
class DadosAvaliacao {
  const DadosAvaliacao({
    required this.nomeProfissional,
    required this.valorLiberadoCentavos,
    required this.criterios,
    required this.gorjetasCentavos,
    this.gorjetaDisponivel = true,
    this.profissionalId,
    this.bonusDisponivel = false,
    this.bonusMoedas = 0,
    this.bonusValidadeDias,
    this.valorMoedaCentavos,
    this.jaAvaliou = false,
    this.avaliarAte,
    this.prazoEncerrado = false,
  });

  /// Termos 12.1: até quando dá para avaliar e se o prazo já terminou (do servidor).
  final DateTime? avaliarAte;
  final bool prazoEncerrado;

  /// Verdadeiro quando o cliente já enviou avaliação para este pedido (ex.: após retrabalho).
  final bool jaAvaliou;

  /// O backend informa se avaliar este pedido rende Tratinhos de bônus.
  final bool bonusDisponivel;

  /// Quantidade de Tratinhos do bônus quando [bonusDisponivel] for verdadeiro.
  final int bonusMoedas;

  /// Termos 13.3: validade em dias do bônus após o crédito. Nulo = servidor não informou.
  final int? bonusValidadeDias;

  /// Valor de 1 Tratinho em centavos (opcional; padrão 1 centavo quando ausente).
  final int? valorMoedaCentavos;

  /// Id do profissional avaliado (para "Salvar como de confiança"); nulo = sem o botão.
  final String? profissionalId;

  /// Falso enquanto o servidor não recebe gorjeta: a seção some da tela.
  final bool gorjetaDisponivel;

  final String nomeProfissional;

  /// O que o cliente pagou pelo serviço (o selo da tela diz "pago").
  final int valorLiberadoCentavos;

  /// Critérios do cliente (modelo de dados 8.4).
  final List<String> criterios;

  /// Valores sugeridos de gorjeta, além de "Não" e "Outro".
  final List<int> gorjetasCentavos;
}

/// Resultado da avaliação entregue a quem chama a tela.
class EnvioAvaliacao {
  const EnvioAvaliacao({
    required this.notas,
    required this.comentario,
    required this.gorjetaCentavos,
    this.etiquetas = const [],
  });

  /// Elogios escolhidos ("O que foi bom?"), no máximo 3; vazio = nenhum.
  final List<String> etiquetas;

  /// Nota (0 a 5) por critério, na ordem de [DadosAvaliacao.criterios].
  final List<int> notas;
  final String comentario;
  final int gorjetaCentavos;
}

/// Tela 20: Relatar problema.
class DadosRelatoProblema {
  const DadosRelatoProblema({
    required this.titulo,
    required this.valorCongeladoCentavos,
    required this.motivos,
    required this.solucoes,
    required this.prazoRespostaHoras,
    required this.nomeProfissional,
    this.casoEmAnalise = false,
  });

  /// Há um caso aberto de verdade neste pedido (estado `em_disputa`).
  final bool casoEmAnalise;

  /// Ex.: "Vazamento na pia · Joana Ribeiro".
  final String titulo;
  final int valorCongeladoCentavos;
  final List<String> motivos;

  /// Opções de "O que resolveria para você?".
  final List<String> solucoes;

  /// Prazo para o profissional responder (Termos 8.2: 24 h). Vem do backend.
  final int prazoRespostaHoras;
  final String nomeProfissional;
}

class EnvioRelato {
  const EnvioRelato({
    required this.motivo,
    required this.descricao,
    required this.solucao,
    this.fotos = const [],
  });

  final String motivo;
  final String descricao;
  final String solucao;

  /// Fotos tiradas no aparelho (caminhos); o repositório sobe e manda os ids.
  final List<String> fotos;
}

/// Tela 21: Garantia do serviço.
class DadosGarantia {
  const DadosGarantia({
    required this.titulo,
    required this.diasTotal,
    required this.diasRestantes,
    required this.fimEm,
    required this.cobre,
    required this.naoCobre,
    required this.prazoAtendimentoDias,
    this.fotoAntes,
    this.fotoDepois,
  });

  /// Fotos do serviço (check-in e check-out), por URL assinada. Nulo = sem foto.
  final String? fotoAntes;
  final String? fotoDepois;

  final String titulo;

  /// Dias da garantia (da categoria ou padrão). O backend calcula; o app só mostra.
  final int diasTotal;
  final int diasRestantes;
  final DateTime fimEm;
  final String cobre;
  final String naoCobre;
  final int prazoAtendimentoDias;

  bool get ativa => diasRestantes > 0;

  /// Parte já consumida da garantia, de 0 a 1 (preenchimento da barra).
  double get progresso =>
      diasTotal <= 0 ? 1 : ((diasTotal - diasRestantes) / diasTotal).clamp(0, 1);
}

// ---------------------------------------------------------------------------
// Dados de exemplo (PROVISÓRIOS, copiados do protótipo)
// ---------------------------------------------------------------------------
