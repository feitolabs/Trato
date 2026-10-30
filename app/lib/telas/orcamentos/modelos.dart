// Modelos de orçamento. Provisórios. Valores em centavos inteiros; o app só exibe o que vier
// dos dados (total, itens, valores de cancelamento): nenhuma conta de dinheiro roda aqui.

class ItemOrcamento {
  const ItemOrcamento({required this.descricao, required this.centavos});

  final String descricao;
  final int centavos;
}

/// Os quatro blocos de regras do detalhe: agenda, garantia, fora do escopo e cancelamento.
class DetalheOrcamento {
  const DetalheOrcamento({
    required this.validoAte,
    required this.itens,
    required this.notaMaterial,
    required this.agendaTitulo,
    required this.agendaDetalhe,
    required this.garantiaTitulo,
    required this.garantiaDetalhe,
    required this.foraDoEscopo,
    required this.cancelamento,
  });

  /// Ex.: "31/10" (a barra mostra "Válido até 31/10").
  final String validoAte;
  final List<ItemOrcamento> itens;
  final String notaMaterial;
  final String agendaTitulo;
  final String agendaDetalhe;
  final String garantiaTitulo;
  final String garantiaDetalhe;
  final String foraDoEscopo;
  final String cancelamento;
}

enum Ordenacao {
  menorValor('Menor valor'),
  maiorNota('Maior nota'),
  maisCedo('Mais cedo');

  const Ordenacao(this.rotulo);

  final String rotulo;
}

class Orcamento {
  const Orcamento({
    required this.id,
    required this.profissional,
    required this.iniciais,
    required this.verificacao,
    required this.totalCentavos,
    required this.nota,
    required this.notaResumo,
    required this.servicosResumo,
    required this.servicosConcluidos,
    required this.quando,
    required this.inicio,
    required this.garantia,
    required this.observacao,
    this.detalhe,
  });

  final String id;
  final String profissional;
  final String iniciais;
  final String verificacao;
  final int totalCentavos;

  /// Para ordenar por "Maior nota".
  final double nota;

  /// Textos prontos do cartão (vêm formatados do backend): "4,7 · 22 avaliações".
  final String notaResumo;
  final String servicosResumo;
  final int servicosConcluidos;

  /// "Sáb, 31/10 · 4 h".
  final String quando;

  /// Para ordenar por "Mais cedo".
  final DateTime inicio;
  final String garantia;
  final String observacao;

  /// Ausente quando o protótipo não traz a tela de detalhe desse orçamento.
  final DetalheOrcamento? detalhe;

  String get primeiroNome => profissional.split(' ').first;
}

/// Pedido ao qual os orçamentos pertencem (cabeçalho da lista).
class ResumoPedido {
  const ResumoPedido({
    required this.numero,
    required this.titulo,
    required this.recebidos,
    required this.limite,
    required this.tempoRestante,
  });

  final String numero;
  final String titulo;
  final int recebidos;
  final int limite;

  /// "31 horas".
  final String tempoRestante;
}
