import 'dart:async';

import '../dados/sessao.dart';
import 'servico_auth.dart';

/// Leva o token do login para o [SessaoTrato] (que o cliente HTTP lê a cada chamada).
/// Ao entrar ou renovar, grava; ao sair, limpa. Não guarda nem registra o token em lugar nenhum.
class LigacaoSessao {
  /// [aoEntrar] roda quando o login passa a ter token (primeiro login ou app reaberto com
  /// sessão guardada). O app usa para chamar `GET /v1/me`, que cria o usuário no backend.
  LigacaoSessao(this._auth, this._sessao, {this.aoEntrar}) {
    _atualizar(_auth.sessaoAtual);
    _inscricao = _auth.sessaoMudou.listen(_atualizar);
    _sessao.renovar = () async {
      final token = await _auth.renovarToken() ?? _auth.tokenAtual;
      if (token != null && token.isNotEmpty && token != _ultimoToken) {
        _ultimoToken = token;
        unawaited(_sessao.avisarAcesso('sessao_renovada', token: token));
      }
      return token;
    };
    _iniciada = true;
  }

  /// Falso enquanto lê a sessão já guardada: reabrir o app não é um login.
  var _iniciada = false;

  /// Último token já tratado, para a mesma renovação não ser avisada duas vezes.
  String? _ultimoToken;

  final ServicoAuth _auth;
  final SessaoTrato _sessao;
  final Future<void> Function()? aoEntrar;
  StreamSubscription<SessaoAuth?>? _inscricao;

  void _atualizar(SessaoAuth? quem) {
    final token = quem == null ? null : _auth.tokenAtual;
    if (token == null || token.isEmpty) {
      unawaited(_sessao.sair());
    } else {
      final jaEstava = _sessao.token == token;
      final anterior = _sessao.logada ? _sessao.usuarioId : null;
      final estavaLogada = _sessao.logada;
      _sessao.entrar(token);
      final novidade = token != _ultimoToken;
      _ultimoToken = token;
      // Outra conta por cima também é login.
      final login = _iniciada &&
          !jaEstava &&
          (!estavaLogada || (anterior != null && anterior != _sessao.usuarioId));
      if (_iniciada && !jaEstava && !login && novidade) {
        unawaited(_sessao.avisarAcesso('sessao_renovada', token: token));
      }
      // Falha aqui (sem rede, API fora) não derruba o login: a próxima chamada tenta de novo.
      final preparo = !jaEstava && aoEntrar != null
          ? aoEntrar!().catchError((Object _) {})
          : Future<void>.value();
      // O aviso de login espera o `GET /v1/me`, que cria o usuário no primeiro acesso.
      unawaited(preparo.whenComplete(() async {
        if (login && _sessao.logada) await _sessao.avisarAcesso('login', token: token);
      }));
    }
  }

  Future<void> encerrar() async {
    await _inscricao?.cancel();
    _sessao.renovar = null;
    await _sessao.sair();
  }
}
