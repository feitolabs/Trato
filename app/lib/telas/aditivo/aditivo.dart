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

