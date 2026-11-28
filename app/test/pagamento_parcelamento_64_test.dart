// FL-PARCELAS-6.4: mapeamento e exibição dos novos campos de parcelamento (Termos 6.4).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';

import 'apoio/fontes.dart';

ClienteApi _apiSimulado(Future<http.Response> Function(http.Request) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient(responder),
    );

http.Response _json(Map<String, Object?> corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(carregarFontesTrato);

  group('RepositorioPagamentoApi — novos campos de parcelamento (6.4)', () {
    test('mapeia valores_parcelas_centavos, ultima_parcela, custo_total_bps, diferenca e sem_juros',
        () async {
      final api = _apiSimulado((req) async {
        if (req.url.path == '/v1/me') {
          return _json({'cpf_cadastrado': true});
        }
        return _json({
          'valor_centavos': 10000,
          'total_a_pagar_centavos': 10000,
          'meios_disponiveis': ['cartao'],
          'opcoes_parcelamento': [
            {
              'parcelas': 2,
              'custo_centavos': 0,
              'total_centavos': 10000,
              'valor_parcela_centavos': 5000,
              'valores_parcelas_centavos': [5000, 5000],
              'ultima_parcela_centavos': 5000,
              'custo_total_bps': 0,
              'diferenca_a_vista_centavos': 0,
              'sem_juros': true,
            },
            {
              'parcelas': 3,
              'custo_centavos': 450,
              'total_centavos': 10450,
              'valor_parcela_centavos': 3483,
              'valores_parcelas_centavos': [3483, 3483, 3484],
              'ultima_parcela_centavos': 3484,
              'custo_total_bps': 450,
              'diferenca_a_vista_centavos': 450,
              'sem_juros': false,
            },
          ],
        });
      });

      final dados = await RepositorioPagamentoApi(api).dados('p1');
      expect(dados.parcelamento, hasLength(2));

      final p2 = dados.parcelamento[0];
      expect(p2.valoresParcelasCentavos, [5000, 5000]);
      expect(p2.ultimaParcelaCentavos, 5000);
      expect(p2.custoTotalBps, 0);
      expect(p2.diferencaAVistaCentavos, 0);
      expect(p2.semJuros, isTrue);

      final p3 = dados.parcelamento[1];
      expect(p3.valoresParcelasCentavos, [3483, 3483, 3484]);
      expect(p3.ultimaParcelaCentavos, 3484);
      expect(p3.custoTotalBps, 450);
      expect(p3.diferencaAVistaCentavos, 450);
      expect(p3.semJuros, isFalse);
    });

    test('fallback seguro quando backend antigo omite os campos novos', () async {
      final api = _apiSimulado((req) async {
        if (req.url.path == '/v1/me') {
          return _json({'cpf_cadastrado': true});
        }
        return _json({
          'valor_centavos': 10000,
          'total_a_pagar_centavos': 10000,
          'meios_disponiveis': ['cartao'],
          'opcoes_parcelamento': [
            {
              'parcelas': 2,
              'custo_centavos': 300,
              'total_centavos': 10300,
              'valor_parcela_centavos': 5150,
            },
          ],
        });
      });

      final dados = await RepositorioPagamentoApi(api).dados('p1');
      final p2 = dados.parcelamento.single;
      expect(p2.valoresParcelasCentavos, isEmpty);
      expect(p2.ultimaParcelaCentavos, isNull);
      expect(p2.custoTotalBps, isNull);
      expect(p2.diferencaAVistaCentavos, isNull);
      expect(p2.semJuros, isNull);
    });
  });

  group('PagamentoTela — exibição de parcelamento (6.4)', () {
    testWidgets(
      'mostra sem juros, custo total único (sem taxa mensal) e última parcela diferente',
      (t) async {
        t.view.physicalSize = const Size(360, 760);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.2;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

        await t.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            home: PagamentoTela(
              dados: const DadosPagamento(
                subtitulo: 'Pedido #42',
                valorAgoraCentavos: 10000,
                opcoes: [
                  OpcaoPagamento(
                    metodo: MetodoPagamento.cartao,
                    titulo: 'Cartão',
                    descricao: 'Crédito',
                  ),
                ],
                parcelamento: [
                  OpcaoParcelamento(
                    parcelas: 2,
                    custoCentavos: 0,
                    totalCentavos: 10000,
                    valorParcelaCentavos: 5000,
                    valoresParcelasCentavos: [5000, 5000],
                    ultimaParcelaCentavos: 5000,
                    custoTotalBps: 0,
                    diferencaAVistaCentavos: 0,
                    semJuros: true,
                  ),
                  OpcaoParcelamento(
                    parcelas: 3,
                    custoCentavos: 0,
                    totalCentavos: 10000,
                    valorParcelaCentavos: 3333,
                    valoresParcelasCentavos: [3333, 3333, 3334],
                    ultimaParcelaCentavos: 3334,
                    custoTotalBps: 0,
                    diferencaAVistaCentavos: 0,
                    semJuros: true,
                  ),
                  OpcaoParcelamento(
                    parcelas: 4,
                    custoCentavos: 450,
                    totalCentavos: 10450,
                    valorParcelaCentavos: 2612,
                    valoresParcelasCentavos: [2612, 2612, 2612, 2614],
                    ultimaParcelaCentavos: 2614,
                    custoTotalBps: 450,
                    diferencaAVistaCentavos: 450,
                    semJuros: false,
                  ),
                ],
              ),
              aoPagarDetalhado: (_, __, ___) async {},
            ),
          ),
        );
        await t.pumpAndSettle();

        final cartao = find.text('Cartão');
        await t.scrollUntilVisible(cartao, 150, scrollable: find.byType(Scrollable).first);
        await t.tap(cartao);
        await t.pumpAndSettle();

        // 2x sem juros com parcelas iguais: não exibe aviso de última parcela.
        await t.scrollUntilVisible(
          find.byKey(const Key('parcela-2')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('2x de R\$ 50,00 sem juros'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('parcela-2')),
            matching: find.textContaining('Última parcela'),
          ),
          findsNothing,
        );

        // 3x sem juros com resto na última parcela.
        await t.scrollUntilVisible(
          find.byKey(const Key('parcela-3')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('3x de R\$ 33,33 sem juros'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('parcela-3')),
            matching: find.textContaining('Última parcela de R\$ 33,34 (fecha o total exato).'),
          ),
          findsOneWidget,
        );

        // 4x com custo: mostra diferença em R$, custo total em % (sem taxa mensal) e última parcela.
        await t.scrollUntilVisible(
          find.byKey(const Key('parcela-4')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('4x de R\$ 26,12'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('parcela-4')),
            matching: find.textContaining('Última parcela de R\$ 26,14 (fecha o total exato).'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('parcela-4')),
            matching: find.textContaining(
              'R\$ 4,50 a mais que à vista (4,5% de custo total no parcelamento).',
            ),
          ),
          findsOneWidget,
        );

        // Nunca inventa taxa mensal.
        expect(find.textContaining('ao mês', skipOffstage: false), findsNothing);
        expect(find.textContaining('a.m.', skipOffstage: false), findsNothing);
        expect(find.textContaining('mensal', skipOffstage: false), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  });
}
