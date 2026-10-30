/// O que o backend devolve para um total. Tudo já calculado lá (escopo 11.1).
class ResumoOrcamento {
  const ResumoOrcamento({
    required this.totalCentavos,
    required this.taxaCentavos,
    required this.taxaBps,
    required this.liquidoCentavos,
  });

  final int totalCentavos;
  final int taxaCentavos;

  /// Percentual da taxa em pontos-base (750 = 7,5%). A tela só exibe.
  final int taxaBps;
  final int liquidoCentavos;
}

/// Porta entre a tela e a regra de taxa. A tela NÃO calcula taxa nem líquido: manda o total
/// em centavos e mostra o que voltar. A implementação real chama o backend (tarefa futura;
/// taxa progressiva base 7,5%, depende de P2/P5).
abstract interface class ServicoOrcamento {
  Future<ResumoOrcamento> resumir(int totalCentavos);
}
