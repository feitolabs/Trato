// APP-14-ACEITE: a pessoa consulta o registro do próprio aceite (cláusula 1.4).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/servico_ajuda_local.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/legal/registro_do_aceite.dart';
import 'package:trato/telas/legal/texto_legal_tela.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

Map<String, Object?> _situacao({String? versao = '1.1', String? em = '2026-11-20T12:30:00Z'}) => {
      'versao_vigente': '1.1',
      'vigente_desde': '2026-11-22',
      'registro_disponivel': true,
      'aceite_pendente': false,
      'versao_aceita': versao,
      'aceita_em': em,
    };

class _Servidor {
  _Servidor([Object? corpo, int status = 200]) : resposta = (status, corpo ?? _situacao());

  (int, Object) resposta;
  final chamadas = <String>[];

  late final servico = ServicoPrivacidadeApi(ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      chamadas.add('${r.method} ${r.url.path}');
      final (status, corpo) = resposta;
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  ));
}

void _janela(WidgetTester t) {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _abrir(WidgetTester t, _Servidor s) async {
  _janela(t);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: TermosEPoliticaTela(aoAbrir: (_) {}, consultaDoAceite: s.servico),
  ));
  await t.pumpAndSettle();
  await t.drag(find.byType(ListView), const Offset(0, -600));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('mostra a versão aceita, a data e a hora; nada de IP; só consulta', (t) async {
    final s = _Servidor({..._situacao(), 'ip': '203.0.113.7'});
    await _abrir(t, s);
    expect(find.text('Versão aceita: 1.1'), findsOneWidget);
    expect(find.textContaining('Aceito em 20/11/2026 às '), findsOneWidget);
    expect(find.textContaining('203.0.113.7'), findsNothing);
    expect(find.textContaining('IP'), findsNothing);
    expect(s.chamadas, ['GET /v1/me/termos']);
    expect(t.takeException(), isNull);
  });

  testWidgets('sem aceite registrado: diz isso, sem data', (t) async {
    await _abrir(t, _Servidor(_situacao(versao: null, em: null)));
    expect(find.text('Não há aceite dos Termos registrado para a sua conta.'), findsOneWidget);
    expect(find.textContaining('Aceito em'), findsNothing);
  });

  testWidgets('aceite sem data: não inventa', (t) async {
    await _abrir(t, _Servidor(_situacao(em: null)));
    expect(find.text('Data do aceite não informada.'), findsOneWidget);
    expect(find.textContaining('Aceito em'), findsNothing);
  });

  for (final (nome, corpo, status) in [
    ('404', {'detail': 'Not Found'}, 404),
    ('503', {'detail': 'x'}, 503),
    ('sem histórico', {..._situacao(), 'registro_disponivel': false}, 200),
    ('sem o campo', {..._situacao()}..remove('versao_aceita'), 200),
    ('corpo vazio', <String, Object?>{}, 200),
  ]) {
    testWidgets('indisponível ($nome): avisa e os textos seguem na tela', (t) async {
      await _abrir(t, _Servidor(corpo, status));
      expect(find.text('O registro do aceite está indisponível agora.'), findsOneWidget);
      expect(find.textContaining('Versão aceita'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('erro: avisa e tenta de novo', (t) async {
    final s = _Servidor({'detail': 'x'}, 500);
    await _abrir(t, s);
    expect(find.text('Não foi possível consultar seu aceite agora.'), findsOneWidget);
    s.resposta = (200, _situacao());
    await t.tap(find.text('Tentar de novo'));
    await t.pumpAndSettle();
    expect(find.text('Versão aceita: 1.1'), findsOneWidget);
  });

  testWidgets('a central de ajuda leva aos Termos e ao aceite', (t) async {
    var abriu = 0;
    _janela(t);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: AjudaTela(servico: const ServicoAjudaLocal(), aoVerTermos: () => abriu++),
    ));
    await t.pumpAndSettle();
    final botao = find.byKey(const Key('ajuda-termos'));
    await t.scrollUntilVisible(botao, 300, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(botao);
    await t.pumpAndSettle();
    await t.tap(botao);
    expect(abriu, 1);
  });

  for (final logado in [true, false]) {
    testWidgets('pela rota dos Termos, ${logado ? 'logado' : 'sem conta'}', (t) async {
      final reposAntes = RotasTrato.repos;
      final authAntes = ServicoAuthPadrao.atual;
      addTearDown(() {
        RotasTrato.repos = reposAntes;
        ServicoAuthPadrao.atual = authAntes;
      });
      ServicoAuthPadrao.atual = ServicoAuthFake();
      if (logado) {
        await entrarNaContaDeTeste(ServicoAuthPadrao.atual);
      }
      final s = _Servidor();
      RotasTrato.repos = repositoriosDemo(privacidade: s.servico);
      _janela(t);
      await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: const Scaffold()));
      RotasTrato.abrirTermos(t.element(find.byType(Scaffold)));
      await t.pumpAndSettle();
      expect(find.byType(CartaoRegistroDoAceite, skipOffstage: false),
          logado ? findsOneWidget : findsNothing);
      if (!logado) expect(s.chamadas, isEmpty);
    });
  }
}
