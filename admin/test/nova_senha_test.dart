import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/app.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/recuperacao_senha.dart';

import 'apoio/api_fake.dart';

Future<void> abrir(WidgetTester tester, ApiFake api, {LinkRecuperacao? link}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(PainelApp(api: api, linkRecuperacao: link));
  await tester.pumpAndSettle();
}

LinkRecuperacao? linkDe(String fragmento) => LinkRecuperacao.deUri(Uri.parse('https://painel.teste/#$fragmento'));

void main() {
  group('leitura do link', () {
    test('token de recovery no fragmento', () {
      final l = linkDe('access_token=abc.def&expires_in=3600&refresh_token=x&token_type=bearer&type=recovery');
      expect(l?.token, 'abc.def');
      expect(l?.expirado, isFalse);
      expect(l.toString(), isNot(contains('abc.def')));
    });

    test('erro de link vencido no fragmento', () {
      final l = linkDe('error=access_denied&error_code=otp_expired&error_description=expired');
      expect(l?.expirado, isTrue);
      expect(l?.token, isNull);
    });

    test('URL comum não é link de recovery', () {
      expect(LinkRecuperacao.deUri(Uri.parse('https://painel.teste/')), isNull);
      expect(linkDe('access_token=abc&type=signup'), isNull);
    });
  });

  group('tela Definir nova senha', () {
    testWidgets('token válido: define a senha e volta ao login com aviso', (tester) async {
      final api = ApiFake();
      await abrir(tester, api, link: linkDe('access_token=${ApiFake.tokenValidoDeTeste}&type=recovery'));
      expect(find.text('Definir nova senha'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('nova-senha')), 'SenhaNova2026');
      await tester.enterText(find.byKey(const ValueKey('confirmar-senha')), 'SenhaNova2026');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Definir senha'));
      await tester.pumpAndSettle();

      expect(api.ultimaSenhaDefinida, 'SenhaNova2026');
      expect(api.ultimoTokenUsado, ApiFake.tokenValidoDeTeste);
      expect(find.text('Senha definida. Entre com a nova senha.'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
    });

    testWidgets('senha curta ou diferente bloqueia o botão', (tester) async {
      await abrir(tester, ApiFake(), link: linkDe('access_token=${ApiFake.tokenValidoDeTeste}&type=recovery'));
      await tester.enterText(find.byKey(const ValueKey('nova-senha')), 'curta');
      await tester.pump();
      expect(find.text('Use pelo menos 8 caracteres.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Definir senha')).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('nova-senha')), 'SenhaNova2026');
      await tester.enterText(find.byKey(const ValueKey('confirmar-senha')), 'Outra2026xx');
      await tester.pump();
      expect(find.text('As senhas não são iguais.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Definir senha')).onPressed, isNull);
    });

    testWidgets('token expirado: mostra o erro claro e mantém a tela', (tester) async {
      final api = ApiFake();
      await abrir(tester, api, link: linkDe('access_token=token-velho&type=recovery'));
      await tester.enterText(find.byKey(const ValueKey('nova-senha')), 'SenhaNova2026');
      await tester.enterText(find.byKey(const ValueKey('confirmar-senha')), 'SenhaNova2026');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Definir senha'));
      await tester.pumpAndSettle();
      expect(find.textContaining('expirou ou já foi usado'), findsOneWidget);
      expect(api.ultimaSenhaDefinida, isNull);
    });

    testWidgets('link que já chegou vencido leva ao login', (tester) async {
      await abrir(tester, ApiFake(), link: linkDe('error=access_denied&error_code=otp_expired'));
      expect(find.textContaining('expirou ou já foi usado'), findsOneWidget);
      await tester.tap(find.text('Voltar ao login'));
      await tester.pumpAndSettle();
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('Senha definida. Entre com a nova senha.'), findsNothing);
    });
  });

  group('Esqueci a senha', () {
    testWidgets('pede o link e mostra mensagem neutra', (tester) async {
      final api = ApiFake();
      await abrir(tester, api);
      await tester.tap(find.text('Esqueci a senha'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('esqueci-email')), 'alguem@exemplo.com');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Enviar link'));
      await tester.pumpAndSettle();
      expect(api.recuperacoesPedidas, ['alguem@exemplo.com']);
      expect(find.textContaining('Se esse e-mail tiver conta'), findsOneWidget);
    });
  });

  group('chamadas ao Auth', () {
    ApiAdminHttp criar(List<http.Request> chamadas, int status, [Object? corpo]) => ApiAdminHttp(
          urlApi: 'https://api.teste',
          urlSupabase: 'https://sb.teste',
          chaveAnonSupabase: 'chave-publica-de-teste',
          urlPublica: 'https://painel.teste',
          cliente: MockClient((req) async {
            chamadas.add(req);
            return http.Response(corpo == null ? '' : '$corpo', status, headers: {'content-type': 'application/json'});
          }),
        );

    test('recover envia e-mail e redirect_to do próprio painel', () async {
      final chamadas = <http.Request>[];
      await criar(chamadas, 200, '{}').pedirRecuperacaoSenha('a@b.com');
      expect(chamadas.single.url.path, '/auth/v1/recover');
      expect(chamadas.single.url.queryParameters['redirect_to'], 'https://painel.teste');
      expect(chamadas.single.body, contains('a@b.com'));
    });

    test('PUT /auth/v1/user leva o token só no Authorization e a senha no corpo', () async {
      final chamadas = <http.Request>[];
      await criar(chamadas, 200, '{}').definirNovaSenha('tok-1', 'SenhaNova2026');
      final c = chamadas.single;
      expect(c.method, 'PUT');
      expect(c.headers['Authorization'], 'Bearer tok-1');
      expect(c.url.toString(), isNot(contains('tok-1')));
      expect(c.body, contains('SenhaNova2026'));
    });

    test('401 vira link expirado; 422 vira senha fraca', () async {
      expect(
        () => criar([], 401, '{"msg":"invalid"}').definirNovaSenha('t', 'SenhaNova2026'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', contains('expirou'))),
      );
      expect(
        () => criar([], 422, '{"error_code":"weak_password"}').definirNovaSenha('t', 'abcdefgh'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', contains('fraca'))),
      );
    });
  });
}
