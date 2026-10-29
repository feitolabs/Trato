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

  /// Lê as variáveis de compilação.
  factory ConfigAuth.doAmbiente() => const ConfigAuth(
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
        googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
        googleIosClientId: String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
      );

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String googleWebClientId;
  final String googleIosClientId;

  /// Sem URL e chave, o app roda com o serviço fake.
  bool get supabaseConfigurado => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get googleConfigurado => googleWebClientId.isNotEmpty;
}
