// Modelos da tela de pagamento. O app só exibe o que vier daqui:
// quanto pagar agora, em que condição e a taxa são decididos pelo backend.

enum MetodoPagamento { pix, cartao }

class OpcaoPagamento {
  const OpcaoPagamento({required this.metodo, required this.titulo, required this.descricao});

  final MetodoPagamento metodo;
  final String titulo;
  final String descricao;
}

class DadosPagamento {
  const DadosPagamento({
    required this.subtitulo,
    required this.valorAgoraCentavos,
    required this.opcoes,
    this.rotuloValor,
  });

  /// "Carlos Mendes · Troca de tomadas e chuveiro".
  final String subtitulo;

  /// Valor a pagar agora, em centavos (int). Vem pronto do backend.
  final int valorAgoraCentavos;

  /// Texto opcional sob o valor, ex.: "Adiantamento de 30%". Null = não mostra.
  final String? rotuloValor;
  final List<OpcaoPagamento> opcoes;
}
