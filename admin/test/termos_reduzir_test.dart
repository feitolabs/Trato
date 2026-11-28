import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/compensacoes_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 8.7: decisão reduzida baixa a dívida, sem novo estorno ao cliente.
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);
Finder _noDialogo(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Compensacao _comp(
        {String origem = 'disputa',
        bool suspensa = true,
        int reduzido = 0,
        String status = 'aberta',
        String? revisao = 'reducao',
        bool podeReduzir = true,
        bool podeCancelar = true}) =>
    Compensacao(
      revisao: revisao,
      revisaoContestacaoId: revisao == null ? null : 'cont-1',
      podeReduzir: podeReduzir,
      reducaoMaximaCentavos: podeReduzir ? 8000 : null,
      podeCancelar: podeCancelar,
      id: 'c1',
      pedidoId: 'ped-1',
      origem: origem,
      valorCentavos: 10000 - reduzido,
      valorOriginalCentavos: 10000,
      reduzidoCentavos: reduzido,
      devolvidoReducaoCentavos: reduzido > 0 ? 1234 : 0,
      compensadoCentavos: 2500,
      restanteCentavos: 10000 - reduzido - 2500,
      motivo: 'Motivo de exemplo',
      status: status,
      suspensa: suspensa,
      criadaEm: DateTime(2026, 11, 20),
      avisadoEm: DateTime(2026, 11, 21),
    );

class _Api extends ApiFake {
  _Api(Compensacao item) {
    compensacoes = [item];
  }
}

Future<_Api> _abrir(WidgetTester tester, Compensacao c, {ErroApi? falha}) async {
  final api = _Api(c);
  await abrirPainel(tester, api: api, secao: 'compensacoes');
  await tester.tap(find.textContaining('Pedido ped-1').first);
  await tester.pumpAndSettle();
  api.falhaCompensacao = falha;
  return api;
}

Future<void> _preencher(WidgetTester tester) async {
  final botao = find.text('Reduzir');
  await rolarListaAte(tester, botao);
  await tester.tap(botao);
  await tester.pumpAndSettle();
  Future<void> escrever(String rotulo, String texto) async {
    await tester.enterText(_noDialogo(find.widgetWithText(TextField, rotulo)), texto);
    await tester.pump();
  }

  expect(_noDialogo(find.widgetWithText(TextField, 'Código da contestação que reduziu')), findsNothing);
  await escrever('Novo valor da compensação', '60,00');
  await escrever('Motivo', 'Contestação reduziu a decisão');
  await tester.pumpAndSettle();
}

Future<void> _confirmar(WidgetTester tester) async {
  final alvo = _noDialogo(find.text('Reduzir compensação'));
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('quitada com pode_reduzir oferece reduzir; acima do máximo não envia', (tester) async {
    final api = await _abrir(tester, _comp(status: 'quitada', suspensa: false));
    await _preencher(tester);
    await tester.enterText(_noDialogo(find.widgetWithText(TextField, 'Novo valor da compensação')), '80,01');
    await tester.pumpAndSettle();
    expect(_contem('Passa do máximo de'), findsOneWidget);
    await _confirmar(tester);
    expect(api.chamadasCompensacao, isEmpty);
    await tester.enterText(_noDialogo(find.widgetWithText(TextField, 'Novo valor da compensação')), '80,00');
    await tester.pumpAndSettle();
    await _confirmar(tester);
    expect(api.chamadasCompensacao.single.$2['valor'], 8000);
  });

  testWidgets('analisar: não recomenda cancelar nem reduzir', (tester) async {
    await _abrir(tester, _comp(revisao: 'analisar', podeReduzir: false));
    await rolarListaAte(tester, _contem(kRevisaoAnalisar));
    expect(_contem(kRevisaoAnalisar), findsOneWidget);
    expect(_contem('O caminho é'), findsNothing);
    expect(find.text('Reduzir'), findsNothing);
    final botao = find.text('Cancelar compensação');
    await rolarListaAte(tester, botao);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    expect(_noDialogo(_contem(kRevisaoAnalisar)), findsOneWidget);
    expect(_noDialogo(_contem('Use quando')), findsNothing);
    expect(_noDialogo(_contem('indica reduzir')), findsNothing);
  });

  testWidgets('reversão indica cancelar e não oferece reduzir', (tester) async {
    await _abrir(tester, _comp(revisao: 'reversao', podeReduzir: false));
    await rolarListaAte(tester, _contem(kRevisaoReversao));
    expect(_contem(kRevisaoReversao), findsOneWidget);
    expect(find.text('Reduzir'), findsNothing);
  });

  testWidgets('sem pode_reduzir e pode_cancelar não há botões, mesmo para administrador', (tester) async {
    await _abrir(tester, _comp(podeReduzir: false, podeCancelar: false));
    expect(find.text('Reduzir'), findsNothing);
    expect(find.text('Cancelar compensação'), findsNothing);
    await rolarListaAte(tester, _contem(kReducaoNaoLiberada));
    expect(_contem(kReducaoNaoLiberada), findsOneWidget);
  });

  testWidgets('suspensa sem revisao não oferece Reduzir, mesmo com pode_reduzir', (tester) async {
    await _abrir(tester, _comp(revisao: null));
    expect(find.text('Reduzir'), findsNothing);
  });

  testWidgets('filtro "Revisão pendente" vai para o servidor', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, api: api, secao: 'compensacoes');
    expect(api.ultimaRevisaoPendente, isFalse);
    await tester.tap(find.widgetWithText(FilterChip, 'Revisão pendente'));
    await tester.pumpAndSettle();
    expect(api.ultimaRevisaoPendente, isTrue);
  });

  testWidgets('suspensa oferece reduzir, com confirmação sem novo estorno', (tester) async {
    final api = await _abrir(tester, _comp());
    await _preencher(tester);
    expect(_contem(kEfeitoDaReducao), findsOneWidget);
    expect(api.chamadasCompensacao, isEmpty);
    await _confirmar(tester);
    expect(api.chamadasCompensacao.single.$1, 'reduzir');
    expect(api.chamadasCompensacao.single.$2,
        {'id': 'c1', 'contestacao': 'cont-1', 'valor': 6000, 'motivo': 'Contestação reduziu a decisão'});
    expect(_contem('sem novo estorno ao cliente'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recusa do servidor aparece na tela', (tester) async {
    await _abrir(tester, _comp(),
        falha: const ErroApi('Esta contestação não permite reduzir esta compensação.',
            status: 422, codigo: 'contestacao_invalida'));
    await _preencher(tester);
    await _confirmar(tester);
    expect(_contem('não permite reduzir'), findsOneWidget);
  });

  testWidgets('mostra original, reduzido, o que vale e o devolvido', (tester) async {
    await _abrir(tester, _comp(suspensa: false, reduzido: 4000));
    for (final rotulo in ['Valor original', 'Reduzido', 'Vale hoje', 'Devolvido ao profissional pela redução']) {
      expect(_contem(rotulo), findsWidgets, reason: rotulo);
    }
    expect(_contem('12,34'), findsOneWidget);
  });

  test('API: rota, corpo e campos novos', () async {
    final chamadas = <(String, Map<String, dynamic>)>[];
    final consultas = <Map<String, String>>[];
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
        if (r.method == 'GET') {
          consultas.add(r.url.queryParameters);
          return http.Response('{"itens":[],"total":0}', 200);
        }
        chamadas.add((r.url.path, jsonDecode(r.body) as Map<String, dynamic>));
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'resultado': 'ok',
              'devolvido_centavos': 100,
              'compensacao': {
                'id': 'c1',
                'pedido_id': 'p1',
                'origem': 'disputa',
                'valor_centavos': 6000,
                'valor_original_centavos': 10000,
                'reduzido_centavos': 4000,
                'devolvido_reducao_centavos': 100,
                'compensado_centavos': 0,
                'restante_centavos': 6000,
                'motivo': 'm',
                'status': 'quitada',
                'revisao': 'reducao',
                'revisao_contestacao_id': 'x2',
                'pode_reduzir': true,
                'reducao_maxima_centavos': 5000,
                'pode_cancelar': true,
                'criada_em': '2026-11-20T10:00:00Z',
              },
            })),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final r = await api.reduzirCompensacao('c1', contestacaoId: 'x1', novoValorCentavos: 6000, motivo: 'motivo longo');
    expect(chamadas.single.$1, '/v1/admin/compensacoes/c1/reduzir');
    expect(chamadas.single.$2, {'contestacao_id': 'x1', 'novo_valor_centavos': 6000, 'motivo': 'motivo longo'});
    expect(r.compensacao.valorOriginalCentavos, 10000);
    expect(r.compensacao.reduzidoCentavos, 4000);
    expect(r.compensacao.devolvidoReducaoCentavos, 100);
    expect((r.compensacao.revisao, r.compensacao.revisaoContestacaoId), ('reducao', 'x2'));
    expect((r.compensacao.podeReduzir, r.compensacao.reducaoMaximaCentavos, r.compensacao.podeCancelar),
        (true, 5000, true));
    await api.listarCompensacoes(revisaoPendente: true);
    await api.listarCompensacoes();
    expect(consultas.first['revisao_pendente'], 'true');
    expect(consultas.last.containsKey('revisao_pendente'), isFalse);
  });
}
