// TERMOS-APP2: "Completar cadastro" para quem entra sem data de nascimento (Termos 4.1) e falha
// do vínculo do cadastro com "Tentar de novo".
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servico_conta_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/auth/completar_cadastro.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/conta/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Servidor de mentira do portão: a data guardada e as falhas.
class _Servidor {
  _Servidor({this.nascimento});
  DateTime? nascimento;
  var semRede = false;
  var gravaDeVerdade = true;
  var leituras = 0;
  final gravadas = <DateTime>[];

  Future<DadosPessoaisConta> ler() async {
    leituras++;
    if (semRede) throw const ErroTrato(TipoErro.semInternet, 'Sem internet.');
    return DadosPessoaisConta(dataNascimento: nascimento);
  }

  Future<DadosPessoaisConta> gravar(DateTime d) async {
    if (semRede) throw const ErroTrato(TipoErro.semInternet, 'Sem internet.');
    gravadas.add(d);
    if (gravaDeVerdade) nascimento = d;
    return DadosPessoaisConta(dataNascimento: nascimento);
  }
}

Future<ServicoAuthFake> _logada() async {
  final auth = ServicoAuthFake();
  await auth.entrarComProvedor(ProvedorAuth.google);
  return auth;
}

Future<void> _abrir(
  WidgetTester t,
  ServicoAuth auth,
  _Servidor s, {
  Listenable? conferirDeNovo,
  Future<void> Function()? sair,
}) async {
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    builder: (c, f) => EscalaFonteLimitada(
      child: PortaoCadastro(
        auth: auth,
        ler: s.ler,
        gravar: s.gravar,
        sair: sair ?? auth.sair,
        conferirDeNovo: conferirDeNovo,
        child: f!,
      ),
    ),
    home: const Scaffold(body: Text('INICIO DO APP')),
  ));
  await t.pumpAndSettle();
}

final _app = find.text('INICIO DO APP');
final _completar = find.text('Completar cadastro');

