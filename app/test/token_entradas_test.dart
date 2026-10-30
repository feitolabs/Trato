import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/auth/servico_auth_fake.dart';
import 'package:trato/auth/ligacao_sessao.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/profissional_inicio/casca_profissional_tela.dart';
import 'package:trato/telas/splash_tela.dart';
import 'package:trato/tema/tema.dart';

const _chave = 'Ab1' 'Cd2' 'Ef3';

void main() {
  tearDown(() => ServicoAuthPadrao.atual = ServicoAuthFake());

  group('token do login no cliente HTTP', () {
    test('toda chamada leva o token da sessão', () async {
      final auth = ServicoAuthFake();
      final sessao = SessaoTrato();
      LigacaoSessao(auth, sessao);
      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');
      final cabecalhos = <String?>[];
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((r) async {
          cabecalhos.add(r.headers['Authorization']);
          return http.Response('{}', 200);
        }),
      );
      await api.get('/v1/a');
      await api.post('/v1/b', corpo: {'x': 1});
      expect(cabecalhos, hasLength(2));
      expect(cabecalhos.every((c) => c == 'Bearer ${auth.tokenAtual}'), isTrue);
    });

    test('401 renova o token e repete a chamada uma vez', () async {
      final auth = ServicoAuthFake();
      final sessao = SessaoTrato();
      LigacaoSessao(auth, sessao);
      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');
      final velho = sessao.token;
      final usados = <String?>[];
      var expirou = 0;
      sessao.aoExpirar = () => expirou++;
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((r) async {
          usados.add(r.headers['Authorization']);
          return usados.length == 1 ? http.Response('{}', 401) : http.Response('{"ok":true}', 200);
        }),
      );
      final r = await api.post('/v1/x', corpo: {'a': 1}, chaveIdempotencia: 'k1');
      expect(r, {'ok': true});
      expect(auth.renovacoes, 1);
      expect(usados, ['Bearer $velho', 'Bearer ${sessao.token}']);
      expect(sessao.token, isNot(velho));
      expect(expirou, 0);
    });

    test('401 sem como renovar limpa a sessão e avisa uma vez', () async {
      final auth = ServicoAuthFake()..renovacaoFalha = true;
      final sessao = SessaoTrato();
      LigacaoSessao(auth, sessao);
      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');
      var expirou = 0;
      sessao.aoExpirar = () => expirou++;
      var chamadas = 0;
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((_) async {
          chamadas++;
          return http.Response('{}', 401);
        }),
      );
      await expectLater(api.get('/v1/x'), throwsA(isA<ErroTrato>()));
      expect(sessao.logada, isFalse);
      expect(expirou, 1);
      expect(chamadas, 1);
    });

    test('se o 401 vem de novo depois de renovar, expira sem laço', () async {
      final auth = ServicoAuthFake();
      final sessao = SessaoTrato();
      LigacaoSessao(auth, sessao);
      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');
      var chamadas = 0;
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((_) async {
          chamadas++;
          return http.Response('{}', 401);
        }),
      );
      await expectLater(api.get('/v1/x'), throwsA(isA<ErroTrato>()));
      expect(chamadas, 2);
      expect(sessao.logada, isFalse);
    });
  });

  group('primeira abertura e perfil', () {
    Future<void> abrir(WidgetTester tester, Widget tela) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
      await tester.pumpAndSettle();
    }

    testWidgets('splash sem sessão vai ao onboarding', (tester) async {
      await abrir(tester, const SplashTela());
      await tester.tap(find.text('Toque para começar'));
      await tester.pumpAndSettle();
      expect(find.byType(SplashTela), findsNothing);
      expect(find.byType(CascaClienteTela), findsNothing);
    });

    testWidgets('splash com sessão de cliente vai direto à casca do cliente', (tester) async {
      final auth = ServicoAuthFake();
      ServicoAuthPadrao.atual = auth;
      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');
      await abrir(tester, const SplashTela());
      await tester.tap(find.text('Toque para começar'));
      await tester.pumpAndSettle();
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('login de conta profissional entra na casca do profissional', (tester) async {
      final auth = ServicoAuthFake();
      ServicoAuthPadrao.atual = auth;
      await auth.criarConta(const DadosCadastro(
        nome: 'Carlos',
        email: 'carlos@pro.com',
        senha: _chave,
        celular: '(31) 98765-4417',
        perfil: 'profissional',
      ));
      await auth.sair();
      await abrir(tester, const LoginTela());
      await tester.enterText(find.byType(TextField).at(0), 'carlos@pro.com');
      await tester.enterText(find.byType(TextField).at(1), _chave);
      await tester.tap(find.text('Entrar').last);
      await tester.pumpAndSettle();
      expect(find.byType(CascaProfissionalTela), findsOneWidget);
      expect(find.byType(CascaClienteTela), findsNothing);
    });

    testWidgets('Sair no Perfil limpa a sessão e volta ao login', (tester) async {
      final auth = ServicoAuthFake();
      ServicoAuthPadrao.atual = auth;
      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');
      final sessao = SessaoTrato();
      LigacaoSessao(auth, sessao);
      RotasTrato.sessao = sessao;
      addTearDown(() => RotasTrato.sessao = null);
      expect(sessao.logada, isTrue);
      await abrir(tester, const CascaClienteTela());
      await tester.tap(find.text('Perfil').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginTela), findsOneWidget);
      expect(sessao.logada, isFalse);
      expect(auth.sessaoAtual, isNull);
    });

    testWidgets('Perfil só lista itens com destino real', (tester) async {
      await abrir(tester, const CascaClienteTela());
      await tester.tap(find.text('Perfil').last);
      await tester.pumpAndSettle();
      expect(find.text('Central de ajuda'), findsOneWidget);
      expect(find.text('Endereços'), findsNothing);
      expect(find.text('Em breve'), findsNothing);
    });
  });
}
