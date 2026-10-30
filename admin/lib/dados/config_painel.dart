import 'package:http/http.dart' as http;

import 'api_admin.dart';
import 'api_fake.dart';
import 'api_http.dart';

/// Como o painel escolhe a API. Tudo vem de `--dart-define` na hora de rodar ou compilar:
///
/// ```
/// flutter run -d chrome \
///   --dart-define=ADMIN_MODO=api \
///   --dart-define=ADMIN_API_URL=https://api.exemplo.com.br \
///   --dart-define=ADMIN_SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=ADMIN_SUPABASE_ANON_KEY=<chave pública (anon)>
/// ```
///
/// Sem `ADMIN_MODO=api` (ou com algum valor faltando) o painel usa os dados de exemplo.
/// Nunca ponha a chave de serviço (service role) aqui: o painel só usa a chave pública.
class ConfigPainel {
  const ConfigPainel({this.modo = '', this.urlApi = '', this.urlSupabase = '', this.chaveAnon = ''});

  static const doAmbiente = ConfigPainel(
    modo: String.fromEnvironment('ADMIN_MODO'),
    urlApi: String.fromEnvironment('ADMIN_API_URL'),
    urlSupabase: String.fromEnvironment('ADMIN_SUPABASE_URL'),
    chaveAnon: String.fromEnvironment('ADMIN_SUPABASE_ANON_KEY'),
  );

  final String modo;
  final String urlApi;
  final String urlSupabase;
  final String chaveAnon;

  bool get usaApi =>
      modo.trim().toLowerCase() == 'api' && urlApi.isNotEmpty && urlSupabase.isNotEmpty && chaveAnon.isNotEmpty;
}

/// Escolhe entre a API real e os dados de exemplo.
ApiAdmin criarApi(ConfigPainel config, {http.Client? cliente}) {
  if (!config.usaApi) return ApiFake(atraso: const Duration(milliseconds: 250));
  return ApiAdminHttp(
    urlApi: config.urlApi,
    urlSupabase: config.urlSupabase,
    chaveAnonSupabase: config.chaveAnon,
    cliente: cliente,
  );
}
