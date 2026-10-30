import '../dados/defines_publicos.dart';

/// Configuração pública do login. Vem de `--dart-define` ou de
/// `--dart-define-from-file=.env` (ver docs/login-configuracao.md); nunca fica no código.
/// A chave aqui é a pública (anon/publishable): nunca use a service role no app.
class ConfigAuth {
  const ConfigAuth({
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.googleWebClientId = '',
    this.googleIosClientId = '',
  });

  /// Lê as variáveis de compilação, passando pela lista permitida (M14).
  factory ConfigAuth.doAmbiente() => ConfigAuth.deValores(filtrarDefines(lerDefinesDoAmbiente()));

  /// Monta a partir de valores já filtrados (também usado nos testes).
  factory ConfigAuth.deValores(Map<String, String> v) => ConfigAuth(
        supabaseUrl: v['SUPABASE_URL'] ?? '',
        supabaseAnonKey: v['SUPABASE_ANON_KEY'] ?? '',
        googleWebClientId: v['GOOGLE_WEB_CLIENT_ID'] ?? '',
        googleIosClientId: v['GOOGLE_IOS_CLIENT_ID'] ?? '',
      );

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String googleWebClientId;
  final String googleIosClientId;

  /// Sem URL e chave, o app roda com o serviço fake.
  bool get supabaseConfigurado => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get googleConfigurado => googleWebClientId.isNotEmpty;
}
