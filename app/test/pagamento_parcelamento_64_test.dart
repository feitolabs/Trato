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

  group('Taxa de juros do parcelamento (6.4)', () {
    Future<List<OpcaoParcelamento>> ler(List<Map<String, Object?>> extras) async {
      final api = _apiSimulado((req) async {
        if (req.url.path == '/v1/me') return _json({'cpf_cadastrado': true});
        return _json({
          'valor_centavos': 10000,
          'total_a_pagar_centavos': 10000,
          'meios_disponiveis': ['cartao'],
          'opcoes_parcelamento': [
            for (final extra in extras)
              {
                'parcelas': 2,
                'custo_centavos': 300,
                'total_centavos': 10300,
                'valor_parcela_centavos': 5150,
                ...extra,
              },
          ],
        });
      });
      return (await RepositorioPagamentoApi(api).dados('p1')).parcelamento;
    }

    test('lê juros_mensal_bps e só formata a taxa do servidor', () async {
      final p = (await ler([
        {'juros_mensal_bps': 199, 'sem_juros': false, 'diferenca_a_vista_centavos': 300},
      ]))
          .single;
      expect(p.jurosMensalBps, 199);
      expect(textoTituloParcela(p), '2x de R\$ 51,50');
      expect(
        textoDetalheParcela(p),
        'Juros de 1,99% ao mês. Total R\$ 103,00. '
        'R\$ 3,00 a mais que à vista (custo do parcelamento).',
      );
    });

    test('campos ausentes, nulos ou inválidos: sem taxa e sem "sem juros"', () async {
      final opcoes = await ler([
        {},
        {'juros_mensal_bps': null, 'sem_juros': null},
        {'juros_mensal_bps': '199', 'sem_juros': 'true'},
      ]);
      for (final p in opcoes) {
        final texto = '${textoTituloParcela(p)} ${textoDetalheParcela(p)}';
        expect(texto, isNot(contains('juros')));
        expect(texto, isNot(contains('ao mês')));
      }
    });

    test('sem_juros mostra "sem juros"; com taxa junto, não afirma nenhum dos dois', () async {
      final opcoes = await ler([
        {'juros_mensal_bps': 0, 'sem_juros': true, 'diferenca_a_vista_centavos': 0},
        {'juros_mensal_bps': 199, 'sem_juros': true},
      ]);
      expect(textoTituloParcela(opcoes[0]), endsWith('sem juros'));
      expect(textoDetalheParcela(opcoes[0]), isNot(contains('ao mês')));
      expect(textoTituloParcela(opcoes[1]), isNot(contains('juros')));
      expect(textoDetalheParcela(opcoes[1]), isNot(contains('ao mês')));
    });

    testWidgets('a tela mostra a taxa antes de confirmar (320 px, fonte 1,3x)', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: PagamentoTela(
            dados: const DadosPagamento(
              subtitulo: 'Pedido de exemplo',
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
                  custoCentavos: 300,
                  totalCentavos: 10300,
                  valorParcelaCentavos: 5150,
                  diferencaAVistaCentavos: 300,
                  semJuros: false,
                  jurosMensalBps: 199,
                ),
              ],
            ),
            aoPagarDetalhado: (_, __, ___) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      final lista = find.byType(Scrollable).first;
      final cartao = find.text('Cartão');
      await t.scrollUntilVisible(cartao, 150, scrollable: lista);
      await t.ensureVisible(cartao);
      await t.pumpAndSettle();
      await t.tap(cartao);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('parcela-2')), 100, scrollable: lista);

      expect(find.text('2x de R\$ 51,50'), findsOneWidget);
      expect(find.textContaining('Juros de 1,99% ao mês. Total R\$ 103,00.'), findsOneWidget);
      expect(find.textContaining('R\$ 3,00 a mais que à vista'), findsOneWidget);
      expect(t.takeException(), isNull);
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
