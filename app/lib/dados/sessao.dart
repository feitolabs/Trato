/// Sessão do usuário. Guarda só o token que o serviço de login entrega; quem faz o login
/// (`ServicoAuth`) chama [entrar]/[sair]. Nunca grava token em código ou log.
class SessaoTrato {
  String? _token;

  String? get token => _token;
  bool get logada => _token != null && _token!.isNotEmpty;

  void entrar(String token) => _token = token;
  void sair() => _token = null;
}
