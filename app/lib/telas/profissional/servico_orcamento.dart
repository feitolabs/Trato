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
    this.prazoExecucaoDias = 3,
    required this.itens,
    required this.materialPorMim,
    required this.pedirSinalMaterial,
    required this.totalCentavos,
    this.foraDoEscopo,
    this.observacoes,
  });

  /// Horas de deslocamento, em décimos de hora (15 = 1,5 h). Cobradas pelo mesmo valor da hora.
  final int decimosDeslocamento;

  /// Horas trabalhadas, em décimos de hora.
  final int decimosDeHora;
  final int valorHoraCentavos;
  final int garantiaDias;
  final int prazoExecucaoDias;
  final List<ItemMaterial> itens;
  final bool materialPorMim;
  final bool pedirSinalMaterial;
  final int totalCentavos;
  final String? foraDoEscopo;
  final String? observacoes;

  /// Total de horas que o cliente vai ver: deslocamento + trabalhadas, em décimos de hora.
  int get totalDecimosDeHora => decimosDeslocamento + decimosDeHora;
}

/// O que o backend devolve para um total. Sem taxa: o cliente paga e o profissional recebe o mesmo valor.
class ResumoOrcamento {
  const ResumoOrcamento({required this.totalCentavos});

  /// O valor do orçamento (serviço).
  final int totalCentavos;
}

/// Porta entre a tela e o backend de orçamentos.
abstract interface class ServicoOrcamento {
  Future<ResumoOrcamento> resumir(int totalCentavos);
  Future<void> enviar(OrcamentoPronto pronto);
}
