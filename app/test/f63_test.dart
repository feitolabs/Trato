import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/tema/tema.dart';

Widget _envolver(Widget child) => MaterialApp(theme: TemaTrato.claro, home: child);

void main() {
  group('F63 — Carteira do profissional (sem card Pix duplicado e ?como=profissional)', () {
    testWidgets(
        '1. Sem conta Pix cadastrada: mostra "Cadastrar conta de recebimento" no topo e NÃO mostra card duplicado abaixo',
        (tester) async {
      var abriuCadastroConta = false;
      final resumo = resumoCarteiraDoSaldo(
        liberadoCentavos: 0,
        retidoCentavos: 15000,
        aLiberarCentavos: 0,
      );

      await tester.pumpWidget(
        _envolver(
          CarteiraTela(
            soExtrato: false,
            dados: DadosCarteira(
              resumo: resumo,
              contaRecebimento: const ContaRecebimento(cadastrada: false),
            ),
            aoConfigurarRecebimento: () => abriuCadastroConta = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cadastre sua conta Pix para receber'), findsOneWidget);
      expect(find.text('Cadastrar conta de recebimento'), findsOneWidget);
      // O segundo card duplicado não deve aparecer.
      expect(find.text('Cadastre sua conta Pix'), findsNothing);
      expect(find.text('Informe sua chave Pix para receber os repasses liberados.'), findsNothing);

      await tester.tap(find.text('Cadastrar conta de recebimento'));
      await tester.pumpAndSettle();
      expect(abriuCadastroConta, isTrue);
    });

    testWidgets(
        '2. Com conta Pix cadastrada: exibe o card "Conta de recebimento ativa" com botão "Alterar"',
        (tester) async {
      var abriuAlterar = false;
      const conta = ContaRecebimento(
        cadastrada: true,
        tipoPix: 'cpf',
        chavePixMascarada: '***.456.789-**',
      );
      final resumo = resumoCarteiraDoSaldo(
        liberadoCentavos: 25000,
        retidoCentavos: 0,
        aLiberarCentavos: 0,
        conta: conta,
      );

      await tester.pumpWidget(
        _envolver(
          CarteiraTela(
            soExtrato: false,
            dados: DadosCarteira(
              resumo: resumo,
              contaRecebimento: conta,
            ),
            aoConfigurarRecebimento: () => abriuAlterar = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conta de recebimento ativa'), findsOneWidget);
      expect(find.text('Alterar'), findsOneWidget);

      await tester.ensureVisible(find.text('Alterar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alterar'));
      await tester.pumpAndSettle();
      expect(abriuAlterar, isTrue);
    });

    test('3. RepositorioProfissionalApi.extrato envia consulta como=profissional em GET /v1/extrato',
        () async {
      Uri? uriChamada;
      final httpMock = MockClient((req) async {
        uriChamada = req.url;
        return http.Response(
          jsonEncode({
            'total': 1,
            'itens': [
              {
                'id': 'l1',
                'pedido_id': 'ped-1234',
                'tipo': 'repasse',
                'valor_centavos': 18000,
                'data': '2026-11-22T15:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final api = ClienteApi(
        urlBase: 'https://api.trato.teste',
        sessao: SessaoTrato()..entrar('tok-prof'),
        intervaloBaseRetry: Duration.zero,
        cliente: httpMock,
      );
      final repo = RepositorioProfissionalApi(api);
      final itens = await repo.extrato(limite: 20, deslocamento: 0);

      expect(uriChamada, isNotNull);
      expect(uriChamada!.path, '/v1/extrato');
      expect(uriChamada!.queryParameters['como'], 'profissional');
      expect(uriChamada!.queryParameters['limite'], '20');
      expect(itens, hasLength(1));
    });
  });
}
