import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/compensacoes_modal.dart';
import 'package:trato_admin/telas/compensacoes_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 8.6 e 8.7: decisão reduzida suspende o desconto; cancelar não vira dívida menor.
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Compensacao _comp({String origem = 'disputa', String status = 'aberta', bool suspensa = false}) => Compensacao(
      suspensa: suspensa,
      podeCancelar: status != 'cancelada',
      id: 'c1',
      pedidoId: 'ped-1',
      origem: origem,
      valorCentavos: 10000,
      compensadoCentavos: 2500,
      restanteCentavos: status == 'cancelada' ? 0 : 7500,
      motivo: 'Motivo de exemplo',
      status: status,
      criadaEm: DateTime(2026, 11, 20),
      avisadoEm: DateTime(2026, 11, 21),
    );

class _Api extends ApiFake {
  _Api(this.item);
  final Compensacao item;

  @override
  Future<PaginaRemota<Compensacao>> listarCompensacoes(
          {String? profissionalId,
          String? pedidoId,
          String? status,
          bool revisaoPendente = false,
          int deslocamento = 0,
          int limite = 50}) async =>
      PaginaRemota([item], 1);
}

Future<void> _abrir(WidgetTester tester, Compensacao c) async {
  await abrirPainel(tester, api: _Api(c), secao: 'compensacoes');
  await tester.tap(find.textContaining('Pedido ped-1').first);
  await tester.pumpAndSettle();
}

Future<void> _abrirCancelamento(WidgetTester tester) async {
  final botao = find.text('Cancelar compensação');
  await rolarListaAte(tester, botao);
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

Future<void> _revisarRegistro(WidgetTester tester) async {
  await tester.tap(find.text('Registrar compensação').first);
  await tester.pumpAndSettle();
  Future<void> escrever(String rotulo, String texto) async {
    await tester.enterText(
        find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo)), texto);
    await tester.pump();
  }

  await escrever('Código do pedido', 'ped-1');
  await escrever('Valor a compensar', '10,00');
  await escrever('Motivo (o profissional lê)', 'Motivo de exemplo válido');
  final revisar = find.text('Revisar');
  await tester.ensureVisible(revisar);
  await tester.pump();
  await tester.tap(revisar);
  await tester.pumpAndSettle();
}

class _ApiRecusa extends ApiFake {
  @override
  Future<({String resultado, Compensacao compensacao, bool avisado})> registrarCompensacao(
          {required String pedidoId, String? contestacaoId, required int valorCentavos, required String motivo}) async =>
      throw const ErroApi('Recusa do servidor (exemplo).', status: 409, codigo: 'estorno_ja_ordenado');
}

void main() {
  testWidgets('suspensa sem revisao: analisar com o financeiro, sem recomendar nada', (tester) async {
    await _abrir(tester, _comp(suspensa: true));
    expect(find.text(kTituloSuspensaSemRevisao), findsOneWidget);
    expect(find.text('Desconto suspenso'), findsNothing);
    await rolarListaAte(tester, _contem(kSuspensaSemRevisao));
    expect(_contem(kSuspensaSemRevisao), findsOneWidget);
    expect(_contem(kDividaSuspensa), findsNothing);
    expect(find.text('Reduzir'), findsNothing);
    await _abrirCancelamento(tester);
    Finder noDialogo(String t) => find.descendant(of: find.byType(Dialog), matching: _contem(t));
    expect(noDialogo('$kTituloSuspensaSemRevisao. $kSuspensaSemRevisao'), findsOneWidget);
    expect(noDialogo('Use quando'), findsNothing);
    expect(noDialogo('indica reduzir'), findsNothing);
    expect(noDialogo('O caminho é'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suspensa sem revisao no celular não estoura', (tester) async {
    await abrirPainel(tester, api: _Api(_comp(suspensa: true)), largura: 360);
    await tester.tap(find.byKey(const ValueKey('menu-mais')));
    await tester.pumpAndSettle();
    await tocarNoMais(tester, 'compensacoes');
    expect(find.text(kTituloSuspensaSemRevisao), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final origem in ['disputa', 'disputa_contestacao', 'regresso']) {
    testWidgets('sem suspensa, $origem não é inferida como suspensa', (tester) async {
      await _abrir(tester, _comp(origem: origem));
      expect(find.text('Desconto suspenso'), findsNothing);
      expect(_contem(kDividaSuspensa), findsNothing);
      await _abrirCancelamento(tester);
      expect(_contem(kEfeitoDoCancelamento), findsOneWidget);
      expect(_contem(kRecusaDepoisDoCancelamento), findsOneWidget);
      expect(find.text('Reduzir'), findsNothing);
    });
  }

  testWidgets('cancelada de disputa diz que o novo registro é recusado', (tester) async {
    await _abrir(tester, _comp(status: 'cancelada'));
    await rolarListaAte(tester, _contem(kRecusaDepoisDoCancelamento));
    expect(_contem(kRecusaDepoisDoCancelamento), findsOneWidget);
  });

  testWidgets('409 estorno_ja_ordenado: nada gravado, vai ao financeiro', (tester) async {
    await abrirPainel(tester, api: _ApiRecusa(), secao: 'compensacoes');
    await _revisarRegistro(tester);
    expect(_contem(kRegistroCriaEstorno), findsOneWidget);
    expect(_contem(kRecusaDepoisDoCancelamento), findsOneWidget);
    await tester.tap(find.text('Confirmar compensação'));
    await tester.pumpAndSettle();
    expect(_contem('Recusa do servidor (exemplo). $kEstornoJaOrdenado'), findsOneWidget);
    expect(_contem('Não foi registrada'), findsOneWidget);
  });

  test('API lê suspensa; ausente = falso', () async {
    Object? suspensa = true;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'itens': [
                {
                  'id': 'c1',
                  'pedido_id': 'p1',
                  'origem': 'disputa',
                  'valor_centavos': 100,
                  'compensado_centavos': 0,
                  'restante_centavos': 100,
                  'motivo': 'm',
                  'status': 'aberta',
                  'criada_em': '2026-11-20T10:00:00Z',
                  'suspensa': ?suspensa,
                }
              ],
              'total': 1,
            })),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    expect((await api.listarCompensacoes()).itens.single.suspensa, isTrue);
    suspensa = null;
    expect((await api.listarCompensacoes()).itens.single.suspensa, isFalse);
  });
}
