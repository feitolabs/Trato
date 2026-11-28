/// Compensações do profissional (Termos 8.6 e 17.4). Valores, situação, motivo e datas vêm do
/// servidor (`/v1/me/compensacoes`): o app não calcula nada, só mostra.
library;

import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _texto(Object? v) {
  final t = v is String ? v.trim() : '';
  return t.isEmpty ? null : t;
}

int? _centavos(Object? v) => v is int ? v : null;

class Compensacao {
  const Compensacao({
    required this.id,
    required this.status,
    this.pedidoId,
    this.valorCentavos,
    this.compensadoCentavos,
    this.restanteCentavos,
    this.motivo,
    this.criadaEm,
    this.avisadoEm,
    this.canceladaEm,
    this.motivoCancelamento,
    this.suspensa = false,
  });

  factory Compensacao.deJson(Map<String, dynamic> j) => Compensacao(
        id: '${j['id'] ?? ''}',
        status: _texto(j['status']) ?? '',
        pedidoId: _texto(j['pedido_id']),
        valorCentavos: _centavos(j['valor_centavos']),
        compensadoCentavos: _centavos(j['compensado_centavos']),
        restanteCentavos: _centavos(j['restante_centavos']),
        motivo: _texto(j['motivo']),
        criadaEm: _data(j['criada_em']),
        avisadoEm: _data(j['avisado_em']),
        canceladaEm: _data(j['cancelada_em']),
        motivoCancelamento: _texto(j['motivo_cancelamento']),
        suspensa: j['suspensa'] == true,
      );

  final String id;

  /// `aberta`, `quitada` ou `cancelada`.
  final String status;
  final String? pedidoId;

  /// Nulo: o servidor não informou (a tela diz isso, em vez de mostrar R$ 0,00).
  final int? valorCentavos;
  final int? compensadoCentavos;
  final int? restanteCentavos;
  final String? motivo;
  final DateTime? criadaEm;
  final DateTime? avisadoEm;
  final DateTime? canceladaEm;
  final String? motivoCancelamento;

  /// `suspensa`: compensação aberta com a decisão em revisão. Ausente (servidor antigo) = não.
  final bool suspensa;

  bool get emRevisao => suspensa && status == 'aberta';

  String get situacaoTexto => emRevisao
      ? 'Em revisão: desconto suspenso'
      : switch (status) {
        'aberta' => 'Aberta',
        'quitada' => 'Quitada',
        'cancelada' => 'Cancelada',
        _ => 'Em acompanhamento',
      };
}

const textoCompensacoesIndisponiveis =
    'As compensações estão indisponíveis no momento. Fale com o Trato.';

abstract interface class ServicoCompensacoes {
  /// Nulo: o servidor não tem a função (404/503).
  Future<List<Compensacao>?> listar();
}

class ServicoCompensacoesApi implements ServicoCompensacoes {
  ServicoCompensacoesApi(this._api);

  final ClienteApi _api;

  @override
  Future<List<Compensacao>?> listar() async {
    try {
      final j = await _api.get('/v1/me/compensacoes');
      return [
        for (final c in (j is List ? j : const []))
          if (c is Map<String, dynamic>) Compensacao.deJson(c),
      ];
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return null;
      rethrow;
    }
  }
}
