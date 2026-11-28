// APP-208-237: histórico de versões dos Termos (23.7) e encerramento agendado (20.8).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/legal/texto_legal_tela.dart';
import 'package:trato/telas/medidas/modelos.dart';

import 'apoio/fontes.dart';

const _itens = [
  {
    'versao': '1.2',
    'vigente_desde': '2026-11-22',
    'vigente_ate': null,
    'atual': true,
    'texto_disponivel': true,
  },
  {
    'versao': '1.1',
    'vigente_desde': '2026-10-01',
    'vigente_ate': '2026-11-21',
    'atual': false,
    'texto_disponivel': false,
  },
];

class _Servidor {
  (int, Object) lista = (200, {'itens': _itens});
  (int, Object) texto = (200, {'versao': '1.2', 'texto': '# T\n\n## 1. Seção\n\nTexto da versão.'});
  final chamadas = <String>[];

  late final servico = ServicoPrivacidadeApi(ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato(),
    cliente: MockClient((r) async {
      chamadas.add(r.url.path);
      final (status, corpo) = r.url.path == '/v1/termos/versoes' ? lista : texto;
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  ));
}

Future<void> _abrir(WidgetTester t, _Servidor s) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: TermosEPoliticaTela(aoAbrir: (_) {}, consultaDeVersoes: s.servico),
  ));
  await t.pumpAndSettle();
  final botao = find.byKey(const ValueKey('historico-de-versoes'));
  await t.ensureVisible(botao);
  await t.pumpAndSettle();
  await t.tap(botao);
  await t.pumpAndSettle();
}

MedidaDeConta _medida({required DateTime inicio, bool vigente = false, DateTime? revertida}) =>
    MedidaDeConta.deJson({
      'id': 'm1',
      'tipo': 'encerramento',
      'inicio_em': inicio.toUtc().toIso8601String(),
      'vigente': vigente,
      'revertida_em': revertida?.toUtc().toIso8601String(),
    });

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('lista na ordem do servidor; abre só o que tem texto', (t) async {
    final s = _Servidor();
    await _abrir(t, s);
    expect(find.text('Versão 1.2'), findsOneWidget);
    expect(find.text('Em vigor desde 22/11/2026'), findsOneWidget);
    final antiga = find.byKey(const ValueKey('versao-1.1'));
    await t.scrollUntilVisible(antiga, 150, scrollable: find.byType(Scrollable).last);
    await t.pumpAndSettle();
    expect(find.text('Valeu de 01/10/2026 a 21/11/2026'), findsOneWidget);
    expect(find.text('Texto não disponível no app'), findsOneWidget);
    await t.tap(antiga);
    await t.pumpAndSettle();
    expect(s.chamadas, ['/v1/termos/versoes']);
    final nova = find.byKey(const ValueKey('versao-1.2'));
    await t.scrollUntilVisible(nova, -150, scrollable: find.byType(Scrollable).last);
    await t.ensureVisible(find.text('Ler o texto'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ler o texto'));
    await t.pumpAndSettle();
    expect(s.chamadas.last, '/v1/termos/versoes/1.2');
    expect(find.textContaining('Texto da versão.', skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('texto 404: avisa sem quebrar', (t) async {
    final s = _Servidor()..texto = (404, {'detail': 'x'});
    await _abrir(t, s);
    await t.ensureVisible(find.text('Ler o texto'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ler o texto'));
    await t.pumpAndSettle();
    expect(find.textContaining('não está disponível'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final (nome, resposta, aviso) in [
    ('servidor antigo', (404, <String, Object>{}), 'indisponível'),
    ('vazio', (200, {'itens': <Object>[]}), 'Ainda não há versões'),
  ]) {
    testWidgets('histórico: $nome', (t) async {
      await _abrir(t, _Servidor()..lista = resposta);
      expect(find.textContaining(aviso), findsOneWidget);
      expect(find.textContaining('Versão 1'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('erro na lista: dá para tentar de novo', (t) async {
    final s = _Servidor()..lista = (500, {'detail': 'x'});
    await _abrir(t, s);
    expect(find.textContaining('Tentar'), findsOneWidget);
    s.lista = (200, {'itens': _itens});
    await t.tap(find.textContaining('Tentar'));
    await t.pumpAndSettle();
    expect(find.text('Versão 1.2'), findsOneWidget);
  });

  test('encerramento futuro é agendado; os outros casos não', () {
    final agora = DateTime.now();
    final depois = agora.add(const Duration(days: 10));
    final futura = _medida(inicio: depois);
    expect(futura.agendada(agora), isTrue);
    expect(futura.situacaoTexto, startsWith('Agendada para '));
    expect(_medida(inicio: agora.subtract(const Duration(days: 1))).situacaoTexto, 'Encerrada');
    expect(_medida(inicio: depois, revertida: agora).situacaoTexto, 'Revertida');
    expect(_medida(inicio: depois, vigente: true).situacaoTexto, 'Em vigor');
    expect(const MedidaDeConta(id: 'x', tipo: 'suspensao').situacaoTexto, 'Encerrada');
  });
}
