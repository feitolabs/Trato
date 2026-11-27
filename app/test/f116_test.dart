// TERMOS-APP17: estado "acordo" da disputa, localização na Política (14.12) e Info.plist.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/disputa_profissional/responder_disputa_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/fontes.dart';

ServicoDisputaProfissionalApi _servico(Object? estado) =>
    ServicoDisputaProfissionalApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        final corpo = r.url.path.endsWith('/disputa')
            ? {
                'pedido_id': 'ab12cd34',
                if (estado != null) 'estado': estado,
                'motivo': 'servico_incompleto',
                'descricao': 'Faltou terminar.',
                'valor_congelado_centavos': 5000,
                'aberta_em': '2026-11-20T10:00:00Z',
                'resposta_ate': '2026-11-22T10:00:00Z',
              }
            : {'nome': 'Ana'};
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200,
            headers: const {'content-type': 'application/json'});
      }),
    ));

void main() {
  setUpAll(carregarFontesTrato);

  for (final (estado, texto) in [
    ('acordo', 'Encerrada por acordo'),
    ('decidida', 'Disputa decidida'),
    ('em_analise', 'Em análise'),
    ('aguardando_aprovacao', 'Em análise'),
    ('estado_que_ainda_nao_existe', 'Em acompanhamento'),
  ]) {
    for (final tamanho in const [Size(390, 844), Size(320, 568)]) {
      testWidgets('$estado: "$texto", sem formulário (${tamanho.width.toInt()})', (t) async {
        t.view.physicalSize = tamanho;
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(MaterialApp(
          theme: TemaTrato.claro,
          home: ResponderDisputaTela(servico: _servico(estado), disputaId: 'ab12cd34'),
        ));
        await t.pumpAndSettle();
        expect(find.text(texto), findsOneWidget);
        expect(find.text('Enviar resposta'), findsNothing);
        expect(find.textContaining('Valor congelado'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final estado in ['aberta', null, 7]) {
    testWidgets('estado $estado: formulário de resposta como antes', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: ResponderDisputaTela(servico: _servico(estado), disputaId: 'ab12cd34'),
      ));
      await t.pumpAndSettle();
      expect(find.text('Enviar resposta'), findsOneWidget);
      expect(find.byKey(const Key('situacao-disputa')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  test('a Política fala de localização só no check-in e no check-out', () {
    final linha = File('assets/legal/politica-de-privacidade.md')
        .readAsLinesSync()
        .singleWhere((l) => l.startsWith('| **Localização do aparelho (GPS)**'));
    expect(linha, contains('Profissionais (no check-in e no check-out)'));
    expect(linha, contains('coletada só nesses dois momentos'));
    expect(linha, isNot(contains('ao buscar')));
    expect(linha, isNot(contains('próximos')));
  });

  test('Info.plist descreve o uso da localização uma vez só', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect('<key>NSLocationWhenInUseUsageDescription</key>'.allMatches(plist), hasLength(1));
    expect(plist, contains('quando começa e quando termina'));
  });
}
