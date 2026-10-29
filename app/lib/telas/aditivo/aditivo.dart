/// Modelos e serviço do aditivo com preço (F6.5 do profissional, F5.9 do cliente).
/// Só vale com aprovação do cliente no app (D9). Valores em centavos inteiros.
library;

import '../pedidos/modelos.dart' show EstadoAditivo;

export '../pedidos/modelos.dart' show EstadoAditivo;

class NovoAditivo {
  const NovoAditivo({required this.pedidoId, required this.motivo, required this.valorCentavos});

  final String pedidoId;
  final String motivo;
  final int valorCentavos;
}

/// Aditivo como o cliente vê.
class DetalheAditivo {
  const DetalheAditivo({
    required this.id,
    required this.pedidoTitulo,
    required this.profissional,
    required this.motivo,
    required this.valorCentavos,
    this.estado = EstadoAditivo.aguardando,
  });

  final String id;
  final String pedidoTitulo;
  final String profissional;
  final String motivo;
  final int valorCentavos;
  final EstadoAditivo estado;
}

abstract interface class ServicoAditivo {
  Future<void> criar(NovoAditivo aditivo);

  /// null = não há aditivo para este pedido.
  Future<DetalheAditivo?> carregar(String aditivoId);

  /// Quem decide e registra é o backend. O app só pede.
  Future<void> responder(String aditivoId, {required bool aprovar});
}

/// PROVISÓRIO — só para teste e demonstração.
class ServicoAditivoFake implements ServicoAditivo {
  ServicoAditivoFake({this.detalhe, this.falharAoCarregar = false, this.falharAoEnviar = false});

  final DetalheAditivo? detalhe;
  final bool falharAoCarregar;
  final bool falharAoEnviar;
  final List<NovoAditivo> criados = [];
  final List<(String, bool)> respostas = [];

  @override
  Future<void> criar(NovoAditivo aditivo) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    criados.add(aditivo);
  }

  @override
  Future<DetalheAditivo?> carregar(String aditivoId) async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return detalhe;
  }

  @override
  Future<void> responder(String aditivoId, {required bool aprovar}) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    respostas.add((aditivoId, aprovar));
  }
}

const aditivoExemplo = DetalheAditivo(
  id: 'ad-1',
  pedidoTitulo: 'Troca de tomadas e chuveiro',
  profissional: 'Carlos',
  motivo: 'A fiação do chuveiro estava ressecada. Precisei trocar 6 m de cabo 6 mm.',
  valorCentavos: 4500,
);
