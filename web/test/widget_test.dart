import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:trato_web/dados/config_web.dart';
import 'package:trato_web/main.dart';
import 'package:trato_web/telas/tela_sem_configuracao.dart';

/// Valores falsos: o domínio `.invalid` nunca resolve, então o teste não alcança nada real.
const _config = ConfigWeb(
  urlApi: 'https://api.exemplo.invalid',
  urlSupabase: 'https://supabase.exemplo.invalid',
  chaveAnon: 'chave-publica-falsa',
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await sb.Supabase.initialize(url: _config.urlSupabase, publishableKey: _config.chaveAnon);
  });

  testWidgets('Sem sessão, mostra a tela de login', (WidgetTester tester) async {
    await tester.pumpWidget(const TratoWebApp(config: _config));
    await tester.pump();

    expect(find.text('Entrar na sua conta'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('Sem configuração, a tela diz o que falta', (WidgetTester tester) async {
    await tester.pumpWidget(TelaSemConfiguracao(problemas: const ConfigWeb().problemas));

    expect(find.text('Site sem configuração'), findsOneWidget);
    expect(find.textContaining('TRATO_API_URL'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.textContaining('SUPABASE_ANON_KEY'), findsOneWidget);
  });

  group('ConfigWeb', () {
    ConfigWeb com({String? urlApi, String? chaveAnon}) => ConfigWeb(
          urlApi: urlApi ?? _config.urlApi,
          urlSupabase: _config.urlSupabase,
          chaveAnon: chaveAnon ?? _config.chaveAnon,
        );

    test('completa não tem problema', () => expect(_config.problemas, isEmpty));

    test('endereço: https ou a própria máquina', () {
      expect(com(urlApi: 'http://localhost:8000').problemas, isEmpty);
      expect(com(urlApi: 'http://api.exemplo.invalid').problemas, hasLength(1));
      expect(com(urlApi: 'api.exemplo.invalid').problemas, hasLength(1));
    });

    test('recusa chave secreta sem repetir o valor', () {
      final corpo = base64Url.encode(utf8.encode(jsonEncode({'role': 'service_role'})));
      for (final chave in ['sb_secret_falsa', 'cabecalho.$corpo.assinatura']) {
        final problemas = com(chaveAnon: chave).problemas;
        expect(problemas, hasLength(1));
        expect(problemas.single, isNot(contains(chave)));
      }
    });
  });
}
