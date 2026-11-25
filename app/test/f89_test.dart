import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/tela_nao_encontrada.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/relato_bug.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/servico_ajuda_local.dart';
import 'package:trato/telas/comuns/relatar_bug.dart';
import 'package:trato/telas/disputa_profissional/atender_retrabalho_tela.dart';
import 'package:trato/telas/disputa_profissional/disputa.dart';
import 'package:trato/telas/disputa_profissional/responder_disputa_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/reagendamento.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/disputa_profissional/disputa_fake.dart';
import 'apoio/fontes.dart';

Future<void> _janela(WidgetTester t, {double fonte = 1}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

ClienteApi _api(http.Response Function(http.Request) responder) {
  final sessao = SessaoTrato()..entrar('valor-de-teste');
  return ClienteApi(
    urlBase: 'https://api.teste/',
    sessao: sessao,
    cliente: MockClient((req) async => responder(req)),
  );
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('1. Relatar bug', () {
    final quando = DateTime(2026, 11, 25, 9, 5);

    test(
        'o mailto leva assunto, versão, aparelho, tela e hora, sem dado pessoal',
        () {
      final r = montarRelatoBug((
        versao: '0.1.37+38',
        sistema: 'Android (14)',
        tela: 'Central de ajuda',
        quando: quando,
      ));
      expect(r.assunto, 'Relato de bug (app Trato)');
      expect(r.corpo, contains('O que aconteceu:'));
      expect(r.corpo, contains('O que eu esperava:'));
      expect(r.corpo, contains('Passos para repetir:'));
      expect(r.corpo, contains('Versão do app: 0.1.37+38'));
      expect(r.corpo, contains('Aparelho: Android (14)'));
      expect(r.corpo, contains('Tela: Central de ajuda'));
      expect(r.corpo, contains('25/11/2026 09:05'));
      expect(r.corpo, isNot(contains('@')));
      expect(r.corpo.toLowerCase(), isNot(contains('cpf')));
      expect(r.corpo.toLowerCase(), isNot(contains('token')));

      final uri = uriDoRelato(emailRelatoBug, r.assunto, r.corpo);
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'suporte@tratofeito.com.br');
      expect(uri.queryParameters['subject'], r.assunto);
      expect(uri.queryParameters['body'], r.corpo);
      expect(uri.toString(), isNot(contains('+')),
          reason: 'espaço sai como %20, não como "+"');
    });

    test('a versão do relato acompanha o pubspec', () {
      final linha = File('pubspec.yaml')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('version:'));
      expect(versaoDoApp, linha.substring('version:'.length).trim());
    });

    for (final fonte in [1.0, 1.3]) {
      testWidgets('Ajuda: "Relatar bug" abre o e-mail com o relato (x$fonte)',
          (t) async {
        await _janela(t, fonte: fonte);
        Uri? aberto;
        abrirEmailDoRelato = (u) async {
          aberto = u;
          return true;
        };
        addTearDown(() => abrirEmailDoRelato = (u) async => false);
        await t.pumpWidget(_app(Builder(
          builder: (c) => AjudaTela(
            servico: const ServicoAjudaLocal(),
            aoRelatarBug: () =>
                relatarBug(c, tela: 'Central de ajuda', agora: () => quando),
          ),
        )));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
            find.byKey(const Key('botao-relatar-bug')), 200,
            scrollable: find.byType(Scrollable).first);
        await t.tap(find.byKey(const Key('botao-relatar-bug')));
        await t.pumpAndSettle();
        expect(aberto, isNotNull);
        expect(aberto!.path, emailRelatoBug);
        expect(aberto!.queryParameters['body'],
            contains('Tela: Central de ajuda'));
        expect(find.byKey(const Key('dialogo-relato-bug')), findsNothing);
      });
    }

    testWidgets('sem app de e-mail: mostra o endereço e o botão Copiar',
        (t) async {
      await _janela(t, fonte: 1.3);
      abrirEmailDoRelato = (u) async => false;
      String? copiado;
      t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'Clipboard.setData') {
          copiado = (c.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await t.pumpWidget(_app(Builder(
        builder: (c) => TextButton(
          onPressed: () => relatarBug(c, tela: 'Configurações'),
          child: const Text('bug'),
        ),
      )));
      await t.tap(find.text('bug'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dialogo-relato-bug')), findsOneWidget);
      expect(find.text('suporte@tratofeito.com.br'), findsOneWidget);
      await t.tap(find.byKey(const Key('copiar-email-bug')));
      await t.pumpAndSettle();
      expect(copiado, 'suporte@tratofeito.com.br');
      expect(find.byKey(const Key('dialogo-relato-bug')), findsNothing);
    });

    testWidgets('Configurações (cliente e profissional) tem "Relatar bug"',
        (t) async {
      await _janela(t);
      for (final profissional in [false, true]) {
        late BuildContext ctx;
        await t.pumpWidget(_app(Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })));
        RotasTrato.abrirConfiguracoes(ctx, profissional: profissional);
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('Relatar bug'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Relatar bug'), findsOneWidget);
      }
    });
  });

  group('2. E-mail de suporte', () {
    test('os textos legais usam suporte@tratofeito.com.br', () {
      final termos = File('assets/legal/termos-de-uso.md').readAsStringSync();
      expect(termos, isNot(contains('suporte@trato.app.br')));
      expect(termos, contains('suporte@tratofeito.com.br'));
    });
  });

  group('3. Pedido pago sem horário: "Agendar" e "Aceitar horário"', () {
    Reagendamento proposta() => Reagendamento(
          id: 'r1',
          propostoPor: 'outro',
          inicio: DateTime.now().add(const Duration(days: 2)),
          fim: DateTime.now().add(const Duration(days: 2, hours: 2)),
        );

    Future<void> abrir(WidgetTester t,
            {required bool semHorario, bool comProposta = false}) =>
        t.pumpWidget(_app(Scaffold(
          body: SecaoReagendamento(
            semHorario: semHorario,
            meuId: 'eu',
            carregar: () async =>
                comProposta ? [proposta()] : <Reagendamento>[],
            propor: (a, b, c) async {},
            aceitar: (_) async {},
            recusar: (_) async {},
          ),
        )));

    for (final fonte in [1.0, 1.3]) {
      testWidgets('sem horário: botão "Agendar" (x$fonte)', (t) async {
        await _janela(t, fonte: fonte);
        await abrir(t, semHorario: true);
        await t.pumpAndSettle();
        expect(find.text('Agendar'), findsOneWidget);
        expect(find.text('Reagendar'), findsNothing);
      });

      testWidgets('sem horário, com proposta: "Aceitar horário" (x$fonte)',
          (t) async {
        await _janela(t, fonte: fonte);
        await abrir(t, semHorario: true, comProposta: true);
        await t.pumpAndSettle();
        expect(find.text('Aceitar horário'), findsOneWidget);
        expect(find.text('Aceitar nova data'), findsNothing);
        expect(find.text('Horário proposto'), findsOneWidget);
      });
    }

    testWidgets(
        'com horário marcado continua "Reagendar" e "Aceitar nova data"',
        (t) async {
      await _janela(t);
      await abrir(t, semHorario: false);
      await t.pumpAndSettle();
      expect(find.text('Reagendar'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await abrir(t, semHorario: false, comProposta: true);
      await t.pumpAndSettle();
      expect(find.text('Aceitar nova data'), findsOneWidget);
    });
  });

  group('4. Garantia mínima por categoria', () {
    Future<List<int>> minimas(Map<String, Object?> extra) async {
      final api = _api((_) => _json([
            {'id': 'a', 'nome': 'Elétrica', 'slug': 'eletrica', ...extra},
          ]));
      final cats = await RepositorioCatalogoApi(api).categorias();
      return [for (final c in cats) c.garantiaMinimaDias];
    }

    test('lê garantia_minima_dias (90 durável, 30 não durável)', () async {
      expect(await minimas({'garantia_minima_dias': 90}), [90]);
      expect(await minimas({'garantia_minima_dias': 30}), [30]);
    });

    test('campo ausente ou inválido: padrão seguro de 30', () async {
      expect(await minimas({}), [30]);
      expect(await minimas({'garantia_minima_dias': null}), [30]);
      expect(await minimas({'garantia_minima_dias': 0}), [30]);
      expect(await minimas({'garantia_minima_dias': 'x'}), [30]);
    });
  });

  group('5. 404 e 403 em disputa e retrabalho', () {
    test('a API não esconde 404 como "vazio"', () async {
      final servico = ServicoDisputaProfissionalApi(
          _api((_) => _json({'detail': 'x'}, 404)));
      await expectLater(
          servico.carregarDisputa('p1'),
          throwsA(isA<ErroTrato>()
              .having((e) => e.tipo, 'tipo', TipoErro.naoEncontrado)));
      await expectLater(
          servico.carregarRetrabalho('p1'),
          throwsA(isA<ErroTrato>()
              .having((e) => e.tipo, 'tipo', TipoErro.naoEncontrado)));
    });

    test('200 com lista vazia segue sendo "sem retrabalho"', () async {
      final servico =
          ServicoDisputaProfissionalApi(_api((_) => _json(<Object>[])));
      expect(await servico.carregarRetrabalho('p1'), isNull);
    });

    for (final fonte in [1.0, 1.3]) {
      testWidgets('disputa 404: mostra "Ops, não encontramos isso" (x$fonte)',
          (t) async {
        await _janela(t, fonte: fonte);
        await t.pumpWidget(_app(ResponderDisputaTela(
          servico:
              _Falha(const ErroTrato(TipoErro.naoEncontrado, 'Não existe.')),
          disputaId: 'p1',
        )));
        await t.pumpAndSettle();
        expect(find.byType(TelaNaoEncontrada), findsOneWidget);
        expect(find.text('Nenhum problema aberto'), findsNothing);
      });

      testWidgets(
          'retrabalho 403: mostra "Ops, não encontramos isso" (x$fonte)',
          (t) async {
        await _janela(t, fonte: fonte);
        await t.pumpWidget(_app(AtenderRetrabalhoTela(
          servico: _Falha(const ErroTrato(TipoErro.recusado, 'Sem acesso.',
              codigoHttp: 403)),
          disputaId: 'p1',
        )));
        await t.pumpAndSettle();
        expect(find.byType(TelaNaoEncontrada), findsOneWidget);
      });
    }

    testWidgets('resposta vazia legítima: "Nenhum problema aberto"', (t) async {
      await _janela(t);
      await t.pumpWidget(_app(ResponderDisputaTela(
        servico: ServicoDisputaProfissionalFake(),
        disputaId: 'p1',
      )));
      await t.pumpAndSettle();
      expect(find.text('Nenhum problema aberto'), findsOneWidget);
      expect(find.byType(TelaNaoEncontrada), findsNothing);
    });
  });
}

class _Falha extends ServicoDisputaProfissionalFake {
  _Falha(this.erro);
  final ErroTrato erro;

  @override
  Future<DetalheDisputa?> carregarDisputa(String disputaId) async => throw erro;

  @override
  Future<DadosRetrabalho?> carregarRetrabalho(String disputaId) async =>
      throw erro;
}
