import 'dart:convert';

/// Configuração do site, lida de `--dart-define` na compilação (ver `README.md`).
///
/// Tudo isto vai para dentro do JavaScript publicado: só cabem valores **públicos**.
/// Os nomes são os mesmos do app (`harness/verificar_defines.py`).
class ConfigWeb {
  const ConfigWeb({this.urlApi = '', this.urlSupabase = '', this.chaveAnon = ''});

  factory ConfigWeb.doAmbiente() => const ConfigWeb(
        urlApi: String.fromEnvironment('TRATO_API_URL'),
        urlSupabase: String.fromEnvironment('SUPABASE_URL'),
        chaveAnon: String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

  final String urlApi;
  final String urlSupabase;
  final String chaveAnon;

  /// O que impede o site de abrir. Só cita **nomes** de variáveis, nunca valores.
  List<String> get problemas => [
        if (!_enderecoValido(urlApi)) 'TRATO_API_URL ausente ou inválida',
        if (!_enderecoValido(urlSupabase)) 'SUPABASE_URL ausente ou inválida',
        if (chaveAnon.trim().isEmpty)
          'SUPABASE_ANON_KEY ausente'
        else if (_chaveSecreta(chaveAnon))
          'SUPABASE_ANON_KEY é uma chave secreta: use só a pública',
      ];

  /// `https` sempre; `http` só para a própria máquina (desenvolvimento).
  static bool _enderecoValido(String valor) {
    final uri = Uri.tryParse(valor);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    return uri.scheme == 'http' && (uri.host == 'localhost' || uri.host == '127.0.0.1');
  }

  static bool _chaveSecreta(String valor) {
    final v = valor.trim();
    if (v.startsWith('sb_secret_') || v.startsWith('sk_') || v.startsWith('rk_')) return true;
    final partes = v.split('.');
    if (partes.length != 3) return false;
    try {
      final corpo = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))));
      return corpo is Map && corpo['role'] == 'service_role';
    } on FormatException {
      return false;
    }
  }
}
