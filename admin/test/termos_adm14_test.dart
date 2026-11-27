import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const _acoes = [
  'Assumir disputa',
  'Assumir no lugar',
  'Aprovar decisão',
  'Registrar decisão',
  'Enviar para aprovação',
];

/// Todas as disputas de exemplo no estado [status]; abre o filtro [filtro].
Future<ApiFake> abrir(
  WidgetTester tester,
  StatusDisputa status, {
  required String filtro,
  double largura = 1400,
  DecisaoDisputa? decisao,
  DivisaoDisputa? divisao,
  bool limparDecisao = false,
}) async {
  final api = ApiFake();
  final disputas = (await tester.runAsync(() => api.listarDisputas(situacao: 'todas')))!.itens;
  for (final d in disputas) {
    api.mudarEstadoDisputa(d.id, status, decisao: decisao, divisao: divisao, limparDecisao: limparDecisao);
  }
  await abrirPainel(tester, papel: 'administrador', api: api, secao: 'disputas', largura: largura);
  await tester.tap(find.textContaining(filtro).first);
  await tester.pumpAndSettle();
  return api;
}

/// Percorre o detalhe até o fim sem encontrar nenhuma ação de decisão.
Future<void> semAcoes(WidgetTester tester) async {
  await rolarListaAte(tester, find.text('Evidências'));
  final lista = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
  for (var i = 0; i < 4; i++) {
    for (final a in _acoes) {
      expect(find.text(a), findsNothing, reason: a);
    }
    // Os filtros do topo também são ChoiceChip: procura só as opções de decisão.
    for (final op in DecisaoDisputa.values) {
      expect(find.widgetWithText(ChoiceChip, op.rotulo), findsNothing, reason: op.rotulo);
    }
    expect(find.widgetWithText(TextField, 'Motivo'), findsNothing);
    await tester.drag(lista, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('acordo: fica em Encerradas, com rótulo claro e sem ações', (tester) async {
    await abrir(tester, StatusDisputa.acordo, filtro: 'Encerradas');
    expect(find.text('Encerrada por acordo'), findsWidgets); // selo e linha da lista
    expect(find.textContaining('Não há o que decidir', findRichText: true), findsOneWidget);
    expect(find.textContaining('Valor congelado', findRichText: true), findsNothing);
    expect(find.text('Decisão até'), findsNothing);
    expect(find.text('Prazo vencendo'), findsNothing);
    await semAcoes(tester);
  });

  testWidgets('acordo sai da fila de abertas', (tester) async {
    await abrir(tester, StatusDisputa.acordo, filtro: 'Abertas');
    expect(find.text('Encerrada por acordo'), findsNothing);
    expect(find.text('Abertas 0'), findsOneWidget);
  });

  testWidgets('estado desconhecido não quebra e não oferece ações', (tester) async {
    await abrir(tester, StatusDisputa.desconhecida, filtro: 'Todas');
    expect(find.text('Situação não reconhecida'), findsWidgets);
    expect(find.textContaining('não oferece ações', findRichText: true), findsOneWidget);
    expect(find.text('Em análise'), findsNothing);
    await semAcoes(tester);
  });

  testWidgets('acordo com divisão e devolução mostra valores, rótulo e aviso do provedor', (tester) async {
    await abrir(
      tester,
      StatusDisputa.acordo,
      filtro: 'Encerradas',
      decisao: DecisaoDisputa.reembolsoParcial,
      divisao: const DivisaoDisputa(
        paraClienteCentavos: 7500,
        paraProfissionalCentavos: 12500,
        retidoCentavos: 1000,
      ),
    );
    expect(find.textContaining('Acordo entre as partes', findRichText: true), findsOneWidget);
    expect(find.text('Devolvido ao cliente'), findsOneWidget);
    expect(find.textContaining('75,00', findRichText: true), findsOneWidget);
    expect(find.text('Liberado ao profissional'), findsOneWidget);
    expect(find.textContaining('125,00', findRichText: true), findsOneWidget);
    expect(find.text('Retido no acordo'), findsOneWidget);
    expect(find.textContaining('10,00', findRichText: true), findsOneWidget);
    expect(find.textContaining('retorno do provedor de pagamento', findRichText: true), findsOneWidget);
    await semAcoes(tester);
  });

  testWidgets('acordo sem devolução não mostra aviso do provedor nem retido zerado', (tester) async {
    await abrir(
      tester,
      StatusDisputa.acordo,
      filtro: 'Encerradas',
      limparDecisao: true,
      divisao: const DivisaoDisputa(
        paraClienteCentavos: 0,
        paraProfissionalCentavos: 20000,
        retidoCentavos: 0,
      ),
    );
    expect(find.text('Acordo entre as partes'), findsOneWidget);
    expect(find.text('Liberado ao profissional'), findsOneWidget);
    expect(find.text('Retido no acordo'), findsNothing);
    expect(find.textContaining('provedor de pagamento', findRichText: true), findsNothing);
    await semAcoes(tester);
  });

  testWidgets('acordo antigo sem divisão nem decisão não quebra a tela', (tester) async {
    await abrir(tester, StatusDisputa.acordo, filtro: 'Encerradas', limparDecisao: true);
    expect(find.text('Encerrada por acordo'), findsWidgets);
    expect(find.text('Devolvido ao cliente'), findsNothing);
    expect(find.textContaining('provedor de pagamento', findRichText: true), findsNothing);
    await semAcoes(tester);
  });

  testWidgets('acordo e desconhecido cabem no celular', (tester) async {
    await abrir(tester, StatusDisputa.acordo, filtro: 'Encerradas', largura: 360);
    expect(tester.takeException(), isNull);
  });

  test('API: "acordo", estado novo e estado ausente', () async {
    Object? estado;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        return http.Response(
            jsonEncode({
              'pedido_id': 'p1',
              'pedido_numero': 1,
              'motivo': 'mal_feito',
              'valor_congelado_centavos': 100,
              'decisao_ate': '2026-12-01T10:00:00Z',
              'estado': estado,
              'decisao': 'algo_novo',
            }),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    for (final (codigo, esperado) in [
      ('acordo', StatusDisputa.acordo),
      ('decidida', StatusDisputa.decidida),
      ('em_analise', StatusDisputa.emAnalise),
      ('estado_do_futuro', StatusDisputa.desconhecida),
      (null, StatusDisputa.desconhecida),
    ]) {
      estado = codigo;
      final d = await api.obterDisputa('p1');
      expect(d.status, esperado, reason: '$codigo');
      expect(d.decisao, isNull);
    }
    expect(StatusDisputa.acordo.encerrada, isTrue);
    expect(StatusDisputa.acordo.aceitaDecisao, isFalse);
    expect(StatusDisputa.desconhecida.aceitaDecisao, isFalse);
  });

  test('API: acordo lê divisão, decisão sem decidido_por, proposta_retorno e evento', () async {
    Map<String, dynamic> resposta = {
      'pedido_id': 'p1',
      'pedido_numero': 10,
      'motivo': 'atraso',
      'valor_congelado_centavos': 20000,
      'decisao_ate': '2026-12-01T10:00:00Z',
      'estado': 'acordo',
      'decisao': 'reembolso_parcial',
      'decidido_por': null,
      'divisao': {
        'para_cliente_centavos': 6000,
        'para_profissional_centavos': 14000,
        'retido_centavos': 0,
      },
      'evidencias': [
        {
          'origem': 'proposta_retorno',
          'em': '2026-11-26T10:00:00Z',
          'ator_papel': 'profissional',
          'dados': {'valor': 6000},
        },
      ],
      'linha_do_tempo': [
        {
          'em': '2026-11-26T11:00:00Z',
          'tipo': 'pedido',
          'acao': 'encerrar_disputa_por_acordo',
          'ator_papel': 'cliente',
        },
      ],
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        return http.Response(jsonEncode(resposta), 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final d = await api.obterDisputa('p1');
    expect(d.status, StatusDisputa.acordo);
    expect(d.decisao, DecisaoDisputa.reembolsoParcial);
    expect(d.decididoPor, isNull);
    expect(d.divisao?.paraClienteCentavos, 6000);
    expect(d.divisao?.paraProfissionalCentavos, 14000);
    expect(d.divisao?.retidoCentavos, 0);
    expect(d.evidencias.single.tipo, 'Proposta de acordo');
    expect(d.linhaDoTempo.single.texto, 'Disputa encerrada por acordo entre as partes');

    resposta = {
      'pedido_id': 'p2',
      'pedido_numero': 11,
      'motivo': 'atraso',
      'valor_congelado_centavos': 10000,
      'decisao_ate': '2026-12-01T10:00:00Z',
      'estado': 'acordo',
      'decisao': null,
      'decidido_por': null,
      'divisao': null,
    };
    final antigo = await api.obterDisputa('p2');
    expect(antigo.status, StatusDisputa.acordo);
    expect(antigo.decisao, isNull);
    expect(antigo.divisao, isNull);
  });
}
