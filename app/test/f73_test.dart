import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';

PedidoEmExecucao _pedido(String estado) => PedidoEmExecucao(
      numero: '#4821',
      titulo: 'Trocar disjuntor',
      etapas: const [],
      fotos: const [],
      estadoApi: estado,
    );

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    RotasTrato.repos = repositoriosDemo();
    RotasTrato.salvarPdfParaTeste = null;
    RotasTrato.compartilharArquivo = (_) async {};
  });

  group('Tela do pedido: botão "Baixar recibo (PDF)"', () {
    testWidgets('aparece no pedido concluído e chama o callback', (tester) async {
      var baixou = 0;
      await _abrir(
        tester,
        PedidoExecucaoTela(pedido: _pedido('concluido'), aoBaixarComprovante: () => baixou++),
      );
      expect(find.text('Baixar recibo (PDF)'), findsOneWidget);
      await tester.tap(find.text('Baixar recibo (PDF)'));
      expect(baixou, 1);
    });

    for (final estado in ['agendado', 'em_andamento', 'em_confirmacao', 'cancelado']) {
      testWidgets('não aparece com o pedido em "$estado"', (tester) async {
        await _abrir(
          tester,
          PedidoExecucaoTela(pedido: _pedido(estado), aoBaixarComprovante: () {}),
        );
        expect(find.text('Baixar recibo (PDF)'), findsNothing);
      });
    }

    testWidgets('sem o callback o botão não aparece mesmo concluído', (tester) async {
      await _abrir(tester, PedidoExecucaoTela(pedido: _pedido('concluido')));
      expect(find.text('Baixar recibo (PDF)'), findsNothing);
    });
  });

  group('Repositório: GET /v1/pedidos/{id}/recibo.pdf com o token do usuário', () {
    test('chama o caminho do recibo com Authorization e devolve os bytes', () async {
      late http.Request pedida;
      final sessao = SessaoTrato()..entrar('token-de-teste');
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: sessao,
        cliente: MockClient((req) async {
          pedida = req;
          return http.Response.bytes(
            utf8.encode('%PDF-1.4\n%%EOF'),
            200,
            headers: const {'content-type': 'application/pdf'},
          );
        }),
      );

      final bytes = await RepositorioPedidosApi(api).baixarReciboPdf('ped-9');

      expect(pedida.method, 'GET');
      expect(pedida.url.path, '/v1/pedidos/ped-9/recibo.pdf');
      expect(pedida.headers['Authorization'], 'Bearer token-de-teste');
      expect(utf8.decode(bytes), startsWith('%PDF-1.4'));
    });
  });

  group('Rota: salva, avisa e oferece compartilhar', () {
    Future<void> abrirComBotao(WidgetTester tester) async {
      await _abrir(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => RotasTrato.baixarReciboPdfParaTeste(context, 'ped-7'),
              child: const Text('baixar'),
            ),
          ),
        ),
      );
    }

    testWidgets('pede o PDF do pedido, salva com nome do pedido e compartilha', (tester) async {
      RotasTrato.repos = repositoriosDemo();
      String? salvo;
      String? compartilhado;
      RotasTrato.salvarPdfParaTeste = (bytes, arquivo) async => salvo = '/tmp/$arquivo';
      RotasTrato.compartilharArquivo = (c) async => compartilhado = c;
      await abrirComBotao(tester);

      await tester.tap(find.text('baixar'));
      await tester.pumpAndSettle();

      final repo = RotasTrato.repos.pedidos as RepositorioPedidosFake;
      expect(repo.recibosBaixados, ['ped-7']);
      expect(salvo, '/tmp/trato_comprovante_ped-7.pdf');
      expect(find.text('Recibo em PDF salvo.'), findsOneWidget);
      await tester.tap(find.text('Compartilhar'));
      await tester.pumpAndSettle();
      expect(compartilhado, '/tmp/trato_comprovante_ped-7.pdf');
    });

    testWidgets('falha do servidor mostra a mensagem, sem travar', (tester) async {
      RotasTrato.repos = repositoriosDemo();
      RotasTrato.salvarPdfParaTeste = (bytes, arquivo) async => throw const ErroTrato(
            TipoErro.recusado,
            'Comprovante indisponível para este pedido.',
          );
      await abrirComBotao(tester);
      await tester.tap(find.text('baixar'));
      await tester.pumpAndSettle();
      expect(find.text('Comprovante indisponível para este pedido.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
