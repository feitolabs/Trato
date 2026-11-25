import 'modelos.dart';

/// "Concluído" ou "Cancelado" para o estado final de um pedido; nulo nos outros (a lista deriva o
/// rótulo como antes: negociação, em andamento, retrabalho).
String? rotuloDeConversaPeloEstado(String? estadoApi) => switch (estadoApi) {
      'concluido' => 'Concluído',
      'cancelado' => 'Cancelado',
      'retrabalho' => 'Retrabalho',
      _ => null,
    };

/// Põe o ESTADO REAL do pedido no rótulo de cada conversa: o servidor só diz "contratado", e por
/// isso um serviço concluído aparecia como "Em andamento". Se o estado não puder ser lido, a lista
/// segue como veio.
class ServicoMensagensComEstado implements ServicoMensagens {
  const ServicoMensagensComEstado(this._base, this._estados);

  final ServicoMensagens _base;

  /// Estado de cada pedido por id (`concluido`, `cancelado`...).
  final Future<Map<String, String>> Function() _estados;

  @override
  Future<List<ConversaResumo>> listar() async {
    final porEstado = _lerEstados();
    final lista = await _base.listar();
    final estados = await porEstado;
    return [
      for (final c in lista) _comEstado(c, estados),
    ];
  }

  Future<Map<String, String>> _lerEstados() async {
    try {
      return await _estados();
    } on Object {
      return const <String, String>{};
    }
  }

  ConversaResumo _comEstado(ConversaResumo c, Map<String, String> estados) {
    if ((c.rotuloEstado ?? '').trim().isNotEmpty) return c;
    final rotulo = rotuloDeConversaPeloEstado(estados[c.pedidoId]);
    return rotulo == null ? c : c.comRotuloEstado(rotulo);
  }
}
