// Modelos da tela de pagamento. O app só exibe o que vier daqui:
// quanto pagar agora, em que condição e a taxa são decididos pelo backend.

enum MetodoPagamento { pix, cartao }

class OpcaoPagamento {
  const OpcaoPagamento({required this.metodo, required this.titulo, required this.descricao});

  final MetodoPagamento metodo;
  final String titulo;
  final String descricao;
}

/// Cartão parcelado: o total por número de parcelas (custo do provedor repassado ao cliente).
/// Vem pronto do backend; lista vazia = parcelado desligado.
class OpcaoParcelamento {
  const OpcaoParcelamento({
    required this.parcelas,
    required this.custoCentavos,
    required this.totalCentavos,
    required this.valorParcelaCentavos,
  });

  final int parcelas;
  final int custoCentavos;
  final int totalCentavos;
  final int valorParcelaCentavos;
}

class DadosPagamento {
  const DadosPagamento({
    required this.subtitulo,
    required this.valorAgoraCentavos,
    required this.opcoes,
    this.rotuloValor,
    this.servicoCentavos,
    this.taxaCentavos,
    this.parcelamento = const [],
  });

  /// Valor do serviço e taxa do Trato (somada), para mostrar a conta antes de pagar. Null = não mostra.
  final int? servicoCentavos;
  final int? taxaCentavos;

  /// Total por número de parcelas no cartão. Vazio enquanto o parcelado estiver desligado.
  final List<OpcaoParcelamento> parcelamento;

  /// "Carlos Mendes · Troca de tomadas e chuveiro".
  final String subtitulo;

  /// Valor a pagar agora, em centavos (int). Vem pronto do backend.
  final int valorAgoraCentavos;

  /// Texto opcional sob o valor, ex.: "Adiantamento de 30%". Null = não mostra.
  final String? rotuloValor;
  final List<OpcaoPagamento> opcoes;
}
