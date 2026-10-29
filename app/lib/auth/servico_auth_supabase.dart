import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'config_auth.dart';
import 'controle_codigo_celular.dart';
import 'servico_auth.dart';

/// Login de verdade, pelo Supabase Auth. Precisa de [ConfigAuth] preenchida e dos
/// provedores ligados no painel (docs/login-configuracao.md).
/// Não tem teste automático: depende do projeto Supabase real.
class ServicoAuthSupabase implements ServicoAuth {
  ServicoAuthSupabase(this._config, {sb.SupabaseClient? cliente, ControleCodigoCelular? codigo})
      : _cliente = cliente ?? sb.Supabase.instance.client,
        _codigo = codigo ?? ControleCodigoCelular();

  /// Inicializa o Supabase. Chame no `main` antes de `runApp`, só se
  /// `config.supabaseConfigurado`.
  static Future<ServicoAuthSupabase> inicializar(ConfigAuth config) async {
    await sb.Supabase.initialize(url: config.supabaseUrl, publishableKey: config.supabaseAnonKey);
    return ServicoAuthSupabase(config);
  }

  final ConfigAuth _config;
  final sb.SupabaseClient _cliente;
  final ControleCodigoCelular _codigo;

  sb.GoTrueClient get _auth => _cliente.auth;

  @override
  bool provedorHabilitado(ProvedorAuth provedor) => switch (provedor) {
        ProvedorAuth.google => _config.googleConfigurado,
        ProvedorAuth.apple => defaultTargetPlatform == TargetPlatform.iOS,
      };

  static SessaoAuth? _paraSessao(sb.User? u) => u == null
      ? null
      : SessaoAuth(
          id: u.id,
          email: u.email ?? '',
          nome: u.userMetadata?['nome'] as String?,
          celularConfirmado: u.phoneConfirmedAt != null,
        );

  @override
  SessaoAuth? get sessaoAtual => _paraSessao(_auth.currentUser);

  @override
  Stream<SessaoAuth?> get sessaoMudou =>
      _auth.onAuthStateChange.map((e) => _paraSessao(e.session?.user));

  /// "(31) 98765-4417" vira "+5531987654417".
  static String celularE164(String celular) => '+55${celular.replaceAll(RegExp(r'\D'), '')}';

  Future<T> _proteger<T>(Future<T> Function() acao) async {
    try {
      return await acao();
    } on ErroAuth {
      rethrow;
    } catch (e) {
      throw traduzirErro(e);
    }
  }

  /// Converte qualquer erro do Supabase ou da rede em [ErroAuth] com texto em português.
  @visibleForTesting
  static ErroAuth traduzirErro(Object e) {
    if (e is ErroAuth) return e;
    if (e is SocketException || e is sb.AuthRetryableFetchException) {
      return const ErroAuth(TipoErroAuth.semInternet);
    }
    if (e is sb.AuthException) {
      final codigo = e.code ?? '';
      final msg = e.message.toLowerCase();
      if (codigo == 'invalid_credentials' || msg.contains('invalid login credentials')) {
        return const ErroAuth(TipoErroAuth.credenciaisInvalidas);
      }
      if (codigo == 'user_already_exists' ||
          codigo == 'email_exists' ||
          codigo == 'phone_exists' ||
          msg.contains('already registered')) {
        return const ErroAuth(TipoErroAuth.emailJaUsado);
      }
      if (codigo == 'weak_password') return const ErroAuth(TipoErroAuth.senhaFraca);
      if (codigo == 'otp_expired' || msg.contains('invalid') && msg.contains('token')) {
        return const ErroAuth(TipoErroAuth.codigoInvalido);
      }
      if (codigo == 'over_sms_send_rate_limit' || codigo == 'over_request_rate_limit') {
        return const ErroAuth(TipoErroAuth.reenviosEsgotados);
      }
      if (codigo == 'provider_disabled' || codigo == 'sms_send_failed') {
        return const ErroAuth(TipoErroAuth.provedorIndisponivel);
      }
    }
    final texto = e.toString();
    if (texto.contains('SocketException') || texto.contains('ClientException')) {
      return const ErroAuth(TipoErroAuth.semInternet);
    }
    return const ErroAuth(TipoErroAuth.desconhecido);
  }

