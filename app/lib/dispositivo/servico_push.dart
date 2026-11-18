import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Token nativo (FCM no Android, APNs/FCM no iOS) obtido via canal nativo do aparelho.
class TokenPushDispositivo {
  const TokenPushDispositivo({required this.token, required this.plataforma});

  /// Token opaco do provedor de push.
  final String token;

  /// `android`, `ios` ou `web` (aceitos em `POST /v1/dispositivos`).
  final String plataforma;
}

/// Integração com o serviço nativo de push (FCM / APNs) sem amarrar o código ao SDK.
abstract interface class ServicoPush {
  Future<TokenPushDispositivo?> obterToken();
  Stream<TokenPushDispositivo> get aoAtualizarToken;
  String? get ultimoTokenRegistrado;
  set ultimoTokenRegistrado(String? valor);
}

/// Implementação via [MethodChannel] (`br.com.feitolabs.trato/push`).
/// Se o projeto nativo ainda não expuser o manipulador ou não tiver `google-services.json`,
/// captura [MissingPluginException] / [PlatformException] e retorna `null` sem falhar.
class ServicoPushNativo implements ServicoPush {
  ServicoPushNativo({
    MethodChannel? canal,
    String Function()? plataformaAtual,
  })  : _canal = canal ?? const MethodChannel('br.com.feitolabs.trato/push'),
        _plataformaAtual = plataformaAtual ?? _plataformaPadrao {
    _canal.setMethodCallHandler(_tratarChamadaNativa);
  }

  final MethodChannel _canal;
  final String Function() _plataformaAtual;
  final _controlador = StreamController<TokenPushDispositivo>.broadcast();

  @override
  String? ultimoTokenRegistrado;

  static String _plataformaPadrao() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => kIsWeb ? 'web' : 'android',
      };

  Future<void> _tratarChamadaNativa(MethodCall chamada) async {
    if (chamada.method == 'tokenAtualizado') {
      final bruto = chamada.arguments;
      String? valor;
      String? plataforma;
      if (bruto is String) {
        valor = bruto;
      } else if (bruto is Map) {
        valor = bruto['token'] as String?;
        plataforma = bruto['plataforma'] as String?;
      }
      final limpo = valor?.trim() ?? '';
      if (limpo.length >= 8) {
        _controlador.add(
          TokenPushDispositivo(
            token: limpo,
            plataforma: plataforma ?? _plataformaAtual(),
          ),
        );
      }
    }
  }

  @override
  Future<TokenPushDispositivo?> obterToken() async {
    try {
      final resposta = await _canal.invokeMethod<Object?>('obterTokenPush');
      String? valor;
      String? plataforma;
      if (resposta is String) {
        valor = resposta;
      } else if (resposta is Map) {
        valor = resposta['token'] as String?;
        plataforma = resposta['plataforma'] as String?;
      }
      final limpo = valor?.trim() ?? '';
      if (limpo.length < 8) return null;
      return TokenPushDispositivo(
        token: limpo,
        plataforma: plataforma ?? _plataformaAtual(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<TokenPushDispositivo> get aoAtualizarToken => _controlador.stream;
}

/// Implementação fake para testes e modo demonstração.
class ServicoPushFake implements ServicoPush {
  ServicoPushFake({this.tokenInicial});

  final TokenPushDispositivo? tokenInicial;
  final _controlador = StreamController<TokenPushDispositivo>.broadcast();

  @override
  String? ultimoTokenRegistrado;

  void emitirNovoToken(TokenPushDispositivo novo) => _controlador.add(novo);

  @override
  Future<TokenPushDispositivo?> obterToken() async => tokenInicial;

  @override
  Stream<TokenPushDispositivo> get aoAtualizarToken => _controlador.stream;
}
