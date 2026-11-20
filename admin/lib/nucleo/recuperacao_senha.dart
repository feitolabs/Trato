/// O que o painel entende do link de redefinição de senha do Supabase Auth (tipo recovery).
///
/// O Supabase devolve o token no fragmento da URL (`#access_token=...&type=recovery`) ou, se o
/// link não vale mais, um erro (`#error_code=otp_expired`). O token fica só em memória: o
/// `toString` o esconde para não ir parar em log.
class LinkRecuperacao {
  const LinkRecuperacao._({this.token, this.expirado = false});

  /// Token de uso único para trocar a senha. Nulo quando o link já chegou inválido.
  final String? token;

  /// O link expirou, já foi usado ou veio com erro.
  final bool expirado;

  /// Devolve o link de recovery contido em [uri], ou null se a URL não tem nada disso.
  static LinkRecuperacao? deUri(Uri uri) {
    final partes = _parametros(uri);
    final token = partes['access_token'];
    if (partes['type'] == 'recovery' && token != null && token.isNotEmpty) {
      return LinkRecuperacao._(token: token);
    }
    // Link vencido ou já usado: o Supabase manda o erro no mesmo fragmento.
    final erro = partes['error_code'] ?? partes['error'];
    if (erro != null && erro.isNotEmpty && (partes['type'] == 'recovery' || erro == 'otp_expired' || erro == 'access_denied')) {
      return const LinkRecuperacao._(expirado: true);
    }
    return null;
  }

  static Map<String, String> _parametros(Uri uri) {
    final fragmento = uri.fragment.startsWith('/') ? uri.fragment.substring(1) : uri.fragment;
    Map<String, String> ler(String texto) {
      try {
        return Uri.splitQueryString(texto);
      } on FormatException {
        return const {};
      }
    }

    return {...uri.queryParameters, ...ler(fragmento)};
  }

  @override
  String toString() => 'LinkRecuperacao(${token == null ? 'sem token' : 'token oculto'}, expirado: $expirado)';
}
