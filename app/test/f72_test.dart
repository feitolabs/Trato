import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/estado_conexao.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/main.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EstadoConexao.marcarOnline();
  });
  tearDown(EstadoConexao.marcarOnline);

  group('Banner "Sem conexão com a internet"', () {
    testWidgets('começa oculto, aparece offline e some ao voltar online', (tester) async {
      final estado = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        MaterialApp(theme: TemaTrato.claro, home: Scaffold(body: BannerSemConexao(estado: estado))),
      );
      expect(find.text('Sem internet'), findsNothing);

      estado.value = false;
      await tester.pump();
      expect(find.text('Sem internet'), findsOneWidget);

      estado.value = true;
      await tester.pump();
      expect(find.text('Sem internet'), findsNothing);
    });

    testWidgets('"Tentar novamente" some com o banner e avisa quem recarrega', (tester) async {
      final estado = ValueNotifier<bool>(false);
      var recarregou = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: Scaffold(
            body: BannerSemConexao(estado: estado, aoTentarNovamente: () => recarregou++),
          ),
        ),
      );
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();
      expect(recarregou, 1);
      expect(estado.value, isTrue);
      expect(find.text('Sem internet'), findsNothing);
    });

    testWidgets('no app (TratoApp): aparece quando o sinal global cai', (tester) async {
      await tester.pumpWidget(const TratoApp());
      expect(find.text('Sem internet'), findsNothing);
      EstadoConexao.marcarOffline();
      await tester.pump();
      expect(find.text('Sem internet'), findsOneWidget);
      EstadoConexao.marcarOnline();
      await tester.pump();
      expect(find.text('Sem internet'), findsNothing);
    });
  });

  group('ClienteApi alimenta o sinal de internet', () {
    ClienteApi api(Future<http.Response> Function(http.Request) responder) => ClienteApi(
          urlBase: 'https://api.teste/',
          sessao: SessaoTrato(),
          intervaloBaseRetry: Duration.zero,
          cliente: MockClient(responder),
        );

    test('falha de rede marca offline e a próxima resposta marca online', () async {
      var cair = true;
      final cliente = api((_) async {
        if (cair) throw const SocketException('sem rede');
        return http.Response('{"ok": true}', 200, headers: {'content-type': 'application/json'});
      });
      expect(EstadoConexao.online.value, isTrue);

      await expectLater(cliente.get('/v1/pedidos'), throwsA(isA<ErroTrato>()));
      expect(EstadoConexao.online.value, isFalse);

      cair = false;
      expect(await cliente.get('/v1/pedidos'), {'ok': true});
      expect(EstadoConexao.online.value, isTrue);
    });

    test('resposta de erro do servidor (4xx/5xx) conta como online', () async {
      final cliente = api((_) async => http.Response('{"detail":"não"}', 409));
      EstadoConexao.marcarOffline();
      await expectLater(cliente.get('/v1/x'), throwsA(isA<ErroTrato>()));
      expect(EstadoConexao.online.value, isTrue);
    });
  });

  group('Compartilhar meu perfil (profissional)', () {
    Future<void> abrir(WidgetTester tester, {CompartilharTextoTeste? compartilhar}) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: PerfilPublicoTela(
            servico: ServicoPerfilPublicoFake(),
            compartilharPerfil: compartilhar,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sem o callback o botão não aparece (padrão não muda)', (tester) async {
      await abrir(tester);
      expect(find.text('Compartilhar meu perfil'), findsNothing);
    });

    testWidgets('compartilha o texto pronto com nome, categoria, cidade e convite', (tester) async {
      final enviados = <String>[];
      await abrir(tester, compartilhar: (t) async => enviados.add(t));
      await tester.tap(find.text('Compartilhar meu perfil'));
      await tester.pumpAndSettle();
      expect(enviados, hasLength(1));
      expect(enviados.single, contains('Trato'));
      expect(enviados.single, contains('contratar'));
      expect(find.textContaining('Texto copiado'), findsNothing);
    });

    testWidgets('sem compartilhamento no aparelho copia o texto e avisa', (tester) async {
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await abrir(tester, compartilhar: (_) async => throw StateError('indisponível'));
      await tester.tap(find.text('Compartilhar meu perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Texto copiado! Cole no WhatsApp para divulgar.'), findsOneWidget);
      expect(copiado, isNotNull);
      expect(copiado, contains('Trato'));
    });
  });
}

typedef CompartilharTextoTeste = Future<void> Function(String texto);
