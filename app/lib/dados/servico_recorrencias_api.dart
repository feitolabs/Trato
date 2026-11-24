import '../telas/recorrencias/modelos.dart';
import 'cliente_api.dart';
import 'erros.dart';

/// `/v1/recorrencias`: propor, listar, detalhar e agir na série (cada ação devolve a série).
/// Erros 403, 409 e 422 vêm com texto em português do backend e seguem como estão.
class ServicoRecorrenciasApi implements ServicoRecorrencias {
  ServicoRecorrenciasApi(this._api);

  final ClienteApi _api;

  static const _base = '/v1/recorrencias';

  Recorrencia _serie(Object? json) {
    final r = Recorrencia.deJson(json);
    if (r == null) throw ErroTrato.servidor;
    return r;
  }

  @override
  Future<List<Recorrencia>> listar() async {
    final bruto = await _api.get(_base);
    return [
      for (final j in (bruto as List? ?? const []))
        if (Recorrencia.deJson(j) case final r?) r,
    ];
  }

  @override
  Future<Recorrencia> detalhe(String id) async => _serie(await _api.get('$_base/$id'));

  @override
  Future<Recorrencia> propor(String pedidoOrigemId, PropostaRecorrencia proposta) async => _serie(
        await _api.post(
          _base,
          corpo: {
            'pedido_origem_id': pedidoOrigemId,
            'frequencia': proposta.frequencia.codigo,
            'proxima_visita_em': proposta.proximaVisita.toUtc().toIso8601String(),
            if (proposta.valorCentavos != null) 'valor_centavos': proposta.valorCentavos,
          },
        ),
      );

  Future<Recorrencia> _acao(String id, String caminho, {Object? corpo}) async =>
      _serie(await _api.post('$_base/$id/$caminho', corpo: corpo));

  @override
  Future<Recorrencia> aceitar(String id) => _acao(id, 'aceitar');

  @override
  Future<Recorrencia> recusar(String id) => _acao(id, 'recusar');

  @override
  Future<Recorrencia> pausar(String id) => _acao(id, 'pausar');

  @override
  Future<Recorrencia> retomar(String id) => _acao(id, 'retomar');

  @override
  Future<Recorrencia> cancelar(String id) => _acao(id, 'cancelar');

  @override
  Future<Recorrencia> pularProxima(String id) => _acao(id, 'pular-proxima');

  @override
  Future<Recorrencia> pularVisita(String id, String visitaId) =>
      _acao(id, 'visitas/$visitaId/pular');

  @override
  Future<Recorrencia> proporReajuste(String id, int valorCentavos) =>
      _acao(id, 'reajuste', corpo: {'valor_centavos': valorCentavos});

  @override
  Future<Recorrencia> aceitarReajuste(String id, int valorCentavos) =>
      _acao(id, 'reajuste/aceitar', corpo: {'valor_centavos': valorCentavos});

  @override
  Future<Recorrencia> recusarReajuste(String id) => _acao(id, 'reajuste/recusar');
}
