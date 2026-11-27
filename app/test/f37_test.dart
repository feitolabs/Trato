import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/config_publica.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/main.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/detalhe_valores_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

const _porQue =
    'O valor fica guardado até o cliente confirmar o serviço e o prazo de reclamação terminar. '
    'Depois é repassado à sua conta cadastrada. Sem taxa.';

void main() {
  tearDown(() => ConfigPublica.atual = const ConfigPublica());

  group('F37 (A) · Carteira: "Cai na sua conta em dd/mm" e "Por quê?"', () {
    test('texto com e sem data, sem horas e sem 7 dias de retrabalho', () {
      expect(textoRegraLiberacao(DateTime(2026, 11, 27)), 'Cai na sua conta em 27/11');
      final semData = textoRegraLiberacao(null);
      expect(semData, 'Cai na sua conta depois que o cliente confirmar o serviço');
      for (final t in [
        textoRegraLiberacao(DateTime(2026, 11, 27)),
        semData,
        textoPorQueLiberacao
      ]) {
        expect(t, isNot(contains('retrabalho')));
        expect(t, isNot(contains('7 dias')));
        expect(t, isNot(matches(RegExp(r'\d+ horas?'))));
      }
      // Mesmo com a configuração pedindo 7 dias, o texto não muda (sem fallback de 7 dias).
      ConfigPublica.atual = const ConfigPublica(prazoLiberacaoDias: 7);
      expect(textoRegraLiberacao(null), semData);
    });

    testWidgets('Carteira: data da API e toque em "Por quê?" abre a explicação', (tester) async {
      await _abrir(
        tester,
        CarteiraTela(dados: DadosCarteira(proximaLiberacao: DateTime(2026, 11, 27))),
      );
      expect(find.text('Cai na sua conta em 27/11'), findsOneWidget);
      expect(find.textContaining('retrabalho'), findsNothing);
      expect(find.text(_porQue), findsNothing);

      await tester.tap(find.byKey(const Key('regra-liberacao-por-que')));
      await tester.pumpAndSettle();
      expect(find.text(_porQue), findsOneWidget);
      await tester.tap(find.text('Entendi'));
      await tester.pumpAndSettle();
      expect(find.text(_porQue), findsNothing);
    });

    testWidgets('Valores do pedido também mostra a data e o "Por quê?"', (tester) async {
      await _abrir(
        tester,
        DetalheValoresTela(
          carregar: () async => DetalheValoresPedido(
            pedidoNumero: '#AB12',
            pagoPeloClienteCentavos: 10000,
            voceRecebeCentavos: 10000,
            situacao: 'Retido até o cliente confirmar o serviço.',
            liberaEm: DateTime(2026, 12, 3),
          ),
        ),
      );
      expect(find.text('Cai na sua conta em 03/12'), findsOneWidget);
      await tester.tap(find.byKey(const Key('regra-liberacao-por-que')));
      await tester.pumpAndSettle();
      expect(find.text(_porQue), findsOneWidget);
    });
  });

  test('F37 (B) · prazo de confirmação do cliente diz o que acontece se ele não responder',
      () async {
    final api = ClienteApi(
      urlBase: 'https://api.teste/',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((r) async {
        Object corpo = <Object>[];
        if (r.url.path == '/v1/pedidos/p1') {
          corpo = {
            'id': 'p1',
            'estado': 'em_confirmacao',
            'estado_nome': 'Em confirmação',
            'cliente_id': 'c1',
            'profissional_id': 'me',
            'aberto_em': '2026-11-07T12:00:00Z',
            'acoes_permitidas': <String>['abrir_disputa', 'confirmar_conclusao'],
          };
        } else if (r.url.path == '/v1/pedidos/p1/saldo') {
          corpo = {
            'cliente_pagou_centavos': 10000,
            'retido_centavos': 0,
            'a_liberar_centavos': 0,
            'liberado_centavos': 0,
          };
        } else if (r.url.path == '/v1/pedidos/p1/eventos') {
          corpo = [
            {'acao': 'fazer_check_out', 'para': 'em_confirmacao', 'em': '2026-11-21T15:00:00Z'},
          ];
        }
        return http.Response(
          jsonEncode(corpo),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final r = await RepositorioPedidosApi(api).conclusao('p1');
    final prazo = r.prazoConfirmacao!;
    expect(prazo, startsWith('Você tem 48 horas para confirmar, até '));
    expect(
      prazo,
      endsWith(
        'Se você não responder, o serviço é confirmado e o pagamento é liberado ao profissional.',
      ),
    );
  });

  group('F37 (C) · Frase nº 1 do app', () {
    testWidgets('splash: nome Trato e a frase principal', (tester) async {
      await tester.pumpWidget(const TratoApp());
      expect(find.text('Trato'), findsOneWidget);
      expect(find.text('Conectando Clientes a Profissionais de Qualidade.'), findsOneWidget);
      expect(find.text('Toque para começar'), findsOneWidget);
    });

    testWidgets('login: frase sob o nome, com o título e o botão Entrar', (tester) async {
      await _abrir(tester, const LoginTela());
      expect(find.text('Trato'), findsOneWidget);
      expect(find.byKey(const Key('frase-principal')), findsOneWidget);
      expect(find.text('Conectando Clientes a Profissionais de Qualidade.'), findsOneWidget);
      expect(find.text('Entrar na sua conta'), findsOneWidget);
    });
  });
}
