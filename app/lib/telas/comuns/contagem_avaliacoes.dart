// Termos 12.3: com menos avaliações que o mínimo do servidor, o profissional é "Novo no Trato".
// O app não calcula média nem escolhe o mínimo.

/// O total de avaliações e o mínimo, como o servidor mandou.
class ContagemAvaliacoes {
  const ContagemAvaliacoes(this.total, this.minimo);

  final int total;
  final int minimo;

  bool get novoNoTrato => total < minimo;

  String get textoAvaliacoes => '$total ${total == 1 ? 'avaliação' : 'avaliações'}';

  /// Nulo sem os dois números (servidor antigo).
  static ContagemAvaliacoes? deJson(Object? j, {String chaveTotal = 'avaliacoes_total'}) {
    if (j is! Map) return null;
    final total = j[chaveTotal];
    final minimo = j['nota_minimo_avaliacoes'];
    return total is int && minimo is int && total >= 0 && minimo > 0
        ? ContagemAvaliacoes(total, minimo)
        : null;
  }
}

String textoServicosConcluidos(int n) =>
    '$n ${n == 1 ? 'serviço concluído' : 'serviços concluídos'}';
