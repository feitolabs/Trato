/// Evento externo / força maior em um pedido (Termos 7.8 e 22.6).
/// O app só coleta a solicitação e exibe a análise do servidor.
library;

import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _texto(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

List<String> _listaTexto(Object? bruto) {
  if (bruto is! List) return const [];
  final saida = <String>[];
  for (final item in bruto) {
    final t = _texto(item);
    if (t != null) saida.add(t);
  }
  return saida.isEmpty ? const [] : List.unmodifiable(saida);
}

class EventoForcaMaior {
  const EventoForcaMaior({
    required this.id,
    required this.pedidoId,
    required this.acaoSolicitada,
    required this.descricao,
    required this.status,
    this.solicitanteId,
    this.solicitantePapel,
    this.comprovantes = const [],
    this.criadoEm,
    this.justificativaDecisao,
    this.decididoEm,
  });

  final String id;
  final String pedidoId;
  final String? solicitanteId;
  final String? solicitantePapel;

  /// `'reagendar'` ou `'cancelar'`.
  final String acaoSolicitada;
  final String descricao;
  final List<String> comprovantes;

  /// `'pendente'`, `'aprovado'` ou `'recusado'`.
  final String status;
  final DateTime? criadoEm;
  final String? justificativaDecisao;
  final DateTime? decididoEm;

  static EventoForcaMaior? deJson(Object? bruto) {
    if (bruto is! Map) return null;
    final id = _texto(bruto['id']);
    final acao = _texto(bruto['acao_solicitada']);
    final desc = _texto(bruto['descricao']);
    final status = _texto(bruto['status']);
    if (id == null || acao == null || desc == null || status == null) return null;
    return EventoForcaMaior(
      id: id,
      pedidoId: _texto(bruto['pedido_id']) ?? '',
      solicitanteId: _texto(bruto['solicitante_id']),
      solicitantePapel: _texto(bruto['solicitante_papel']),
      acaoSolicitada: acao,
      descricao: desc,
      comprovantes: _listaTexto(bruto['comprovantes']),
      status: status,
      criadoEm: _data(bruto['criado_em']),
      justificativaDecisao: _texto(bruto['justificativa_decisao']),
      decididoEm: _data(bruto['decidido_em']),
    );
  }
}

abstract interface class ServicoForcaMaior {
  /// Lista as solicitações de força maior do pedido.
  /// Retorna nulo se 404/503 (servidor antigo / indisponível).
  Future<List<EventoForcaMaior>?> listar(String pedidoId);

  Future<EventoForcaMaior> solicitar(
    String pedidoId, {
    required String acaoSolicitada,
    required String descricao,
    List<String> comprovantes = const [],
  });
}

class ServicoForcaMaiorApi implements ServicoForcaMaior {
  ServicoForcaMaiorApi(this._api);

  final ClienteApi _api;

  @override
  Future<List<EventoForcaMaior>?> listar(String pedidoId) async {
    try {
      final bruto = await _api.get('/v1/pedidos/$pedidoId/forca-maior');
      if (bruto is! List) return const [];
      return [
        for (final item in bruto)
          if (EventoForcaMaior.deJson(item) case final e?) e,
      ];
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return null;
      rethrow;
    }
  }

  @override
  Future<EventoForcaMaior> solicitar(
    String pedidoId, {
    required String acaoSolicitada,
    required String descricao,
    List<String> comprovantes = const [],
  }) async {
    final j = await _api.post(
      '/v1/pedidos/$pedidoId/forca-maior',
      corpo: {
        'acao_solicitada': acaoSolicitada,
        'descricao': descricao.trim(),
        'comprovantes': comprovantes.take(10).toList(),
      },
    );
    final parsed = EventoForcaMaior.deJson(j);
    if (parsed == null) {
      throw const ErroTrato(TipoErro.servidor, 'Não foi possível ler a resposta do servidor.');
    }
    return parsed;
  }
}