Future<void> _digitarECContinuar(WidgetTester t, String data) async {
  await t.ensureVisible(find.byType(TextField));
  await t.enterText(find.byType(TextField), data);
  await t.pump();
  final botao = find.textContaining(RegExp('^(Continuar|Tentar de novo)\$'));
  await t.ensureVisible(botao);
  await t.pumpAndSettle();
  await t.tap(botao);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ligarDemoNosTestes();
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('sem data: cobre o app, recusa menor e libera o adulto ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final s = _Servidor();
        final auth = await _logada();
        await _abrir(t, auth, s);
        expect(_completar, findsOneWidget);
        expect(_app, findsNothing);
        expect(find.text('Sair da conta'), findsOneWidget);

        await _digitarECContinuar(t, '0101${DateTime.now().year - 10}');
        expect(find.text('O cadastro é exclusivo para maiores de 18 anos.'), findsOneWidget);
        expect(find.text('Sem 18 anos não dá para continuar.'), findsOneWidget);
        expect(s.gravadas, isEmpty);
        expect(_app, findsNothing);

        await _digitarECContinuar(t, '15031992');
        expect(s.gravadas.single, DateTime(1992, 3, 15));
        expect(_app, findsOneWidget);
        expect(_completar, findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('data de menor já gravada: só dá para sair ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final auth = await _logada();
        await _abrir(t, auth, _Servidor(nascimento: DateTime(DateTime.now().year - 10)));
        expect(find.text('Cadastro só para maiores de 18 anos'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(_app, findsNothing);
        await t.ensureVisible(find.text('Sair da conta'));
        await t.pumpAndSettle();
        await t.tap(find.text('Sair da conta'));
        await t.pumpAndSettle();
        expect(auth.sessaoAtual, isNull);
        expect(_app, findsOneWidget, reason: 'sem sessão o portão solta (a rota vai ao login)');
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('quem tem data entra direto e fica anotado: depois nem consulta', (t) async {
    final s = _Servidor(nascimento: DateTime(1990));
    final auth = await _logada();
    await _abrir(t, auth, s);
    expect(_app, findsOneWidget);
    expect(s.leituras, 1);

    await t.pumpWidget(const SizedBox());
    s.semRede = true;
    await _abrir(t, auth, s);
    expect(_app, findsOneWidget);
    expect(s.leituras, 1, reason: 'cadastro completo não depende de rede');
  });

  testWidgets('sem rede não prende; quando volta, confere e pede a data', (t) async {
    final s = _Servidor()..semRede = true;
    final volta = ValueNotifier<int>(0);
    await _abrir(t, await _logada(), s, conferirDeNovo: volta);
    expect(_app, findsOneWidget);
    expect(_completar, findsNothing);

    s.semRede = false;
    volta.value++;
    await t.pumpAndSettle();
    expect(_completar, findsOneWidget);
    expect(_app, findsNothing);
  });

  testWidgets('consulta que não responde não prende além do limite', (t) async {
    final auth = await _logada();
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      builder: (c, f) => PortaoCadastro(
        auth: auth,
        ler: () => Completer<DadosPessoaisConta>().future,
        gravar: (_) async => const DadosPessoaisConta(),
        sair: auth.sair,
        child: f!,
      ),
      home: const Scaffold(body: Text('INICIO DO APP')),
    ));
    await t.pump();
    expect(_app, findsNothing);
    await t.pump(const Duration(seconds: 9));
    await t.pump();
    expect(_app, findsOneWidget);
  });

  testWidgets('falha ao salvar: erro claro, "Tentar de novo"; 204 sem gravar não libera',
      (t) async {
    final s = _Servidor();
    await _abrir(t, await _logada(), s);
    s.semRede = true;
    await _digitarECContinuar(t, '15031992');
    expect(find.text('Sem internet.'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);

    s.semRede = false;
    s.gravaDeVerdade = false;
    await _digitarECContinuar(t, '15031992');
    expect(find.textContaining('Não conseguimos salvar'), findsOneWidget);
    expect(_app, findsNothing);

    s.gravaDeVerdade = true;
    await _digitarECContinuar(t, '15031992');
    expect(_app, findsOneWidget);
  });

  testWidgets('sem sessão não há portão; ao entrar sem data, ele aparece', (t) async {
    final s = _Servidor();
    final auth = ServicoAuthFake();
    await _abrir(t, auth, s);
    expect(_app, findsOneWidget);
    expect(s.leituras, 0);
    await auth.entrarComProvedor(ProvedorAuth.apple);
    await t.pumpAndSettle();
    expect(_completar, findsOneWidget);
  });

  testWidgets('sair pelo contexto do navegador raiz (como o main liga) leva ao login', (t) async {
    final navegador = GlobalKey<NavigatorState>();
    final auth = await _logada();
    ServicoAuthPadrao.atual = auth;
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      navigatorKey: navegador,
      builder: (c, f) => PortaoCadastro(
        auth: auth,
        ler: _Servidor().ler,
        gravar: _Servidor().gravar,
        sair: () => RotasTrato.sair(navegador.currentContext!),
        child: f!,
      ),
      home: const Scaffold(body: Text('INICIO DO APP')),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Sair da conta'));
    await t.pumpAndSettle();
    expect(auth.sessaoAtual, isNull);
    expect(find.byType(LoginTela), findsOneWidget);
    expect(_completar, findsNothing);
    expect(t.takeException(), isNull);
  });

  test('a data é gravada pelo vínculo do cadastro e confirmada pela leitura', () async {
    final chamadas = <(String, String, Object?)>[];
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        chamadas.add((req.method, req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
        if (req.method == 'POST') return http.Response('', 204);
        return http.Response(jsonEncode({'data_nascimento': '1992-03-15'}), 200,
            headers: const {'content-type': 'application/json'});
      }),
    );
    final d = await ServicoContaApi(api).informarNascimento(
        usuarioId: 'u1', email: 'a@b.com', nascimento: DateTime(1992, 3, 15));
    expect(d.dataNascimento, DateTime(1992, 3, 15));
    expect(chamadas.map((c) => '${c.$1} ${c.$2}'),
        ['POST /v1/cadastro/vincular', 'GET /v1/me/dados-pessoais']);
    expect(chamadas.first.$3,
        {'usuario_id': 'u1', 'email': 'a@b.com', 'data_nascimento': '1992-03-15'});
  });

  testWidgets('cadastro com vínculo que falhou mostra erro e "Tentar de novo"', (t) async {
    await _janela(t, const Size(390, 844), 1);
    final auth = ServicoAuthFake()
      ..falharNaProxima = const ErroAuth(TipoErroAuth.cadastroNaoVinculado);
    await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: CriarContaTela(servico: auth)));
    final valores = ['Ana Souza', '15031992', '31999998888', 'ana@teste.com', 'segredo123'];
    for (var i = 0; i < valores.length; i++) {
      final campo = find.byType(TextField).at(i);
      await t.ensureVisible(campo);
      await t.pumpAndSettle();
      await t.enterText(campo, valores[i]);
    }
    await t.ensureVisible(find.byType(Checkbox).first);
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox).first);
    await t.pump();
    await t.tap(find.text('Criar conta').last);
    await t.pumpAndSettle();
    expect(find.textContaining('não salvamos seus dados'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    await t.tap(find.text('Tentar de novo'));
    await t.pumpAndSettle();
    expect(auth.sessaoAtual?.email, 'ana@teste.com');
  });
}
