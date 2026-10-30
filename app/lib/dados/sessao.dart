/// Sessão do usuário. Guarda só o token que o serviço de login entrega; quem faz o login
/// (`ServicoAuth`) chama [entrar]/[sair]. Nunca grava token em código ou log.
class SessaoTrato {
  String? _token;

  /// Chamado quando a API recusa o token (401). Quem monta o app liga isto ao login.
  void Function()? aoExpirar;

  /// Pede um token novo ao login. Devolve o token novo ou nulo. Quem monta o app liga isto ao
  /// serviço de login; sem ele, um 401 expira a sessão direto.
  Future<String?> Function()? renovar;

  String? get token => _token;
  bool get logada => _token != null && _token!.isNotEmpty;

  /// Tenta renovar o token (uma tentativa de cada vez, mesmo com várias chamadas em paralelo).
  Future<String?> renovarToken() {
    final pendente = _renovando;
    if (pendente != null) return pendente;
    final pedido = renovar;
    if (pedido == null) return Future.value();
    final futuro = pedido().then<String?>((novo) {
      if (novo != null && novo.isNotEmpty) _token = novo;
      return novo != null && novo.isNotEmpty ? novo : null;
    }, onError: (_) => null).whenComplete(() => _renovando = null);
    return _renovando = futuro;
  }

  Future<String?>? _renovando;

  void entrar(String token) => _token = token;
  void sair() => _token = null;

  /// A API respondeu 401: limpa o token e avisa uma vez só (várias chamadas em paralelo
  /// recebem 401 juntas).
  void expirar() {
    if (!logada) return;
    _token = null;
    aoExpirar?.call();
  }
}
