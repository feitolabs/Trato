import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'servico_push.dart';

/// Inicializa o Firebase com segurança na subida do app.
/// Em modo demonstração, testes unitários ou ambiente sem configuração nativa,
/// captura a falha e retorna `false` sem travar a abertura do app.
Future<bool> inicializarFirebaseComSeguranca({
  Future<void> Function()? inicializar,
  bool Function()? jaInicializado,
}) async {
  try {
    final pronto = jaInicializado != null ? jaInicializado() : Firebase.apps.isNotEmpty;
    if (pronto) return true;
    if (inicializar != null) {
      await inicializar();
    } else {
      await Firebase.initializeApp();
    }
    return true;
  } on Object {
    return false;
  }
}

/// Implementação de [ServicoPush] baseada em `firebase_core` e `firebase_messaging`.
/// Pede permissão de notificação (incluindo `POST_NOTIFICATIONS` no Android 13+),
/// obtém o token FCM e escuta atualizações em `onTokenRefresh`.
/// Falhas de Firebase ou rede retornam `null` e nunca travam login ou abertura do app.
class ServicoPushFirebase implements ServicoPush {
  ServicoPushFirebase({
    Future<bool> Function()? garantirFirebase,
    Future<bool> Function()? pedirPermissao,
    Future<String?> Function()? obterTokenFcm,
    Stream<String> Function()? streamTokenRefresh,
    String Function()? plataformaAtual,
  })  : _garantirFirebase = garantirFirebase ?? _garantirFirebasePadrao,
        _pedirPermissao = pedirPermissao ?? _pedirPermissaoPadrao,
        _obterTokenFcm = obterTokenFcm ?? _obterTokenFcmPadrao,
        _streamTokenRefresh = streamTokenRefresh ?? _streamTokenRefreshPadrao,
        _plataformaAtual = plataformaAtual ?? _plataformaPadrao;

  final Future<bool> Function() _garantirFirebase;
  final Future<bool> Function() _pedirPermissao;
  final Future<String?> Function() _obterTokenFcm;
  final Stream<String> Function() _streamTokenRefresh;
  final String Function() _plataformaAtual;

  final _controlador = StreamController<TokenPushDispositivo>.broadcast();
  StreamSubscription<String>? _inscricaoRefresh;

  @override
  String? ultimoTokenRegistrado;

  static Future<bool> _garantirFirebasePadrao() => inicializarFirebaseComSeguranca();

  static Future<bool> _pedirPermissaoPadrao() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // ignore: deprecated_member_use
  static Future<String?> _obterTokenFcmPadrao() => FirebaseMessaging.instance.getToken();

  // ignore: deprecated_member_use
  static Stream<String> _streamTokenRefreshPadrao() => FirebaseMessaging.instance.onTokenRefresh;

  static String _plataformaPadrao() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => kIsWeb ? 'web' : 'android',
      };

  void _escutarRefresh() {
    if (_inscricaoRefresh != null) return;
    try {
      _inscricaoRefresh = _streamTokenRefresh().listen(
        (token) {
          final limpo = token.trim();
          if (limpo.length >= 8 && !_controlador.isClosed) {
            _controlador.add(
              TokenPushDispositivo(
                token: limpo,
                plataforma: _plataformaAtual(),
              ),
            );
          }
        },
        onError: (Object _) {
          // Falha transitória do stream de refresh nunca derruba o app.
        },
      );
    } on Object {
      // Sem Firebase pronto neste ambiente.
    }
  }

  @override
  Future<TokenPushDispositivo?> obterToken() async {
    try {
      final pronto = await _garantirFirebase();
      if (!pronto) return null;
      _escutarRefresh();
      final permitido = await _pedirPermissao();
      if (!permitido) return null;
      final token = await _obterTokenFcm();
      final limpo = token?.trim() ?? '';
      if (limpo.length < 8) return null;
      return TokenPushDispositivo(
        token: limpo,
        plataforma: _plataformaAtual(),
      );
    } on Object {
      return null;
    }
  }

  @override
  Stream<TokenPushDispositivo> get aoAtualizarToken => _controlador.stream;

  Future<void> encerrar() async {
    await _inscricaoRefresh?.cancel();
    _inscricaoRefresh = null;
    await _controlador.close();
  }
}
