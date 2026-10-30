/// Sessão do usuário. Guarda só o token que o serviço de login entrega; quem faz o login
/// (`ServicoAuth`) chama [entrar]/[sair]. Nunca grava token em código ou log.
class SessaoTrato {
  String? _token;

  /// Chamado quando a API recusa o token (401). Quem monta o app liga isto ao login.
  void Function()? aoExpirar;

  String? get token => _token;
  bool get logada => _token != null && _token!.isNotEmpty;

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
