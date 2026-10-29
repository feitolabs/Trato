/// Modelos simples e dados de exemplo das telas 18 a 21 do protótipo
/// (Conclusão, Avaliação, Relatar problema, Garantia).
///
/// PROVISÓRIO: nada aqui é regra. Prazos, textos de prazo e valores vêm do backend
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
  });

  final String numeroPedido;
  final String nomeProfissional;

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
  });

  final String nomeProfissional;
  final int valorLiberadoCentavos;

  /// Critérios do cliente (modelo de dados 8.4).
  final List<String> criterios;

  /// Valores sugeridos de gorjeta, além de "Não" e "Outro".
  final List<int> gorjetasCentavos;
}

/// Resultado da avaliação entregue a quem chama a tela.
class EnvioAvaliacao {
  const EnvioAvaliacao({required this.notas, required this.comentario, required this.gorjetaCentavos});

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
  });

  /// Ex.: "Vazamento na pia · Joana Ribeiro".
  final String titulo;
  final int valorCongeladoCentavos;
  final List<String> motivos;

  /// Opções de "O que resolveria para você?".
  final List<String> solucoes;

  /// Prazo para o profissional responder (escopo: 48 h). Vem do backend.
  final int prazoRespostaHoras;
  final String nomeProfissional;
}

class EnvioRelato {
  const EnvioRelato({required this.motivo, required this.descricao, required this.solucao});

  final String motivo;
  final String descricao;
  final String solucao;
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
  });

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
  double get progresso => diasTotal <= 0 ? 1 : ((diasTotal - diasRestantes) / diasTotal).clamp(0, 1);
}

// ---------------------------------------------------------------------------
// Dados de exemplo (PROVISÓRIOS, copiados do protótipo)
// ---------------------------------------------------------------------------

const resumoConclusaoExemplo = ResumoConclusao(
  numeroPedido: '#4821',
  nomeProfissional: 'Carlos',
  legendaFotoAntes: 'Antes · 14h08',
  legendaFotoDepois: 'Depois · 16h52',
  orcamentoCentavos: 38000,
  aditivoCentavos: 4500,
  codigo: '7305',
  avisoLiberacao:
      'Liberação automática em 48 horas, salvo disputa aberta. '
      'Ao confirmar, a garantia de 90 dias começa a contar.',
);

const dadosAvaliacaoExemplo = DadosAvaliacao(
  nomeProfissional: 'Carlos',
  valorLiberadoCentavos: 42500,
  criterios: ['Pontualidade', 'Qualidade', 'Limpeza', 'Comunicação', 'Preço justo'],
  gorjetasCentavos: [1000, 2000],
);

const dadosRelatoExemplo = DadosRelatoProblema(
  titulo: 'Vazamento na pia · Joana Ribeiro',
  valorCongeladoCentavos: 22000,
  motivos: [
    'O problema voltou ou não foi resolvido',
    'Qualidade abaixo do combinado',
    'Cobrança extra não combinada',
    'Dano no local',
    'Outro motivo',
  ],
  solucoes: ['Retrabalho sem custo', 'Reembolso parcial', 'Reembolso total'],
  prazoRespostaHoras: 48,
  nomeProfissional: 'A profissional',
);

final dadosGarantiaExemplo = DadosGarantia(
  titulo: 'Pintura da sala · Rafael Souza',
  diasTotal: 90,
  diasRestantes: 64,
  fimEm: DateTime(2026, 12, 31),
  cobre: 'Refazer o que está no orçamento: descascado, manchas, falhas',
  naoCobre: 'Não cobre: infiltração na parede e serviços fora do escopo',
  prazoAtendimentoDias: 7,
);
