import 'dart:async';
import 'dart:convert';

/// Sessão do usuário. Guarda só o token que o serviço de login entrega; quem faz o login
/// (`ServicoAuth`) chama [entrar]/[sair]. Nunca grava token em código ou log.
class SessaoTrato {
  String? _token;

  /// Chamado quando a API recusa o token (401). Quem monta o app liga isto ao login.
  void Function()? aoExpirar;

  /// A API respondeu 403 `conta_bloqueada`: a pessoa continua logada, mas só entra no
  /// atendimento e nas medidas. Pode ser chamado várias vezes (chamadas em paralelo).
  void Function(String? mensagem)? aoBloquear;

  /// A API respondeu 403 `conta_inativa` (Termos 4.9): a pessoa continua logada para reativar
  /// gratuitamente ou falar com o atendimento. Pode ser chamado várias vezes em paralelo.
  void Function(String? mensagem)? aoInativar;

  /// Pede um token novo ao login. Devolve o token novo ou nulo. Quem monta o app liga isto ao
  /// serviço de login; sem ele, um 401 expira a sessão direto.
  Future<String?> Function()? renovar;

  String? get token => _token;

  /// Termos 14.3: dados do aparelho que vão nas chamadas com sessão. Vazio = não envia.
  Map<String, String> cabecalhosDoAparelho = const {};

  /// Envia `login`, `sessao_renovada` ou `logout` com o token dado. Quem monta o app liga.
  Future<void> Function(String evento, String token)? enviarAcesso;

  /// Quanto o app espera pelo aviso de acesso antes de seguir.
  Duration limiteDoAcesso = const Duration(seconds: 3);

  /// Uma tentativa, com tempo curto. Nunca lança: login e logout não dependem dela.
  Future<void> avisarAcesso(String evento, {String? token}) async {
    final enviar = enviarAcesso;
    final efetivo = token ?? _token;
    if (enviar == null || efetivo == null || efetivo.isEmpty) return;
    try {
      await enviar(evento, efetivo).timeout(limiteDoAcesso);
    } on Object {
      // Sem rede, servidor antigo ou lento: segue sem registro e sem log.
    }
  }

  /// Id do usuário (`sub` do token), só para separar o cache de leitura de cada conta. Nulo se o
  /// token não for um JWT legível. Não guarda nada.
  String? get usuarioId {
    final t = _token;
    if (t == null) return null;
    final partes = t.split('.');
    if (partes.length != 3) return null;
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))));
      final sub = json is Map ? json['sub'] : null;
      return sub is String && sub.isNotEmpty ? sub : null;
    } on Object {
      return null;
    }
  }

  /// Avisados ao sair (logout ou sessão expirada): ex. limpar o cache de leitura.
  final List<Future<void> Function()> aoSair = [];

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

  /// Sai da conta e espera a limpeza (cache de leitura) terminar.
  Future<void> sair() async {
    _token = null;
    await _avisarSaida();
  }

  Future<void> _avisarSaida() async {
    for (final f in List.of(aoSair)) {
      try {
        await f();
      } on Object {
        // limpeza é secundária: não impede o logout
      }
    }
  }

  /// A API respondeu 401: limpa o token e avisa uma vez só (várias chamadas em paralelo
  /// recebem 401 juntas).
  Future<void> expirar() async {
    if (!logada) return;
    _token = null; // já sem token: nenhuma chamada nova usa a sessão velha
    await _avisarSaida();
    aoExpirar?.call();
  }
}
