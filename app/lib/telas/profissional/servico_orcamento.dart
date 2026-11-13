class ItemMaterial {
  const ItemMaterial({required this.nome, required this.centavos});

  final String nome;
  final int centavos;
}

/// O que a tela entrega ao tocar em "Enviar orçamento". O total é só soma para exibir;
/// quem confere e grava é o backend.
class OrcamentoPronto {
  const OrcamentoPronto({
    required this.decimosDeslocamento,
    required this.decimosDeHora,
    required this.valorHoraCentavos,
    required this.garantiaDias,
    required this.itens,
    required this.materialPorMim,
    required this.pedirSinalMaterial,
    required this.totalCentavos,
  });

  /// Horas de deslocamento, em décimos de hora (15 = 1,5 h). Cobradas pelo mesmo valor da hora.
  final int decimosDeslocamento;

  /// Horas trabalhadas, em décimos de hora.
  final int decimosDeHora;
  final int valorHoraCentavos;
  final int garantiaDias;
  final List<ItemMaterial> itens;
  final bool materialPorMim;
  final bool pedirSinalMaterial;
  final int totalCentavos;

  /// Total de horas que o cliente vai ver: deslocamento + trabalhadas, em décimos de hora.
  int get totalDecimosDeHora => decimosDeslocamento + decimosDeHora;
}

/// O que o backend devolve para um total. Tudo já calculado lá (escopo 11.1).
class ResumoOrcamento {
  const ResumoOrcamento({
    required this.totalCentavos,
    required this.taxaCentavos,
    this.taxaBps,
    required this.liquidoCentavos,
    int? clientePagaCentavos,
  }) : clientePagaCentavos = clientePagaCentavos ?? totalCentavos;

  /// O valor do orçamento (serviço). [liquidoCentavos] é esse valor menos [taxaCentavos].
  final int totalCentavos;

  /// Taxa do Trato. É descontada do profissional; o cliente não paga por cima.
  final int taxaCentavos;

  /// O que o cliente paga à vista: o valor do orçamento. Vem do backend.
  final int clientePagaCentavos;

  /// Percentual da taxa em pontos-base (750 = 7,5%). A tela só exibe.
  final int? taxaBps;
  final int liquidoCentavos;
}

/// Porta entre a tela e o backend de orçamentos.
abstract interface class ServicoOrcamento {
  Future<ResumoOrcamento> resumir(int totalCentavos);
  Future<void> enviar(OrcamentoPronto pronto);
}
