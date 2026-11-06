import 'defines_publicos.dart';

/// Configuração de execução do app. Tudo vem de `--dart-define`; nada de chave no código.
///
/// O app só fala com a API real: não existe modo de demonstração nem dado de exemplo.
/// - `TRATO_API_URL=https://...`: endereço base da API.
class ConfigTrato {
  const ConfigTrato({this.apiUrl = ''});

  /// Lê os `--dart-define` da compilação.
  factory ConfigTrato.doAmbiente() {
    final v = filtrarDefines(lerDefinesDoAmbiente());
    return ConfigTrato(apiUrl: v['TRATO_API_URL'] ?? '');
  }

  final String apiUrl;

  bool get usaApi => apiUrl.isNotEmpty;
}
