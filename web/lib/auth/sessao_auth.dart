import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../dados/sessao.dart';

/// Mensagem de erro em português para a tela de login, a partir do erro do Supabase.
String mensagemErroLogin(Object erro) {
  if (erro is sb.AuthException) {
    final msg = erro.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Confirme seu e-mail para entrar.';
    }
    return erro.message;
  }
  return 'Não foi possível entrar agora. Confira sua conexão e tente de novo.';
}

/// Login real (Supabase Auth) ligado à [SessaoTrato] que a API usa para autenticar as chamadas.
class ServicoAuthWeb {
  ServicoAuthWeb(this.sessao) {
    final sessaoAtual = _cliente.auth.currentSession;
    if (sessaoAtual != null) sessao.entrar(sessaoAtual.accessToken);
    logado = ValueNotifier(sessaoAtual != null);
    _cliente.auth.onAuthStateChange.listen((estado) {
      final token = estado.session?.accessToken;
      if (token != null) {
        sessao.entrar(token);
      } else {
        sessao.sair();
      }
      logado.value = token != null;
    });
    sessao.renovar = () async {
      final nova = await _cliente.auth.refreshSession();
      return nova.session?.accessToken;
    };
  }

  final SessaoTrato sessao;
  sb.SupabaseClient get _cliente => sb.Supabase.instance.client;

  /// Verdadeiro com sessão Supabase ativa; muda sozinho ao entrar/sair.
  late final ValueNotifier<bool> logado;

  Future<void> entrarComEmail({required String email, required String senha}) async {
    await _cliente.auth.signInWithPassword(email: email, password: senha);
  }

  Future<void> sair() => _cliente.auth.signOut();
}
