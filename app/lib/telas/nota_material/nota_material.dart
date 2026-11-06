/// Modelos e serviço da nota dos materiais (F6.5 do profissional, F5.9 do cliente).
/// Valores em centavos inteiros. A soma exibida é só conferência visual: o backend é quem vale.
library;

class ItemNota {
  const ItemNota({
    required this.descricao,
    this.quantidade = 1,
    int? valorUnitarioCentavos,
    int? centavos,
  }) : valorUnitarioCentavos = valorUnitarioCentavos ?? centavos ?? 0;

  final String descricao;
  final int quantidade;
  final int valorUnitarioCentavos;

  int get centavos => quantidade * valorUnitarioCentavos;
  int get totalCentavos => centavos;
}

/// Envio do profissional: foto da notinha + itens com valor.
class EnvioNota {
  const EnvioNota({required this.pedidoId, required this.fotoNota, required this.itens});

  final String pedidoId;

  /// Referência da foto devolvida por quem captura.
  final String fotoNota;
  final List<ItemNota> itens;
}

/// Nota como o cliente vê.
class NotaMaterial {
  const NotaMaterial({
    required this.pedidoTitulo,
    required this.profissional,
    required this.enviadaEm,
    required this.itens,
    this.fotoNota,
  });

  final String pedidoTitulo;
  final String profissional;
  final DateTime enviadaEm;
  final List<ItemNota> itens;
  final String? fotoNota;

  int get somaCentavos => itens.fold(0, (s, i) => s + i.centavos);
}

abstract interface class ServicoNotaMaterial {
  /// null ou sem itens = o profissional ainda não enviou nota.
  Future<NotaMaterial?> carregar(String pedidoId);

  /// Lança exceção se falhar; a tela mostra mensagem simples.
  Future<void> enviar(EnvioNota envio);
}

