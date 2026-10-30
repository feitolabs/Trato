import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Tudo que entra por `--dart-define` vai para dentro do APK/IPA. Só variáveis públicas passam
/// (revisão M14). A mesma lista está em `harness/verificar_defines.py`.
const definesPublicos = <String>{
  'TRATO_MODO',
  'TRATO_API_URL',
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'GOOGLE_WEB_CLIENT_ID',
  'GOOGLE_IOS_CLIENT_ID',
  'GALERIA',
};

/// Nomes que nunca podem estar no app, mesmo vazios no código: se vierem preenchidos, é erro.
const definesProibidos = <String>[
  'SUPABASE_SERVICE_ROLE_KEY',
  'SERVICE_ROLE',
  'SUPABASE_DB_URL',
  'DATABASE_URL',
  'SUPABASE_JWT_SECRET',
  'JWT_SECRET',
  'STRIPE_SECRET_KEY',
  'STRIPE_WEBHOOK_SECRET',
  'TRATO_CODIGO_SEGREDO',
];

/// O nome tem cara de segredo (`service_role`, `secret`, `sk_`, `JWT_SECRET`, `DATABASE_URL`)?
bool nomeComCaraDeSegredo(String nome) {
  final n = nome.toUpperCase();
  return n.contains('SERVICE_ROLE') ||
      n.contains('SECRET') ||
      n.contains('DATABASE_URL') ||
      n.contains('DB_URL') ||
      n.startsWith('SK_') ||
      n.contains('PRIVATE_KEY');
}

/// O valor tem cara de segredo? Chave `sk_`/`rk_`, ou JWT com papel `service_role`.
bool valorComCaraDeSegredo(String valor) {
  final v = valor.trim();
  if (RegExp(r'^(sk|rk)_(live|test)_').hasMatch(v) || v.startsWith('whsec_')) return true;
  final partes = v.split('.');
  if (partes.length == 3 && v.startsWith('eyJ')) {
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))));
      if (json is Map && json['role'] == 'service_role') return true;
    } on Object {
      // não é JWT legível: não é a chave service_role
    }
  }
  return false;
}

/// Confere as variáveis lidas do ambiente. Devolve os **nomes** com problema (nunca o valor).
List<String> defineSuspeitos(Map<String, String> valores) => [
      for (final e in valores.entries)
        if (e.value.isNotEmpty &&
            (nomeComCaraDeSegredo(e.key) ||
                !definesPublicos.contains(e.key) ||
                valorComCaraDeSegredo(e.value)))
          e.key,
    ];

/// Em debug, para o app com erro claro. Em release, devolve só as variáveis seguras
/// (a suspeita é ignorada).
Map<String, String> filtrarDefines(Map<String, String> valores) {
  final ruins = defineSuspeitos(valores);
  if (ruins.isNotEmpty && kDebugMode) {
    throw StateError(
      'Variável com cara de segredo em --dart-define: ${ruins.join(', ')}. '
      'Use só as públicas (docs/BUILD.md).',
    );
  }
  return {
    for (final e in valores.entries)
      if (!ruins.contains(e.key)) e.key: e.value,
  };
}

/// Lê do ambiente as variáveis públicas e as proibidas (estas só para detectar o erro).
Map<String, String> lerDefinesDoAmbiente() => const {
      'TRATO_MODO': String.fromEnvironment('TRATO_MODO'),
      'TRATO_API_URL': String.fromEnvironment('TRATO_API_URL'),
      'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
      'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
      'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      'GOOGLE_IOS_CLIENT_ID': String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
      'SUPABASE_SERVICE_ROLE_KEY': String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY'),
      'SUPABASE_DB_URL': String.fromEnvironment('SUPABASE_DB_URL'),
      'DATABASE_URL': String.fromEnvironment('DATABASE_URL'),
      'SUPABASE_JWT_SECRET': String.fromEnvironment('SUPABASE_JWT_SECRET'),
      'JWT_SECRET': String.fromEnvironment('JWT_SECRET'),
      'STRIPE_SECRET_KEY': String.fromEnvironment('STRIPE_SECRET_KEY'),
      'STRIPE_WEBHOOK_SECRET': String.fromEnvironment('STRIPE_WEBHOOK_SECRET'),
    };
