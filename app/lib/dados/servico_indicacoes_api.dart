import '../telas/indicacoes/modelos.dart';
import 'cliente_api.dart';

/// `/v1/indicacoes/...`: meu código e lista (login), validar um código (público) e aplicar.
class ServicoIndicacoesApi implements ServicoIndicacoes {
  ServicoIndicacoesApi(this._api);

  final ClienteApi _api;

  @override
  Future<MeuCodigoIndicacao> meuCodigo() async =>
      MeuCodigoIndicacao.deJson(await _api.get('/v1/indicacoes/meu-codigo'));

  @override
  Future<ConviteIndicacao> validar(String codigo) async => ConviteIndicacao.deJson(
        await _api.get('/v1/indicacoes/codigo/${Uri.encodeComponent(codigo.trim().toUpperCase())}'),
      );

  @override
  Future<ResultadoAplicacao> aplicar(String codigo) async => ResultadoAplicacao.deJson(
        await _api.post(
          '/v1/indicacoes/aplicar',
          corpo: {'codigo': codigo.trim().toUpperCase()},
        ),
      );
}
