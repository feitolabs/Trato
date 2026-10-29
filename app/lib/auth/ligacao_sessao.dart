import 'dart:async';

import '../dados/sessao.dart';
import 'servico_auth.dart';

/// Leva o token do login para o [SessaoTrato] (que o cliente HTTP lê a cada chamada).
/// Ao entrar ou renovar, grava; ao sair, limpa. Não guarda nem registra o token em lugar nenhum.
class LigacaoSessao {
  LigacaoSessao(this._auth, this._sessao) {
    _atualizar(_auth.sessaoAtual);
    _inscricao = _auth.sessaoMudou.listen(_atualizar);
  }

  final ServicoAuth _auth;
  final SessaoTrato _sessao;
  StreamSubscription<SessaoAuth?>? _inscricao;

  void _atualizar(SessaoAuth? quem) {
    final token = quem == null ? null : _auth.tokenAtual;
    if (token == null || token.isEmpty) {
      _sessao.sair();
    } else {
      _sessao.entrar(token);
    }
  }

  Future<void> encerrar() async {
    await _inscricao?.cancel();
    _sessao.sair();
  }
}
