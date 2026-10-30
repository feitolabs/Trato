/// Modelos e serviço da nota dos materiais (F6.5 do profissional, F5.9 do cliente).
/// Valores em centavos inteiros. A soma exibida é só conferência visual: o backend é quem vale.
library;

class ItemNota {
  const ItemNota({required this.descricao, required this.centavos});

  final String descricao;
  final int centavos;
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

/// PROVISÓRIO — só para teste e demonstração.
class ServicoNotaMaterialFake implements ServicoNotaMaterial {
  ServicoNotaMaterialFake({this.nota, this.falharAoCarregar = false, this.falharAoEnviar = false});

  final NotaMaterial? nota;
  final bool falharAoCarregar;
  final bool falharAoEnviar;
  final List<EnvioNota> enviados = [];

  @override
  Future<NotaMaterial?> carregar(String pedidoId) async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return nota;
  }

  @override
  Future<void> enviar(EnvioNota envio) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    enviados.add(envio);
  }
}

final notaMaterialExemplo = NotaMaterial(
  pedidoTitulo: 'Troca de tomadas e chuveiro',
  profissional: 'Carlos',
  enviadaEm: DateTime(2026, 10, 28),
  fotoNota: 'nota-123',
  itens: const [
    ItemNota(descricao: '2 tomadas 20 A', centavos: 4600),
    ItemNota(descricao: 'Resistência 220 V', centavos: 6400),
    ItemNota(descricao: 'Fita isolante', centavos: 900),
  ],
);
