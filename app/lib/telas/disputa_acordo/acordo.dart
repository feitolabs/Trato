/// Proposta de devolução do profissional e acordo da disputa (Termos 8.2). Os valores vêm do
/// servidor, em centavos: o app só mostra e devolve a proposta aceita.
library;

import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';
import '../comuns/resultado_esperado.dart';

int? _centavos(Object? v) => v is int && v >= 0 ? v : null;

class PropostaDisputa {
  const PropostaDisputa({required this.solucao, required this.reembolsoCentavos});

  final String solucao;
  final int? reembolsoCentavos;

  /// Só a proposta de devolução com valor pode ser aceita.
  bool get podeAceitar => solucao == 'reembolso_parcial' && (reembolsoCentavos ?? 0) > 0;

  static PropostaDisputa? deJson(Object? j) {
    if (j is! Map || j['solucao'] is! String) return null;
    return PropostaDisputa(
      solucao: j['solucao'] as String,
      reembolsoCentavos: _centavos(j['reembolso_centavos']),
    );
  }
}

class AcordoDisputa {
  const AcordoDisputa({this.reembolsoCentavos, this.liberadoCentavos});

  final int? reembolsoCentavos;
  final int? liberadoCentavos;

  static AcordoDisputa? deJson(Object? j) => j is! Map
      ? null
      : AcordoDisputa(
          reembolsoCentavos: _centavos(j['reembolso_centavos']),
          liberadoCentavos: _centavos(j['liberado_centavos']),
        );
}

class SituacaoDisputa {
  const SituacaoDisputa({this.estado, this.proposta, this.acordo, this.pedidoDoCliente});

  /// Termos 8.4: o texto do que o cliente pediu. Nulo: não informado.
  final String? pedidoDoCliente;

  final String? estado;

  /// Ausente em servidor antigo.
  final PropostaDisputa? proposta;
  final AcordoDisputa? acordo;

  /// Proposta que ainda pode ser aceita (a palavra final é do servidor).
  PropostaDisputa? get propostaAberta =>
      acordo == null && estado != 'acordo' && estado != 'decidida' && (proposta?.podeAceitar ?? false)
          ? proposta
          : null;

  static SituacaoDisputa deJson(Map<dynamic, dynamic> j) => SituacaoDisputa(
        estado: j['estado'] is String ? j['estado'] as String : null,
        proposta: PropostaDisputa.deJson(j['proposta']),
        acordo: AcordoDisputa.deJson(j['acordo']),
        pedidoDoCliente: separarRelato(j['descricao'], j['resultado_esperado']).pedido,
      );
}

abstract interface class ServicoAcordoDisputa {
  /// Nulo: o pedido não tem disputa ou o servidor não tem a função (404/503).
  Future<SituacaoDisputa?> ver(String pedidoId);

  Future<SituacaoDisputa?> aceitar(String pedidoId, PropostaDisputa proposta);
}

class ServicoAcordoDisputaApi implements ServicoAcordoDisputa {
  ServicoAcordoDisputaApi(this._api);

  final ClienteApi _api;

  @override
  Future<SituacaoDisputa?> ver(String pedidoId) async {
    try {
      final j = await _api.get('/v1/pedidos/$pedidoId/disputa');
      return j is Map ? SituacaoDisputa.deJson(j) : null;
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return null;
      rethrow;
    }
  }

  @override
  Future<SituacaoDisputa?> aceitar(String pedidoId, PropostaDisputa proposta) async {
    final j = await _api.post(
      '/v1/pedidos/$pedidoId/disputa/aceitar-proposta',
      corpo: {
        'solucao': proposta.solucao,
        'reembolso_centavos': proposta.reembolsoCentavos,
      },
    );
    return j is Map ? SituacaoDisputa.deJson(j) : null;
  }
}
