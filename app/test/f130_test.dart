// APP-94-SOS: da emergência do pedido ao chamado de segurança (cláusulas 9.3 a 9.5).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/atendimento/atendimento_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/atendimento.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

class _Servidor {
  (int, Object) resposta = (
    201,
    {
      'id': 'c1',
      'protocolo': 'SAC-1',
      'assunto': casoPessoaDiferente,
      'status': 'aberto',
      'categoria': 'seguranca',
      'pedido_id': 'p1',
      'mensagens': <Object>[],
    }
  );
  final envios = <http.Request>[];

  late final servico = ServicoSacApi(ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      if (r.method == 'POST') envios.add(r);
      final (status, corpo) = resposta;
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  ));
}

void _janela(WidgetTester t, [double altura = 640]) {
  t.view.physicalSize = Size(320, altura);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _formulario(WidgetTester t, _Servidor s, {bool cliente = true}) async {
  // Tela alta: o formulário inteiro fica montado.
  _janela(t, 2400);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: NovoChamadoTela(
      servico: s.servico,
      pedidoInicial: 'p1',
      seguranca: true,
      orientarChegada: cliente,
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, Key chave) async {
  await t.ensureVisible(find.byKey(chave));
  await t.pumpAndSettle();
  await t.tap(find.byKey(chave));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);

  for (final cliente in [true, false]) {
    testWidgets('emergência: telefones primeiro; relatar não envia nada ($cliente)', (t) async {
      var relatou = 0;
      _janela(t);
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => mostrarEmergencia(c, 'Resumo',
                aoRelatar: () => relatou++, orientarChegada: cliente),
            child: const Text('abrir'),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      double y(String chave) => t.getTopLeft(find.byKey(ValueKey(chave))).dy;
      expect(y('ligar-190') < y('ligar-192') && y('ligar-192') < y('ligar-193'), isTrue);
      expect(y('ligar-193') < y('sos-relatar'), isTrue);
      expect(find.text(orientacaoPessoaDiferente), cliente ? findsOneWidget : findsNothing);
      expect(find.textContaining('reembolso'), findsNothing);
      await t.ensureVisible(find.byKey(const ValueKey('sos-relatar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sos-relatar')));
      await t.pumpAndSettle();
      expect(relatou, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('os seis casos; só envia no botão, como segurança e ligado ao pedido', (t) async {
    final s = _Servidor();
    await _formulario(t, s);
    expect(casosDeSeguranca, hasLength(6));
    expect(find.byKey(const Key('categoria-chamado')), findsNothing);
    expect(find.textContaining('reembolso'), findsNothing);
    await _tocar(t, const Key('enviar-chamado'));
    expect(s.envios, isEmpty);
    expect(find.text('Escolha o que aconteceu.', skipOffstage: false), findsOneWidget);
    await _tocar(t, const ValueKey('caso-seguranca-3'));
    expect(find.text(orientacaoPessoaDiferente, skipOffstage: false), findsOneWidget);
    expect(s.envios, isEmpty);
    final texto = find.byKey(const Key('texto-chamado'));
    await t.enterText(texto, 'Não é a pessoa da foto.');
    await t.pumpAndSettle();
    expect(s.envios, isEmpty);
    await _tocar(t, const Key('enviar-chamado'));
    expect(jsonDecode(s.envios.single.body), {
      'categoria': 'seguranca',
      'assunto': casoPessoaDiferente,
      'texto': 'Não é a pessoa da foto.',
      'pedido_id': 'p1',
    });
    expect(find.textContaining('SAC-1'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('profissional não recebe a orientação sobre a porta', (t) async {
    await _formulario(t, _Servidor(), cliente: false);
    await _tocar(t, const ValueKey('caso-seguranca-3'));
    expect(find.text(orientacaoPessoaDiferente, skipOffstage: false), findsNothing);
  });

  testWidgets('erro no envio fica junto do botão e o texto continua', (t) async {
    final s = _Servidor()..resposta = (503, {'detail': 'x'});
    await _formulario(t, s);
    await _tocar(t, const ValueKey('caso-seguranca-0'));
    final texto = find.byKey(const Key('texto-chamado'));
    await t.enterText(texto, 'Sumiu um objeto.');
    await _tocar(t, const Key('enviar-chamado'));
    expect(find.text(textoAtendimentoIndisponivel, skipOffstage: false), findsOneWidget);
    expect(find.text('Sumiu um objeto.', skipOffstage: false), findsOneWidget);
    expect(s.envios, hasLength(1));
  });

  testWidgets('pela rota do profissional: SOS leva ao relato ligado ao pedido', (t) async {
    final antes = RotasTrato.repos;
    addTearDown(() => RotasTrato.repos = antes);
    final s = _Servidor();
    RotasTrato.repos = repositoriosDemo(sac: s.servico);
    _janela(t, 844);
    await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: const Scaffold()));
    RotasTrato.acoesPedidoProfissionalParaTeste(
      t.element(find.byType(Scaffold)),
      estadoApi: 'em_andamento',
    );
    await t.pumpAndSettle();
    await _tocar(t, const ValueKey('botao-sos-emergencia'));
    await _tocar(t, const ValueKey('sos-relatar'));
    final tela = t.widget<NovoChamadoTela>(find.byType(NovoChamadoTela));
    expect((tela.seguranca, tela.pedidoInicial, tela.orientarChegada), (true, 'p1', false));
    expect(s.envios, isEmpty);
  });
}
