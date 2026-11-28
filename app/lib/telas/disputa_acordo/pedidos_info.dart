/// Pedidos de informação adicional na disputa (Termos 8.4, prazo de 10 dias úteis).
/// O app só exibe o que o servidor devolver e envia a resposta do destinatário.
library;

import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _texto(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

class PedidoInfoDisputa {
  const PedidoInfoDisputa({
    required this.id,
    required this.disputaId,
    required this.pedidoId,
    required this.destinatarioPapel,
    required this.mensagem,
    required this.status,
    this.solicitadoEm,
    this.responderAte,
    this.respondidoEm,
    this.respostaTexto,
    this.encerradoSemRespostaEm,
  });

  final String id;
  final String disputaId;
  final String pedidoId;

  /// `'cliente'` ou `'profissional'`.
  final String destinatarioPapel;
  final String mensagem;

  /// `'aguardando_resposta'`, `'vencido'`, `'respondido'` ou `'encerrado_sem_resposta'`.
  final String status;
  final DateTime? solicitadoEm;
  final DateTime? responderAte;
  final DateTime? respondidoEm;
  final String? respostaTexto;
  final DateTime? encerradoSemRespostaEm;

  bool get aceitaResposta => status == 'aguardando_resposta' || status == 'vencido';

  bool podeResponder({required bool profissional}) =>
      aceitaResposta && destinatarioPapel == (profissional ? 'profissional' : 'cliente');

  static PedidoInfoDisputa? deJson(Object? bruto) {
    if (bruto is! Map) return null;
    final id = _texto(bruto['id']);
    final mensagem = _texto(bruto['mensagem']);
    final destinatario = _texto(bruto['destinatario_papel']);
    final status = _texto(bruto['status']);
    if (id == null || mensagem == null || destinatario == null || status == null) return null;
    return PedidoInfoDisputa(
      id: id,
      disputaId: _texto(bruto['disputa_id']) ?? '',
      pedidoId: _texto(bruto['pedido_id']) ?? '',
      destinatarioPapel: destinatario,
      mensagem: mensagem,
      status: status,
      solicitadoEm: _data(bruto['solicitado_em']),
      responderAte: _data(bruto['responder_ate']),
      respondidoEm: _data(bruto['respondido_em']),
      respostaTexto: _texto(bruto['resposta_texto']),
      encerradoSemRespostaEm: _data(bruto['encerrado_sem_resposta_em']),
    );
  }
}

abstract interface class ServicoPedidosInfoDisputa {
  /// Lista os pedidos de informação da disputa (aceita `disputa_id` ou `pedido_id`).
  /// Retorna lista vazia se 404/503/servidor antigo.
  Future<List<PedidoInfoDisputa>> listar(String disputaOuPedidoId);

  Future<PedidoInfoDisputa> responder(
    String disputaOuPedidoId,
    String pedidoInfoId,
    String respostaTexto,
  );
}

class ServicoPedidosInfoDisputaApi implements ServicoPedidosInfoDisputa {
  ServicoPedidosInfoDisputaApi(this._api);

  final ClienteApi _api;

  @override
  Future<List<PedidoInfoDisputa>> listar(String disputaOuPedidoId) async {
    try {
      final bruto = await _api.get('/v1/disputas/$disputaOuPedidoId/pedidos-informacao');
      if (bruto is! List) return const [];
      return [
        for (final item in bruto)
          if (PedidoInfoDisputa.deJson(item) case final p?) p,
      ];
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return const [];
      rethrow;
    }
  }

  @override
  Future<PedidoInfoDisputa> responder(
    String disputaOuPedidoId,
    String pedidoInfoId,
    String respostaTexto,
  ) async {
    final j = await _api.post(
      '/v1/disputas/$disputaOuPedidoId/pedidos-informacao/$pedidoInfoId/responder',
      corpo: {'resposta_texto': respostaTexto.trim()},
    );
    final parsed = PedidoInfoDisputa.deJson(j);
    if (parsed == null) {
      throw const ErroTrato(TipoErro.servidor, 'Não foi possível ler a resposta do servidor.');
    }
    return parsed;
  }
}
