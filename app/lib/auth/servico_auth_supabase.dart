import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../dados/cliente_api.dart';
import '../dados/erros.dart';
import 'armazenamento_sessao.dart';
import 'config_auth.dart';
import 'controle_codigo_celular.dart';
import 'servico_auth.dart';

/// Link de retorno do e-mail de confirmação (deep link do app). Precisa estar na lista de URLs
/// de redirecionamento do painel do Supabase (docs/login-configuracao.md).
const kUrlRetornoEmail = 'br.com.feitolabs.trato://login-callback';

/// Login de verdade, pelo Supabase Auth. Precisa de [ConfigAuth] preenchida e dos
/// provedores ligados no painel (docs/login-configuracao.md).
/// Testado com cliente simulado (`test/servico_auth_supabase_test.dart`).
class ServicoAuthSupabase implements ServicoAuth {
  ServicoAuthSupabase(
    this._config, {
    sb.SupabaseClient? cliente,
    ControleCodigoCelular? codigo,
    ClienteApi? api,
  })  : _cliente = cliente ?? sb.Supabase.instance.client,
        _codigo = codigo ?? ControleCodigoCelular(),
        _api = api;

  /// Inicializa o Supabase. Chame no `main` antes de `runApp`, só se
  /// `config.supabaseConfigurado`. [api] é a API do Trato, que guarda o CPF (fora do login).
  static Future<ServicoAuthSupabase> inicializar(ConfigAuth config, {ClienteApi? api}) async {
    // Sessão no Keychain/Keystore, nunca em SharedPreferences (revisão M13).
    await sb.Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
      authOptions: sb.FlutterAuthClientOptions(
        localStorage: LocalStorageSeguro(chave: LocalStorageSeguro.chaveDaUrl(config.supabaseUrl)),
      ),
    );
    return ServicoAuthSupabase(config, api: api);
  }

  final ConfigAuth _config;
  final sb.SupabaseClient _cliente;
  final ControleCodigoCelular _codigo;
  final ClienteApi? _api;
  String? _cpfPendente;

  sb.GoTrueClient get _auth => _cliente.auth;

  @override
  bool provedorHabilitado(ProvedorAuth provedor) => switch (provedor) {
        ProvedorAuth.google => true,
        ProvedorAuth.apple => defaultTargetPlatform == TargetPlatform.iOS,
      };

  static SessaoAuth? _paraSessao(sb.User? u) => u == null
      ? null
      : SessaoAuth(
          id: u.id,
          email: u.email ?? '',
          nome: u.userMetadata?['nome'] as String?,
          celularConfirmado: u.phoneConfirmedAt != null,
          perfil: u.userMetadata?['perfil'] as String?,
        );

  @override
  SessaoAuth? get sessaoAtual => _paraSessao(_auth.currentUser);

  @override
  Stream<SessaoAuth?> get sessaoMudou =>
      _auth.onAuthStateChange.map((e) => _paraSessao(e.session?.user));

  @override
  String? get tokenAtual => _auth.currentSession?.accessToken;

  @override
  Future<String?> renovarToken() async {
    try {
      final r = await _auth.refreshSession();
      return r.session?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// "(31) 98765-4417" vira "+5531987654417".
  static String celularE164(String celular) => '+55${celular.replaceAll(RegExp(r'\D'), '')}';

  static String _digitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

  ErroAuth _deApi(ErroTrato erro) => erro.tipo == TipoErro.semInternet
      ? const ErroAuth(TipoErroAuth.semInternet)
      : ErroAuth(TipoErroAuth.dadosInvalidos, erro.mensagem);

  /// Antes de criar a conta: o backend diz se o CPF já pertence a outra conta.
  /// Sem API (modo demo), não há onde conferir nem gravar: o cadastro segue como antes.
  Future<void> _exigirCpfLivre(String cpf) async {
    final api = _api;
    if (api == null) return;
    try {
      final resposta = await api.post('/v1/cadastro/cpf', corpo: {'cpf': cpf});
      if (!(resposta is Map && resposta['disponivel'] == true)) {
        throw const ErroAuth(TipoErroAuth.cpfJaUsado);
      }
    } on ErroTrato catch (e) {
      throw _deApi(e);
    }
  }

  /// Depois do primeiro login: grava o CPF uma única vez. Se já for de outra conta, desloga.
  /// Sem API (modo demo), não grava: o CPF fica só na tela.
  Future<void> _gravarCpf(String cpf, {String? token}) async {
    final api = _api;
    if (api == null) return;
    final acesso = token ?? _auth.currentSession?.accessToken;
    if (acesso == null || acesso.isEmpty) {
      throw const ErroAuth(TipoErroAuth.cpfNaoVerificado);
    }
    try {
      await api.post('/v1/me/dados-pessoais', corpo: {'cpf': cpf}, token: acesso);
    } on ErroTrato catch (e) {
      try {
        await _auth.signOut();
      } catch (_) {
        // Sem sessão para encerrar: o erro abaixo já impede de prosseguir.
      }
      if (e.codigoHttp == 409) throw const ErroAuth(TipoErroAuth.cpfJaUsado);
      throw _deApi(e);
    }
  }

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
    if (e is ErroTrato) {
      return e.tipo == TipoErro.semInternet
          ? const ErroAuth(TipoErroAuth.semInternet)
          : ErroAuth(TipoErroAuth.dadosInvalidos, e.mensagem);
    }
    if (e is SocketException || e is sb.AuthRetryableFetchException) {
      return const ErroAuth(TipoErroAuth.semInternet);
    }
    if (e is sb.AuthException) {
      final codigo = e.code ?? '';
      final msg = e.message.toLowerCase();
      if (codigo == 'invalid_credentials' || msg.contains('invalid login credentials')) {
        return const ErroAuth(TipoErroAuth.credenciaisInvalidas);
      }
      if (codigo == 'email_not_confirmed' || msg.contains('email not confirmed')) {
        return const ErroAuth(TipoErroAuth.emailNaoConfirmado);
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
      if (codigo == 'over_email_send_rate_limit') {
        return const ErroAuth(TipoErroAuth.limiteEmail);
      }
      if (codigo == 'over_sms_send_rate_limit' || codigo == 'over_request_rate_limit') {
        return const ErroAuth(TipoErroAuth.reenviosEsgotados);
      }
      if (codigo == 'validation_failed') return const ErroAuth(TipoErroAuth.dadosInvalidos);
      if (codigo == 'signup_disabled') return const ErroAuth(TipoErroAuth.cadastroDesativado);
      if (codigo == 'provider_disabled' || codigo == 'sms_send_failed') {
        return const ErroAuth(TipoErroAuth.provedorIndisponivel);
      }
    }
    final texto = e.toString();
    if (texto.contains('SocketException') || texto.contains('ClientException')) {
      return const ErroAuth(TipoErroAuth.semInternet);
    }
    // Só tipo e código, nunca a mensagem (pode ter e-mail ou telefone).
    debugPrint('Auth: erro não mapeado (${e.runtimeType}, código ${e is sb.AuthException ? e.code : '-'})');
    return const ErroAuth(TipoErroAuth.desconhecido);
  }

  Future<String> _resolverIdentificador(String identificador) async {
    final api = _api;
    if (api == null) throw const ErroAuth(TipoErroAuth.credenciaisInvalidas);
    try {
      final resposta = await api.post(
        '/v1/cadastro/identificador',
        corpo: {'identificador': _digitos(identificador)},
      );
      final email = resposta is Map ? resposta['email'] as String? : null;
      if (email == null || email.isEmpty) {
        throw const ErroAuth(TipoErroAuth.credenciaisInvalidas);
      }
      return email;
    } on ErroTrato catch (e) {
      if (e.tipo == TipoErro.semInternet) {
        throw const ErroAuth(TipoErroAuth.semInternet);
      }
      throw const ErroAuth(TipoErroAuth.credenciaisInvalidas);
    }
  }

  @override
  Future<SessaoAuth> entrarComEmail({required String email, required String senha}) =>
      _proteger(() async {
        final limpo = email.trim();
        final emailLogin = limpo.contains('@') ? limpo : await _resolverIdentificador(limpo);
        final r = await _auth.signInWithPassword(email: emailLogin, password: senha);
        final pendente = _cpfPendente;
        _cpfPendente = null;
        if (pendente != null && pendente.isNotEmpty && r.session != null) {
          try {
            await _gravarCpf(pendente, token: r.session!.accessToken);
          } on Object {
            // Se falhar, não impede o login.
          }
        }
        return _paraSessao(r.user) ?? (throw const ErroAuth(TipoErroAuth.desconhecido));
      });

  @override
  Future<ResultadoCadastro> criarConta(DadosCadastro dados) => _proteger(() async {
        final cpf = _digitos(dados.cpf);
        // Um CPF, uma conta: confere antes de criar a conta no Auth.
        await _exigirCpfLivre(cpf);
        final r = await _auth.signUp(
          email: dados.email.trim(),
          password: dados.senha,
          emailRedirectTo: kUrlRetornoEmail,
          // Metadados do usuário: não exigem sessão (nada de updateUser/SMS, D16).
          // O CPF NÃO vai aqui: iria no token. O backend grava depois do login.
          data: {
            'nome': dados.nome,
            'celular': celularE164(dados.celular),
            if (dados.perfil != null) 'perfil': dados.perfil,
            'termos_aceitos': dados.termosAceitos,
            'termos_aceitos_em': DateTime.now().toUtc().toIso8601String(),
            'termos_versao': '1.0',
          },
        );
        // Com confirmação de e-mail ligada, e-mail repetido volta sem erro e sem identidades.
        if (r.user?.identities?.isEmpty ?? false) {
          throw const ErroAuth(TipoErroAuth.emailJaUsado);
        }
        if (r.user != null && _api != null) {
          try {
            await _api.post(
              '/v1/cadastro/vincular',
              corpo: {
                'usuario_id': r.user!.id,
                'email': dados.email.trim(),
                'nome': dados.nome,
                'cpf': cpf,
                'telefone': celularE164(dados.celular),
              },
            );
          } on Object catch (e) {
            debugPrint('Aviso: vincular_cadastro falhou: $e');
          }
        }
        final sessao = r.session == null ? null : _paraSessao(r.user);
        if (sessao != null) {
          await _gravarCpf(cpf, token: r.session!.accessToken);
          return CadastroComSessao(sessao);
        }
        _cpfPendente = cpf;
        return CadastroAguardandoEmail(dados.email.trim());
      });

  @override
  Future<bool> cpfDisponivel(String cpf) => _proteger(() async {
        final api = _api;
        if (api == null) return true; // modo demo: sem backend, não há o que conferir
        try {
          final resposta = await api.post(
            '/v1/cadastro/cpf',
            corpo: {'cpf': _digitos(cpf)},
          );
          return resposta is Map && resposta['disponivel'] == true;
        } on ErroTrato catch (e) {
          throw _deApi(e);
        }
      });

  @override
  Future<void> registrarCpf(String cpf) => _proteger(() {
        _cpfPendente = null;
        return _gravarCpf(_digitos(cpf));
      });

  @override
  Future<void> reenviarEmailConfirmacao(String email) =>
      _proteger(() => _auth.resend(
            type: sb.OtpType.signup,
            email: email.trim(),
            emailRedirectTo: kUrlRetornoEmail,
          ));

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
      serverClientId: _config.googleWebClientId.isEmpty ? null : _config.googleWebClientId,
    );
    final GoogleSignInAccount? conta;
    try {
      conta = await google.signIn();
    } on Object catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('canceled') || msg.contains('cancelled') || msg.contains('sign_in_canceled')) {
        throw const ErroAuth(TipoErroAuth.cancelado);
      }
      throw const ErroAuth(TipoErroAuth.provedorIndisponivel);
    }
    if (conta == null) throw const ErroAuth(TipoErroAuth.cancelado);
    final aut = await conta.authentication;
    final idToken = aut.idToken;
    if (idToken == null) throw const ErroAuth(TipoErroAuth.provedorIndisponivel);
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
