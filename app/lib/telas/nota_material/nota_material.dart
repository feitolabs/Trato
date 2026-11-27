/// Modelos e serviço da nota dos materiais (F6.5 do profissional, F5.9 do cliente).
/// Valores em centavos inteiros. A soma exibida é só conferência visual: o backend é quem vale.
library;

class ItemNota {
  const ItemNota({
    required this.descricao,
    this.quantidade = 1,
    int? valorUnitarioCentavos,
    int? centavos,
    this.id,
  }) : valorUnitarioCentavos = valorUnitarioCentavos ?? centavos ?? 0;

  /// `itens[].id` do servidor. Nulo (servidor antigo): só dá para contestar a nota inteira.
  final String? id;
  final String descricao;
  final int quantidade;
  final int valorUnitarioCentavos;

  int get centavos => quantidade * valorUnitarioCentavos;
  int get totalCentavos => centavos;

  /// "Parafuso — 2 × R$ 10,00 =" (a linha mostra o total ao lado). Com 1 unidade, só a descrição.
  /// [formatar] vem da tela (centavos -> reais): a conta do total é do próprio item.
  String rotuloComConta(String Function(int centavos) formatar) {
    if (quantidade <= 1) return descricao;
    return '$descricao — $quantidade × ${formatar(valorUnitarioCentavos)} =';
  }
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
    this.id,
  });

  final String? id;
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

  /// Todas as notas do pedido, da mais antiga para a mais nova (o profissional pode mandar mais
  /// de uma). Vazio = ainda não enviou nota.
  Future<List<NotaMaterial>> carregarTodas(String pedidoId);

  /// Lança exceção se falhar; a tela mostra mensagem simples.
  Future<void> enviar(EnvioNota envio);
}
