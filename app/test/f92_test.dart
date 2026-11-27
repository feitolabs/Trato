import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/tela_nao_encontrada.dart';
import 'package:trato/dispositivo/toque_push.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/comuns/aviso_push.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/navegacao_casca.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _uuid = '3f2b8c1e-9a4d-4e7b-8c55-0d6f1a2b3c4d';

class _Rotas extends NavigatorObserver {
  var empilhadas = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      empilhadas++;
}

MensagemPush _push(Map<String, dynamic> dados,
        {String? titulo, String? corpo}) =>
    MensagemPush(titulo: titulo, corpo: corpo, dados: dados);

/// Fakes dos três pontos de entrada do Firebase.
class _Fakes {
  final aberta = StreamController<MensagemPush>.broadcast();
  final primeiroPlano = StreamController<MensagemPush>.broadcast();
  MensagemPush? inicial;
  var firebaseOk = true;
  var inicialFalha = false;

  ServicoToquePush servico() => ServicoToquePush(
        garantirFirebase: () async => firebaseOk,
        mensagemInicial: () async {
          if (inicialFalha) throw Exception('sem firebase');
          return inicial;
        },
        aoAbrirPeloToque: () => aberta.stream,
        aoChegarComAppAberto: () => primeiroPlano.stream,
      );
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() {
    ligarDemoNosTestes();
    DeepLinks.esquecer();
    ControladorCasca.aoCascaPronta = DeepLinks.aoCascaPronta;
  });
  tearDown(() {
    DeepLinks.esquecer();
    DeepLinks.navegador = () => null;
    RotasTrato.repos = repositoriosDemo();
  });

  group('data do push -> destino (mesma tabela da caixa de notificações)', () {
    test('cada tela do backend', () {
      for (final (tela, destino) in [
        ('orcamentos', DestinoApp.orcamentos),
        ('pedido', DestinoApp.pedido),
        ('pedido_aberto', DestinoApp.pedidoAberto),
        ('avaliacao', DestinoApp.avaliacao),
        ('disputa', DestinoApp.disputa),
        ('mensagens', DestinoApp.chat),
      ]) {
        expect(
          resultadoDoPush({'tela': tela, 'pedido_id': _uuid, 'evento': 'x'}),
          ResultadoLink.valido(destino, _uuid),
          reason: tela,
        );
      }
    });

    test('recorrências: id da série, ou a lista quando não vem', () {
      expect(resultadoDoPush({'tela': 'recorrencias', 'recorrencia_id': _uuid}),
          const ResultadoLink.valido(DestinoApp.recorrencia, _uuid));
      expect(resultadoDoPush({'tela': 'recorrencias'}),
          const ResultadoLink.valido(DestinoApp.recorrencia, null));
    });

    test('tela desconhecida, ausente ou de outro tipo: ignorada', () {
      for (final d in <Map<String, dynamic>>[
        {'tela': 'admin', 'pedido_id': _uuid},
        {'pedido_id': _uuid},
        {'tela': 7, 'pedido_id': _uuid},
        {'tela': null},
        {},
        {'tela': 'pedido'}, // sem id: nada para abrir
        {'tela': 'pedido', 'pedido_id': ''},
        {'tela': 'pedido', 'pedido_id': 12345},
      ]) {
        expect(resultadoDoPush(d), ResultadoLink.ignorado, reason: '$d');
      }
    });

    test('id inválido: "não encontrado"', () {
      for (final ruim in ['../x', 'a b', 'a' * 65, '<script>']) {
        expect(resultadoDoPush({'tela': 'pedido', 'pedido_id': ruim}).situacao,
            SituacaoLink.invalido,
            reason: ruim);
      }
    });

    test('a chave link (esquema antigo) e qualquer outra é descartada', () {
      expect(
        resultadoDoPush({
          'tela': 'pedido',
          'pedido_id': _uuid,
          'link': 'https://evil.example/x',
          'url': 'javascript:alert(1)',
        }),
        const ResultadoLink.valido(DestinoApp.pedido, _uuid),
      );
      // Só o link, sem tela: nada abre.
      expect(resultadoDoPush({'link': 'trato://pedido/$_uuid'}),
          ResultadoLink.ignorado);
    });
  });

  group('ligação com o Firebase (fakes)', () {
    test('inicial, toque em segundo plano e primeiro plano chegam a quem pediu',
        () async {
      final f = _Fakes()..inicial = _push({'tela': 'pedido', 'pedido_id': 'a'});
      final toques = <MensagemPush>[], chegadas = <MensagemPush>[];
      await f.servico().ligar(aoToque: toques.add, aoChegar: chegadas.add);
      expect(toques.length, 1, reason: 'app fechado: getInitialMessage');
      f.aberta.add(_push({'tela': 'chat'}));
      f.primeiroPlano.add(_push({'tela': 'x'}, titulo: 'T'));
      await Future<void>.delayed(Duration.zero);
      expect(toques.length, 2, reason: 'segundo plano: onMessageOpenedApp');
      expect(chegadas.length, 1, reason: 'primeiro plano: onMessage');
    });

    test('Firebase indisponível ou com falha: nada acontece, sem erro',
        () async {
      final sem = _Fakes()..firebaseOk = false;
      var chamou = 0;
      await sem
          .servico()
          .ligar(aoToque: (_) => chamou++, aoChegar: (_) => chamou++);
      sem.aberta.add(_push({}));
      await Future<void>.delayed(Duration.zero);
      expect(chamou, 0);

      final falha = _Fakes()..inicialFalha = true;
      await falha
          .servico()
          .ligar(aoToque: (_) => chamou++, aoChegar: (_) => chamou++);
      expect(chamou, 0);
    });

    test('quem trata a mensagem falhar não derruba a ligação', () async {
      final f = _Fakes();
      var depois = 0;
      await f.servico().ligar(
            aoToque: (m) =>
                m.dados.isEmpty ? throw StateError('boom') : depois++,
            aoChegar: (_) {},
          );
      f.aberta.add(_push({}));
      f.aberta.add(_push({'a': 'b'}));
      await Future<void>.delayed(Duration.zero);
      expect(depois, 1);
    });
  });

  Future<(GlobalKey<NavigatorState>, GlobalKey<ScaffoldMessengerState>, _Rotas)>
      abrirCasca(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final auth = ServicoAuthFake();
    await entrarNaContaDeTeste(auth, email: 'ana@exemplo.com');
    ServicoAuthPadrao.atual = auth;
    final chave = GlobalKey<NavigatorState>();
    final msg = GlobalKey<ScaffoldMessengerState>();
    final obs = _Rotas();
    DeepLinks.navegador = () => chave.currentState;
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      navigatorKey: chave,
      scaffoldMessengerKey: msg,
      navigatorObservers: [obs],
      home: const CascaClienteTela(),
    ));
    await t.pumpAndSettle();
    return (chave, msg, obs);
  }

  group('o toque navega', () {
    testWidgets('app FECHADO: a mensagem inicial abre o destino', (t) async {
      final (_, _, obs) = await abrirCasca(t);
      final f = _Fakes()
        ..inicial = _push({'tela': 'pedido', 'pedido_id': 'srv-pintura'});
      final antes = obs.empilhadas;
      await f.servico().ligar(
          aoToque: (m) => DeepLinks.receberPush(m.dados), aoChegar: (_) {});
      await t.pumpAndSettle();
      expect(obs.empilhadas, antes + 1);
      expect(LinkPendente.atual, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('SEGUNDO PLANO: onMessageOpenedApp abre o destino (chat)',
        (t) async {
      final (_, _, obs) = await abrirCasca(t);
      final f = _Fakes();
      await f.servico().ligar(
          aoToque: (m) => DeepLinks.receberPush(m.dados), aoChegar: (_) {});
      final antes = obs.empilhadas;
      f.aberta.add(_push({'tela': 'mensagens', 'pedido_id': 'srv-pintura'}));
      await t.pumpAndSettle();
      expect(obs.empilhadas, antes + 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('tela desconhecida: não navega e não quebra', (t) async {
      final (_, _, obs) = await abrirCasca(t);
      final antes = obs.empilhadas;
      DeepLinks.receberPush(
          {'tela': 'qualquer_coisa', 'pedido_id': 'srv-pintura'});
      DeepLinks.receberPush({'link': 'trato://pedido/x'});
      DeepLinks.receberPush({'tela': 5});
      await t.pumpAndSettle();
      expect(obs.empilhadas, antes);
      expect(LinkPendente.atual, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('id inválido: "Ops, não encontramos isso"', (t) async {
      await abrirCasca(t);
      DeepLinks.receberPush({'tela': 'pedido', 'pedido_id': '../admin'});
      await t.pumpAndSettle();
      expect(find.byType(TelaNaoEncontrada), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('sem navegador (partida a frio): espera sem quebrar',
        (t) async {
      DeepLinks.navegador = () => null;
      DeepLinks.receberPush({'tela': 'pedido', 'pedido_id': 'srv-pintura'});
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 100));
      expect(LinkPendente.atual, isNotNull,
          reason: 'guardado em memória até haver navegador');
      expect(t.takeException(), isNull);
    });

    testWidgets('deslogado: vai ao login e, depois de entrar, abre o destino',
        (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final auth = ServicoAuthFake();
      ServicoAuthPadrao.atual = auth;
      final chave = GlobalKey<NavigatorState>();
      DeepLinks.navegador = () => chave.currentState;
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        navigatorKey: chave,
        home: const Scaffold(body: Text('splash')),
      ));
      DeepLinks.receberPush({'tela': 'disputa', 'pedido_id': 'srv-pintura'});
      await t.pumpAndSettle();
      expect(find.byType(LoginTela), findsOneWidget);
      expect(LinkPendente.atual, isNotNull);

      await entrarNaContaDeTeste(auth, email: 'ana@exemplo.com');
      chave.currentState!.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const CascaClienteTela()),
        (_) => false,
      );
      await t.pumpAndSettle();
      expect(LinkPendente.atual, isNull);
      expect(find.byType(LoginTela), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('sair da conta esquece o destino guardado', (t) async {
      DeepLinks.receberPush({'tela': 'pedido', 'pedido_id': 'srv-pintura'});
      expect(LinkPendente.atual, isNotNull);
      DeepLinks.esquecer();
      expect(LinkPendente.atual, isNull);
    });
  });

  group('app ABERTO (primeiro plano): aviso dentro do app', () {
    testWidgets('mostra título e corpo, toque navega e some em ~5 s',
        (t) async {
      final (chave, _, obs) = await abrirCasca(t);
      final antes = obs.empilhadas;
      AvisoPush.mostrar(
        _push({'tela': 'pedido', 'pedido_id': 'srv-pintura'},
            titulo: 'Novo orçamento', corpo: 'Você recebeu um orçamento.'),
        navegador: () => chave.currentState,
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Novo orçamento'), findsOneWidget);
      expect(find.text('Você recebeu um orçamento.'), findsOneWidget);
      await t.tap(find.text('Novo orçamento'));
      await t.pumpAndSettle();
      expect(obs.empilhadas, antes + 1);
      expect(find.text('Novo orçamento'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('sem toque, o aviso some sozinho em 5 s', (t) async {
      final (chave, _, _) = await abrirCasca(t);
      AvisoPush.mostrar(
          _push({'tela': 'pedido', 'pedido_id': 'a'}, titulo: 'Oi'),
          navegador: () => chave.currentState);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Oi'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Oi'), findsNothing);
    });

    testWidgets(
        'mensagem só de dados: nada aparece; tela desconhecida: sem botão Abrir',
        (t) async {
      final (chave, _, _) = await abrirCasca(t);
      AvisoPush.mostrar(_push({'tela': 'pedido', 'pedido_id': 'a'}),
          navegador: () => chave.currentState);
      await t.pump();
      expect(find.byKey(const Key('aviso-push')), findsNothing);
      AvisoPush.mostrar(_push({'tela': 'x'}, titulo: 'Aviso'), navegador: () => chave.currentState);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Aviso'), findsOneWidget);
      expect(find.text('Abrir'), findsNothing);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