  @override
  Future<SessaoAuth> entrarComEmail({required String email, required String senha}) =>
      _proteger(() async {
        final r = await _auth.signInWithPassword(email: email.trim(), password: senha);
        return _paraSessao(r.user) ?? (throw const ErroAuth(TipoErroAuth.desconhecido));
      });

  @override
  Future<SessaoAuth> criarConta(DadosCadastro dados) => _proteger(() async {
        final r = await _auth.signUp(
          email: dados.email.trim(),
          password: dados.senha,
          data: {'nome': dados.nome},
        );
        // Com confirmação de e-mail ligada, e-mail repetido volta sem erro e sem identidades.
        if (r.user?.identities?.isEmpty ?? false) {
          throw const ErroAuth(TipoErroAuth.emailJaUsado);
        }
        // Pede o SMS: o Supabase manda o código para o celular e espera a confirmação.
        await _auth.updateUser(sb.UserAttributes(phone: celularE164(dados.celular)));
        _codigo.novoCadastro();
        return _paraSessao(r.user) ?? (throw const ErroAuth(TipoErroAuth.desconhecido));
      });

  @override
  Future<SessaoAuth> entrarComProvedor(ProvedorAuth provedor) => _proteger(() async {
        if (!provedorHabilitado(provedor)) {
          throw const ErroAuth(TipoErroAuth.provedorIndisponivel);
        }
        final r = switch (provedor) {
          ProvedorAuth.google => await _entrarGoogle(),
          ProvedorAuth.apple => await _entrarApple(),
        };
        return _paraSessao(r.user) ?? (throw const ErroAuth(TipoErroAuth.desconhecido));
      });

  Future<sb.AuthResponse> _entrarGoogle() async {
    final google = GoogleSignIn(
      clientId: _config.googleIosClientId.isEmpty ? null : _config.googleIosClientId,
      serverClientId: _config.googleWebClientId,
    );
    final conta = await google.signIn();
    if (conta == null) throw const ErroAuth(TipoErroAuth.cancelado);
    final aut = await conta.authentication;
    final idToken = aut.idToken;
    if (idToken == null) throw const ErroAuth(TipoErroAuth.desconhecido);
    return _auth.signInWithIdToken(
      provider: sb.OAuthProvider.google,
      idToken: idToken,
      accessToken: aut.accessToken,
    );
  }

  Future<sb.AuthResponse> _entrarApple() async {
    final acaso = Random.secure();
    final bruto = base64UrlEncode(List<int>.generate(32, (_) => acaso.nextInt(256)));
    final hash = sha256.convert(utf8.encode(bruto)).toString();
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hash,
      );
      final idToken = c.identityToken;
      if (idToken == null) throw const ErroAuth(TipoErroAuth.desconhecido);
      return await _auth.signInWithIdToken(
        provider: sb.OAuthProvider.apple,
        idToken: idToken,
        nonce: bruto,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      throw e.code == AuthorizationErrorCode.canceled
          ? const ErroAuth(TipoErroAuth.cancelado)
          : const ErroAuth(TipoErroAuth.desconhecido);
    }
  }

  @override
  Future<void> sair() => _proteger(() => _auth.signOut());

  @override
  Future<void> recuperarSenha(String email) =>
      _proteger(() => _auth.resetPasswordForEmail(email.trim()));

  @override
  Future<void> reenviarCodigoCelular(String celular) => _proteger(() async {
        _codigo.registrarReenvio();
        await _auth.resend(type: sb.OtpType.phoneChange, phone: celularE164(celular));
      });

  @override
  Future<SessaoAuth> confirmarCelular({required String celular, required String codigo}) =>
      _proteger(() async {
        _codigo.checarTentativa();
        try {
          final r = await _auth.verifyOTP(
            type: sb.OtpType.phoneChange,
            phone: celularE164(celular),
            token: codigo,
          );
          return _paraSessao(r.user ?? _auth.currentUser) ??
              (throw const ErroAuth(TipoErroAuth.desconhecido));
        } on sb.AuthException catch (e) {
          final erro = traduzirErro(e);
          if (erro.tipo == TipoErroAuth.codigoInvalido) throw _codigo.registrarErro();
          throw erro;
        }
      });
}
