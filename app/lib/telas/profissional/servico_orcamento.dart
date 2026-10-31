/// O que o backend devolve para um total. Tudo já calculado lá (escopo 11.1).
class ResumoOrcamento {
  const ResumoOrcamento({
    required this.totalCentavos,
    required this.taxaCentavos,
    this.taxaBps,
    required this.liquidoCentavos,
    int? clientePagaCentavos,
  }) : clientePagaCentavos = clientePagaCentavos ?? totalCentavos + taxaCentavos;

  /// O valor do orçamento (serviço). O profissional recebe tudo: [liquidoCentavos] == [totalCentavos].
  final int totalCentavos;

  /// Taxa do Trato. É SOMADA ao orçamento e paga pelo cliente; não sai do profissional.
  final int taxaCentavos;

  /// O que o cliente paga à vista: orçamento + taxa. Vem do backend.
  final int clientePagaCentavos;

  /// Percentual da taxa em pontos-base (750 = 7,5%). A tela só exibe.
  final int? taxaBps;
  final int liquidoCentavos;
}

/// Porta entre a tela e a regra de taxa. A tela NÃO calcula taxa nem líquido: manda o total
/// em centavos e mostra o que voltar. A implementação real chama o backend (tarefa futura;
/// taxa progressiva base 7,5%, depende de P2/P5).
abstract interface class ServicoOrcamento {
  Future<ResumoOrcamento> resumir(int totalCentavos);
}
