// APP-REACEITE: aceite dos Termos pedido na tela (cláusulas 1.7 e 23.4).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/comuns/textos_dos_termos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/legal/aceite_dos_termos.dart';
import 'package:trato/telas/pedido_novo/modelos.dart' show FaixaPreco, RascunhoPedido;

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

Map<String, Object?> _situacao({
  String versao = '1.1',
  bool pendente = true,
  bool registro = true,
}) =>
    {
      'versao_vigente': versao,
      'vigente_desde': '2026-11-22',
      'registro_disponivel': registro,
      'aceite_pendente': pendente,
      'versao_aceita': null,
      'aceita_em': null,
    };

class _Servidor {
  _Servidor([Object? corpo]) : consulta = (200, corpo ?? _situacao());

  (int, Object?) consulta;
  (int, Object) aceite = (201, _situacao(pendente: false));
  Completer<void>? espera;
  final chamadas = <http.Request>[];

  Iterable<http.Request> get envios => chamadas.where((r) => r.method == 'POST');

  late final servico = ServicoPrivacidadeApi(ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      chamadas.add(r);
      if (r.method == 'GET') await espera?.future;
      final (status, corpo) = r.method == 'POST' ? aceite : consulta;
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  ));
}

void _janela(WidgetTester t, [Size tamanho = const Size(320, 640), double fonte = 1]) {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _tela(WidgetTester t, _Servidor s, {String versao = '1.1', double fonte = 1}) async {
  _janela(t, const Size(320, 640), fonte);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: AceiteDosTermosTela(
      servico: s.servico,
      pendente: AceitePendente(versaoVigente: versao),
      carregarTexto: () async => '# T\n\n## 1. Seção\n\nTexto dos termos para ler.',
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, String chave) async {
  final alvo = find.byKey(ValueKey(chave));
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('caixa desmarcada; só envia depois de marcar e tocar, só com a versão', (t) async {
    final s = _Servidor();
    await _tela(t, s);
    expect(versaoDosTermos, '1.1');
    expect(find.text('Texto dos termos para ler.'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('termos-marcar'))).value, isFalse);
    await _tocar(t, 'termos-aceitar');
    expect(s.chamadas, isEmpty);
    await _tocar(t, 'termos-marcar');
    expect(s.chamadas, isEmpty);
    await _tocar(t, 'termos-aceitar');
    expect(s.envios.single.url.path, '/v1/me/termos/aceite');
    expect(jsonDecode(s.envios.single.body), {'versao': '1.1'});
    expect(t.takeException(), isNull);
  });

  for (final (status, detalhe, aviso) in [
    (409, 'A versão em vigor dos Termos é a 1.2.', 'A versão em vigor dos Termos é a 1.2.'),
    (422, 'Versão inválida.', 'Versão inválida.'),
    (503, 'x', 'O registro do aceite está indisponível agora. Tente mais tarde.'),
  ]) {
    testWidgets('erro $status aparece junto do botão; dá para tentar de novo', (t) async {
      final s = _Servidor()..aceite = (status, {'detail': detalhe});
      await _tela(t, s, fonte: 1.3);
      await _tocar(t, 'termos-marcar');
      await _tocar(t, 'termos-aceitar');
      expect(find.text(aviso), findsOneWidget);
      s.aceite = (200, _situacao(pendente: false));
      await _tocar(t, 'termos-aceitar');
      expect(s.envios.length, 2);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('versão diferente da do app: não deixa aceitar e pede para atualizar', (t) async {
    final s = _Servidor();
    await _tela(t, s, versao: '1.2');
    expect(find.textContaining('Atualize o app'), findsOneWidget);
    expect(find.byKey(const ValueKey('termos-marcar')), findsNothing);
    expect(find.byKey(const ValueKey('termos-aceitar')), findsNothing);
    expect(find.byKey(const ValueKey('termos-depois')), findsOneWidget);
    expect(s.chamadas, isEmpty);
  });

  testWidgets('o texto que vai no app abre na tela, a 320 px com fonte 1,3x', (t) async {
    _janela(t, const Size(320, 568), 1.3);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: AceiteDosTermosTela(
          servico: _Servidor().servico, pendente: const AceitePendente(versaoVigente: '1.1')),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('texto-dos-termos')), findsOneWidget);
    expect(find.byKey(const ValueKey('termos-aceitar')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('nada a mostrar: sem pendência, sem registro, campo ausente, 404, 503 e 403', () async {
    for (final corpo in <Object?>[
      _situacao(pendente: false),
      _situacao(registro: false),
      <String, Object>{},
      {..._situacao()}..remove('versao_vigente'),
      {..._situacao()}..remove('aceite_pendente'),
    ]) {
      expect(await _Servidor(corpo).servico.aceitePendente(), isNull, reason: '$corpo');
    }
    for (final status in [404, 503, 403]) {
      final s = _Servidor()..consulta = (status, {'detail': 'x', 'codigo': 'conta_bloqueada'});
      expect(await s.servico.aceitePendente(), isNull, reason: '$status');
    }
  });

  group('ao entrar no app', () {
    Future<GlobalKey<NavigatorState>> entrar(WidgetTester t, _Servidor s) async {
      final reposAntes = RotasTrato.repos;
      final authAntes = ServicoAuthPadrao.atual;
      addTearDown(() {
        RotasTrato.repos = reposAntes;
        ServicoAuthPadrao.atual = authAntes;
      });
      ServicoAuthPadrao.atual = ServicoAuthFake();
      await entrarNaContaDeTeste(ServicoAuthPadrao.atual);
      RotasTrato.repos = repositoriosDemo(privacidade: s.servico);
      // O texto guardado por um teste anterior não completa neste: lê de novo.
      rootBundle.clear();
      _janela(t, const Size(390, 844));
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
          MaterialApp(theme: TemaTrato.claro, navigatorKey: nav, home: const Scaffold()));
      RotasTrato.irParaCliente(nav.currentContext!);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      return nav;
    }

    // O texto dos Termos vem de um arquivo do app: precisa de espera de verdade.
    Future<void> carregarTermos(WidgetTester t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
    }

    // "Sair" esquece que o aceite já foi oferecido (isola os testes).
    Future<void> sair(WidgetTester t, GlobalKey<NavigatorState> nav) async {
      unawaited(RotasTrato.sair(nav.currentState!.overlay!.context));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('pendente: abre sem enviar nada; "depois" volta ao app e não insiste', (t) async {
      final s = _Servidor();
      final nav = await entrar(t, s);
      await carregarTermos(t);
      expect(find.byType(AceiteDosTermosTela), findsOneWidget);
      expect(find.byKey(const ValueKey('texto-dos-termos')), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.byType(CascaClienteTela), findsOneWidget);
      RotasTrato.irParaCliente(nav.currentContext!);
      await t.pumpAndSettle();
      expect(find.byType(AceiteDosTermosTela), findsNothing);
      expect(s.envios, isEmpty);
      await sair(t, nav);
    });

    testWidgets('entrada com pedido em rascunho: oferece ao voltar ao início', (t) async {
      RotasTrato.rascunhoPendente = const RascunhoPedido(
        servicos: ['Tomadas'],
        quantidade: 1,
        voltagem: '127 V',
        descricao: 'Trocar uma tomada da sala',
        prazo: 'Sem pressa',
        faixa: FaixaPreco(minimoCentavos: 0, maximoCentavos: 20000),
      );
      addTearDown(() => RotasTrato.rascunhoPendente = null);
      final s = _Servidor();
      final nav = await entrar(t, s);
      await t.pumpAndSettle();
      expect(s.chamadas, isEmpty);
      await t.tap(find.text('Voltar ao início'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await carregarTermos(t);
      expect(find.byType(AceiteDosTermosTela), findsOneWidget);
      expect(s.envios, isEmpty);
      await sair(t, nav);
    });

    testWidgets('erro na consulta: o app abre normal', (t) async {
      final s = _Servidor()..consulta = (500, {'detail': 'x'});
      final nav = await entrar(t, s);
      await t.pumpAndSettle();
      expect(find.byType(CascaClienteTela), findsOneWidget);
      expect(find.byType(AceiteDosTermosTela), findsNothing);
      expect(t.takeException(), isNull);
      await sair(t, nav);
    });

    testWidgets('consulta lenta não segura o app nem cobre o que foi aberto depois', (t) async {
      final s = _Servidor()..espera = Completer<void>();
      final nav = await entrar(t, s);
      expect(find.byType(CascaClienteTela), findsOneWidget);
      unawaited(nav.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('OUTRA')))));
      await t.pump(const Duration(seconds: 1));
      s.espera!.complete();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('OUTRA'), findsOneWidget);
      expect(find.byType(AceiteDosTermosTela), findsNothing);
      await sair(t, nav);
    });
  });
}
