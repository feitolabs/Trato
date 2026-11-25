import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/tela_nao_encontrada.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/navegacao_casca.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _uuid = '3f2b8c1e-9a4d-4e7b-8c55-0d6f1a2b3c4d';
String _l(String caminho) => 'br.com.feitolabs.trato://$caminho';

class _Rotas extends NavigatorObserver {
  var empilhadas = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      empilhadas++;
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

  group('interpretar o link', () {
    test('cada tipo com id válido (uuid ou id curto)', () {
      for (final (host, destino) in [
        ('pedido', DestinoApp.pedido),
        ('orcamentos', DestinoApp.orcamentos),
        ('chat', DestinoApp.chat),
        ('recorrencia', DestinoApp.recorrencia),
        ('disputa', DestinoApp.disputa),
        (
          'avaliacao',
          DestinoApp.pedido
        ), // mesmo destino da notificação de avaliação
      ]) {
        expect(interpretarLink(Uri.parse(_l('$host/$_uuid'))),
            ResultadoLink.valido(destino, _uuid));
        expect(interpretarLink(Uri.parse(_l('$host/srv-1'))),
            ResultadoLink.valido(destino, 'srv-1'));
      }
      expect(interpretarLink(Uri.parse(_l('recorrencia'))),
          const ResultadoLink.valido(DestinoApp.recorrencia, null));
    });

    test('id inválido: nada de caminho, espaço, texto longo ou id faltando',
        () {
      for (final ruim in [
        'pedido/a%20b',
        'pedido/..%2Fadmin',
        'pedido/${'a' * 65}',
        'pedido/a/b',
        'pedido',
        'chat',
        'orcamentos/%3Cscript%3E',
        'disputa/a;b',
      ]) {
        final r = interpretarLink(Uri.parse(_l(ruim)));
        expect(r.situacao, SituacaoLink.invalido, reason: ruim);
        expect(r.id, isNull, reason: ruim);
      }
    });

    test('tipo desconhecido, outro esquema e login-callback são ignorados', () {
      for (final u in [
        _l('perfil/abc'),
        _l('/'),
        'https://trato.app/pedido/abc',
        _l('login-callback'),
        _l('login-callback#access_token=SEGREDO&type=recovery'),
        _l('login-callback?code=abc'),
        '/',
      ]) {
        expect(interpretarLink(Uri.parse(u)), ResultadoLink.ignorado,
            reason: u);
      }
    });

    test('o link não carrega dado pessoal: query e fragmento são descartados',
        () {
      final r = interpretarLink(
          Uri.parse(_l('pedido/$_uuid?email=a@b.com&token=x#y')));
      expect(r, const ResultadoLink.valido(DestinoApp.pedido, _uuid));
    });
  });

  group('com a pessoa logada', () {
    Future<(GlobalKey<NavigatorState>, _Rotas)> abrirCasca(
        WidgetTester t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final auth = ServicoAuthFake();
      await auth.entrarComEmail(email: 'ana@exemplo.com', senha: '12345678');
      ServicoAuthPadrao.atual = auth;
      final chave = GlobalKey<NavigatorState>();
      final obs = _Rotas();
      DeepLinks.navegador = () => chave.currentState;
      DeepLinks
          .ligar(); // antes do app, como no main: o ouvinte vem antes do WidgetsApp
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        navigatorKey: chave,
        navigatorObservers: [obs],
        home: const CascaClienteTela(),
      ));
      await t.pumpAndSettle();
      expect(ControladorCasca.ativa, isTrue);
      return (chave, obs);
    }

    for (final host in [
      'pedido',
      'orcamentos',
      'chat',
      'recorrencia',
      'disputa',
      'avaliacao'
    ]) {
      testWidgets('link "$host" abre uma tela por cima, sem erro', (t) async {
        final (_, obs) = await abrirCasca(t);
        final antes = obs.empilhadas;
        DeepLinks.receber(Uri.parse(_l('$host/srv-pintura')));
        await t.pumpAndSettle();
        expect(obs.empilhadas, antes + 1);
        expect(LinkPendente.atual, isNull,
            reason: 'o destino é limpo depois de abrir');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('id inválido mostra "Ops, não encontramos isso"', (t) async {
      await abrirCasca(t);
      DeepLinks.receber(Uri.parse(_l('pedido/..%2Fx')));
      await t.pumpAndSettle();
      expect(find.byType(TelaNaoEncontrada), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('tipo desconhecido e login-callback: nada abre, sem erro',
        (t) async {
      final (_, obs) = await abrirCasca(t);
      final antes = obs.empilhadas;
      DeepLinks.receber(Uri.parse(_l('perfil/abc')));
      DeepLinks.receber(Uri.parse(_l('login-callback#access_token=SEGREDO')));
      await t.pumpAndSettle();
      expect(obs.empilhadas, antes);
      expect(LinkPendente.atual, isNull);
      expect(find.byType(TelaNaoEncontrada), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('o sistema entrega o link (app aberto ou em segundo plano)',
        (t) async {
      final (_, obs) = await abrirCasca(t);
      final antes = obs.empilhadas;

      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall(
              'pushRouteInformation', {'location': _l('chat/srv-pintura')}),
        ),
        (_) {},
      );
      await t.pumpAndSettle();
      expect(obs.empilhadas, antes + 1);
      expect(t.takeException(), isNull);
    });
  });

  group('sem login', () {
    testWidgets('leva ao login e, depois de entrar, abre o destino do link',
        (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final auth = ServicoAuthFake();
      ServicoAuthPadrao.atual = auth;
      final chave = GlobalKey<NavigatorState>();
      final obs = _Rotas();
      DeepLinks.navegador = () => chave.currentState;
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        navigatorKey: chave,
        navigatorObservers: [obs],
        home: const Scaffold(body: Text('splash')),
      ));

      DeepLinks.receber(Uri.parse(_l('pedido/srv-pintura')));
      await t.pumpAndSettle();
      expect(find.byType(LoginTela), findsOneWidget);
      expect(LinkPendente.atual, isNotNull,
          reason: 'guardado em memória até entrar');

      // Entrou: a casca aparece e o destino abre.
      await auth.entrarComEmail(email: 'ana@exemplo.com', senha: '12345678');
      chave.currentState!.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const CascaClienteTela()),
        (_) => false,
      );
      await t.pumpAndSettle();
      expect(
          find.byType(CascaClienteTela, skipOffstage: false), findsOneWidget);
      expect(LinkPendente.atual, isNull);
      expect(find.byType(LoginTela), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('sair da conta esquece o link guardado', (t) async {
      DeepLinks.receber(Uri.parse(_l('pedido/srv-pintura')));
      expect(LinkPendente.atual, isNotNull);
      DeepLinks.esquecer();
      expect(LinkPendente.atual, isNull);
    });
  });
}
