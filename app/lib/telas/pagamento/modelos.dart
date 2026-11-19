// Modelos da tela de pagamento. O app só exibe o que vier daqui:
// quanto pagar agora e em que condição são decididos pelo backend.

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
    this.parcelamento = const [],
    this.descontoCentavos = 0,
    this.cupomCodigo,
    this.moedasSaldo = 0,
    this.moedasUsadas = 0,
    this.moedasDescontoCentavos = 0,
  });

  /// Total por número de parcelas no cartão. Vazio enquanto o parcelado estiver desligado.
  final List<OpcaoParcelamento> parcelamento;

  /// "Carlos Mendes · Troca de tomadas e chuveiro".
  final String subtitulo;

  /// Valor a pagar agora, em centavos (int). Vem pronto do backend.
  final int valorAgoraCentavos;

  /// Desconto aplicado pelo cupom (em centavos). Zero quando não há cupom.
  final int descontoCentavos;

  /// Código de cupom aceito e aplicado neste cálculo.
  final String? cupomCodigo;

  /// Moedas do Trato: saldo do cliente, quantas entram neste cálculo e o desconto delas. Tudo
  /// vem pronto do backend; o app só mostra.
  final int moedasSaldo;
  final int moedasUsadas;
  final int moedasDescontoCentavos;

  /// Texto opcional sob o valor, ex.: "Adiantamento de 30%". Null = não mostra.
  final String? rotuloValor;
  final List<OpcaoPagamento> opcoes;

  DadosPagamento copiarCom({
    String? subtitulo,
    int? valorAgoraCentavos,
    List<OpcaoParcelamento>? parcelamento,
    int? descontoCentavos,
    String? cupomCodigo,
    int? moedasSaldo,
    int? moedasUsadas,
    int? moedasDescontoCentavos,
    String? rotuloValor,
    List<OpcaoPagamento>? opcoes,
  }) =>
      DadosPagamento(
        subtitulo: subtitulo ?? this.subtitulo,
        valorAgoraCentavos: valorAgoraCentavos ?? this.valorAgoraCentavos,
        parcelamento: parcelamento ?? this.parcelamento,
        descontoCentavos: descontoCentavos ?? this.descontoCentavos,
        cupomCodigo: cupomCodigo ?? this.cupomCodigo,
        moedasSaldo: moedasSaldo ?? this.moedasSaldo,
        moedasUsadas: moedasUsadas ?? this.moedasUsadas,
        moedasDescontoCentavos: moedasDescontoCentavos ?? this.moedasDescontoCentavos,
        rotuloValor: rotuloValor ?? this.rotuloValor,
        opcoes: opcoes ?? this.opcoes,
      );
}
