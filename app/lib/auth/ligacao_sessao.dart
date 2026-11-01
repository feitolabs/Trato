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
      final novo = await _auth.renovarToken();
      return novo ?? _auth.tokenAtual;
    };
  }

  final ServicoAuth _auth;
  final SessaoTrato _sessao;
  final Future<void> Function()? aoEntrar;
  StreamSubscription<SessaoAuth?>? _inscricao;

  void _atualizar(SessaoAuth? quem) {
    final token = quem == null ? null : _auth.tokenAtual;
    if (token == null || token.isEmpty) {
      _sessao.sair();
    } else {
      final jaEstava = _sessao.token == token;
      _sessao.entrar(token);
      if (!jaEstava && aoEntrar != null) {
        // Falha aqui (sem rede, API fora) não derruba o login: a próxima chamada tenta de novo.
        unawaited(aoEntrar!().catchError((Object _) {}));
      }
    }
  }

  Future<void> encerrar() async {
    await _inscricao?.cancel();
    _sessao.renovar = null;
    _sessao.sair();
  }
}
