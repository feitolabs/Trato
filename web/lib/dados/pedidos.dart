import 'cliente_api.dart';

/// Espelha os campos usados de `PedidoOut` (`GET /v1/pedidos`, "Meus pedidos").
/// Sem valores em dinheiro aqui: isso fica na tela de detalhe do backend real.
class PedidoResumo {
  const PedidoResumo({
    required this.id,
    required this.estado,
    required this.estadoNome,
    required this.abertoEm,
    this.urgente = false,
  });

  final String id;
  final String estado;
  final String estadoNome;
  final DateTime abertoEm;
  final bool urgente;

  factory PedidoResumo.deJson(Map<String, dynamic> json) => PedidoResumo(
        id: json['id'] as String,
        estado: json['estado'] as String,
        estadoNome: json['estado_nome'] as String,
        abertoEm: DateTime.parse(json['aberto_em'] as String),
        urgente: json['urgente'] as bool? ?? false,
      );
}

class RepositorioPedidos {
  RepositorioPedidos(this._api);

  final ClienteApi _api;

  Future<List<PedidoResumo>> listar() async {
    final json = await _api.get('/v1/pedidos');
    return (json as List)
        .cast<Map<String, dynamic>>()
        .map(PedidoResumo.deJson)
        .toList();
  }
}
