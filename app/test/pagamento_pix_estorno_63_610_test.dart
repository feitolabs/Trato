// FL-PIX-ESTORNO-6.3-6.10: prazo do Pix e status/prazo do estorno nas telas de pagamento.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';

import 'apoio/fontes.dart';

ClienteApi _apiSimulado(Future<http.Response> Function(http.Request) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient(responder),
    );

http.Response _json(Object corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(carregarFontesTrato);

  group('Mapeamento API — Pix (6.3) e Estorno (6.10)', () {
    test('criarCobranca mapeia pix_expira_em, pix_validade_minutos, estorno_status e prazo',
        () async {
      final api = _apiSimulado((_) async => _json({
            'cobranca_id': 'cob-pix-1',
            'tipo_instrucao': 'pix_copia_e_cola',
            'instrucao': '000201PIXTESTE',
            'pix_expira_em': '2026-11-27T21:30:00Z',
            'pix_validade_minutos': 30,
            'estorno_status': 'em_processamento',
            'estorno_prazo_estimado': 'Até 1 dia útil no Pix.',
          }, 201));

      final cob = await RepositorioPagamentoApi(api).criarCobranca('p1', MetodoPagamento.pix);
      expect(cob.pixExpiraEm, isNotNull);
      expect(cob.pixValidadeMinutos, 30);
      expect(cob.estornoStatus, 'em_processamento');
      expect(cob.estornoPrazoEstimado, 'Até 1 dia útil no Pix.');

      // Fallback seguro quando servidor antigo omite os 4 campos.
      final apiAntigo = _apiSimulado((_) async => _json({
            'cobranca_id': 'cob-pix-2',
            'tipo_instrucao': 'pix_copia_e_cola',
            'instrucao': '000201PIXOLD',
          }, 201));
      final cobAntiga =
          await RepositorioPagamentoApi(apiAntigo).criarCobranca('p1', MetodoPagamento.pix);
      expect(cobAntiga.pixExpiraEm, isNull);
      expect(cobAntiga.pixValidadeMinutos, isNull);
      expect(cobAntiga.estornoStatus, isNull);
      expect(cobAntiga.estornoPrazoEstimado, isNull);
    });

    test('rotuloEstornoStatus traduz todos os 4 status do backend', () {
      expect(rotuloEstornoStatus('solicitado'), 'Estorno solicitado');
      expect(rotuloEstornoStatus('em_processamento'), 'Estorno em processamento');
      expect(rotuloEstornoStatus('concluido'), 'Estorno concluído');
      expect(rotuloEstornoStatus('falhou'), 'Falha no estorno');
      expect(rotuloEstornoStatus(null), isNull);
    });
  });

  group('Telas de pagamento — exibição Pix (6.3) e Estorno (6.10)', () {
    testWidgets('AguardandoPagamentoTela exibe prazo do Pix e status/prazo do estorno', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: AguardandoPagamentoTela(
            cobranca: Cobranca(
              id: 'cob-1',
              pixCopiaECola: '000201PIXTESTE',
              pixExpiraEm: DateTime(2026, 11, 27, 21, 30),
              pixValidadeMinutos: 30,
              estornoStatus: 'solicitado',
              estornoPrazoEstimado: 'Devolução em até 1 dia útil.',
            ),
            consultar: () async => StatusPagamento.aguardando,
            aoConfirmar: () {},
            intervalo: const Duration(hours: 1),
          ),
        ),
      );
      await t.pump();

      expect(find.byKey(const Key('pix-prazo-validade')), findsOneWidget);
      expect(find.text('Pix válido por 30 minutos (até 27/11, 21:30).'), findsOneWidget);
      expect(find.byKey(const Key('cartao-estorno-aguardando')), findsOneWidget);
      expect(find.text('Estorno solicitado'), findsOneWidget);
      expect(find.text('Devolução em até 1 dia útil.'), findsOneWidget);
    });

    testWidgets('PagamentoTela exibe prazo do Pix ao selecionar Pix e cartão de estorno',
        (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: PagamentoTela(
            dados: DadosPagamento(
              subtitulo: 'Pedido #77',
              valorAgoraCentavos: 15000,
              pixExpiraEm: DateTime(2026, 11, 27, 22, 0),
              pixValidadeMinutos: 15,
              estornoStatus: 'concluido',
              estornoPrazoEstimado: 'Estorno concluído na mesma conta.',
              opcoes: const [
                OpcaoPagamento(
                    metodo: MetodoPagamento.pix, titulo: 'Pix', descricao: 'Instantâneo'),
                OpcaoPagamento(
                    metodo: MetodoPagamento.cartao, titulo: 'Cartão', descricao: 'Crédito'),
              ],
            ),
            aoPagarDetalhado: (_, __, ___) async {},
          ),
        ),
      );
      await t.pumpAndSettle();

      // Estorno aparece independente do método.
      await t.scrollUntilVisible(
        find.byKey(const Key('pagamento-cartao-estorno')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Estorno concluído'), findsOneWidget);
      expect(find.text('Estorno concluído na mesma conta.'), findsOneWidget);

      // Seleciona Pix -> mostra prazo do Pix.
      await t.scrollUntilVisible(
        find.text('Pix'),
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Pix'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pagamento-pix-prazo')), findsOneWidget);
      expect(find.text('Pix válido por 15 minutos (até 27/11, 22:00).'), findsOneWidget);
    });
  });
}
