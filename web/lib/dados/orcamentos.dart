import 'cliente_api.dart';

/// Espelha `OrcamentoEnviadoOut` (`GET /v1/profissional/orcamentos`): só exibe o valor que o
/// backend já calculou, em centavos — nenhuma conta é feita aqui.
class OrcamentoEnviado {
  const OrcamentoEnviado({
    required this.orcamentoId,
    required this.pedidoId,
    required this.tituloPedido,
    required this.valorCentavos,
    required this.situacao,
    this.enviadoEm,
  });

  final String orcamentoId;
  final String pedidoId;
  final String? tituloPedido;
  final int valorCentavos;
  final String situacao;
  final DateTime? enviadoEm;

  factory OrcamentoEnviado.deJson(Map<String, dynamic> json) => OrcamentoEnviado(
        orcamentoId: json['orcamento_id'] as String,
        pedidoId: json['pedido_id'] as String,
        tituloPedido: json['titulo_pedido'] as String?,
        valorCentavos: json['valor_centavos'] as int,
        situacao: json['situacao'] as String,
        enviadoEm:
            json['enviado_em'] == null ? null : DateTime.parse(json['enviado_em'] as String),
      );
}

class RepositorioOrcamentos {
  RepositorioOrcamentos(this._api);

  final ClienteApi _api;

  Future<List<OrcamentoEnviado>> listarEnviados() async {
    final json = await _api.get('/v1/profissional/orcamentos');
    return (json as List).cast<Map<String, dynamic>>().map(OrcamentoEnviado.deJson).toList();
  }
}
