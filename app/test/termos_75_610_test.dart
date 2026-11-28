// Termos 7.5 (aviso do reagendamento) e 6.10 (status e prazo do estorno no pedido).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/conta_bloqueada/pedidos_contratados.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pagamento/estorno_pedido.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/reagendamento.dart';

import 'apoio/exemplos/demo.dart';

const _aviso = 'Aviso do servidor sobre menos de 24 horas.';

Map<String, Object?> _proposta([Object? aviso]) => {
      'id': 'r1',
      'proposto_por': 'u1',
      'nova_janela_inicio': '2026-12-01T12:00:00Z',
      'nova_janela_fim': '2026-12-01T14:00:00Z',
      'status': 'pendente',
      if (aviso != null) 'aviso_prazo': aviso,
    };

RepositorioPedidosApi _repo(int codigo, Object corpo, [List<String>? rotas]) =>
    RepositorioPedidosApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        rotas?.add(r.url.path);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), codigo,
            headers: const {'content-type': 'application/json'});
      }),
    ));

Future<void> _abrir(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(320, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

void main() {
  test('aviso_prazo: lido do servidor; ausente, vazio ou de outro tipo vira nulo', () {
    expect(Reagendamento.deJson(_proposta(_aviso))!.avisoPrazo, _aviso);
    for (final v in <Object?>[null, '  ', 5]) {
      expect(Reagendamento.deJson(_proposta(v))!.avisoPrazo, isNull);
    }
  });

  for (final (quem, meuId) in [('quem propôs', 'u1'), ('quem responde', 'u2')]) {
    testWidgets('cartão mostra o aviso do servidor para $quem', (t) async {
      await _abrir(
        t,
        SecaoReagendamento(
          meuId: meuId,
          carregar: () async => [Reagendamento.deJson(_proposta(_aviso))!],
          propor: (_, __, ___) async {},
          aceitar: (_) async {},
          recusar: (_) async {},
        ),
      );
      expect(find.text(_aviso), findsOneWidget);
    });
  }

  testWidgets('sem aviso_prazo o cartão fica como antes', (t) async {
    await _abrir(
      t,
      SecaoReagendamento(
        carregar: () async => [Reagendamento.deJson(_proposta())!],
        propor: (_, __, ___) async {},
        aceitar: (_) async {},
        recusar: (_) async {},
      ),
    );
    expect(find.byKey(const ValueKey('aviso-prazo-reagendamento')), findsNothing);
    expect(find.byKey(const ValueKey('aceitar-nova-data')), findsOneWidget);
  });

  test('ao propor, o aviso vem da resposta do envio, com uma só chamada', () async {
    final rotas = <String>[];
    final aviso = await _repo(201, _proposta(_aviso), rotas).proporReagendamentoComAviso('p1',
        inicio: DateTime(2026, 12, 1, 9), fim: DateTime(2026, 12, 1, 11));
    expect(aviso, _aviso);
    expect(rotas, ['/v1/pedidos/p1/reagendamentos']);
    expect(
        await _repo(201, _proposta()).proporReagendamentoComAviso('p1',
            inicio: DateTime(2026, 12, 1, 9), fim: DateTime(2026, 12, 1, 11)),
        isNull);
  });

  test('estornos vêm das cobranças do pedido; sem estorno_status não entram', () async {
    final rotas = <String>[];
    final itens = await _repo(
            200,
            [
              {
                'id': 'a',
                'valor_centavos': 15000,
                'meio': 'pix',
                'estorno_status': 'concluido',
                'estorno_prazo_estimado': 'Prazo do servidor.'
              },
              {'id': 'b', 'valor_centavos': 2000, 'meio': 'cartao'},
              {'id': 'c', 'estorno_status': 'solicitado'},
            ],
            rotas)
        .estornosDoPedido('p1');
    expect(rotas, ['/v1/pedidos/p1/cobrancas']);
    expect(itens.map((e) => e.status), ['concluido', 'solicitado']);
    expect(itens.first.textoCobranca, contains('150,00 no Pix'));
    expect(itens.last.textoCobranca, isNull);
    expect(itens.last.prazoEstimado, isNull);
  });

  test('404 de servidor antigo vira lista vazia', () async {
    expect(await _repo(404, {'detail': 'Not Found'}).estornosDoPedido('p1'), isEmpty);
  });

  testWidgets('seção mostra status, cobrança e prazo', (t) async {
    await _abrir(
      t,
      SecaoEstorno(
        carregar: () async => const [
          EstornoDoPedido(
              status: 'em_processamento',
              prazoEstimado: 'Prazo do servidor.',
              cobrancaCentavos: 15000,
              meio: 'cartao'),
        ],
      ),
    );
    expect(find.text('Estorno em processamento'), findsOneWidget);
    expect(find.text('Prazo do servidor.'), findsOneWidget);
    expect(find.textContaining('150,00 no cartão'), findsOneWidget);
  });

  test('valor e datas: rótulos honestos; ausentes ou inválidos somem', () {
    final e = EstornoDoPedido.deJson({
      'estorno_status': 'em_processamento',
      'valor_centavos': 15000,
      'estorno_valor_centavos': 5000,
      'estorno_solicitado_em': '2026-11-20T15:00:00Z',
      'estorno_enviado_em': '2026-11-21T15:00:00Z',
    })!;
    final tudo = e.linhas.join(' | ');
    expect(tudo, matches(RegExp(r'Valor mandado devolver: R\$\s50,00')));
    expect(tudo, contains('Estorno registrado em 20/11/2026'));
    expect(tudo, contains('Enviado ao provedor de pagamento em 21/11/2026'));
    expect(tudo, contains('não é a data em que o dinheiro cai'));
    expect(tudo.toLowerCase(), isNot(contains('reembolsado')));
    // Estorno feito por fora: valor sem datas.
    final semDatas =
        EstornoDoPedido.deJson({'estorno_status': 'concluido', 'estorno_valor_centavos': 5000})!;
    expect(semDatas.linhas, hasLength(1));
    final antigo = EstornoDoPedido.deJson({
      'estorno_status': 'solicitado',
      'estorno_valor_centavos': null,
      'estorno_solicitado_em': 'ontem',
      'estorno_enviado_em': 7,
    })!;
    expect(antigo.linhas, isEmpty);
  });

  test('conta bloqueada em servidor antigo (403): nada a mostrar', () async {
    expect(
        await _repo(403, {'detail': 'Conta bloqueada.', 'codigo': 'conta_bloqueada'})
            .estornosDoPedido('p1'),
        isEmpty);
  });

  testWidgets('conta bloqueada: a tela reduzida consulta e mostra o estorno', (t) async {
    final antes = RotasTrato.repos;
    addTearDown(() {
      RotasTrato.repos = antes;
      RotasTrato.esquecerBloqueio();
    });
    final chamadas = <String>[];
    RotasTrato.repos = repositoriosDemo(
      pedidos: RepositorioPedidosApi(ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((r) async {
          chamadas.add('${r.method} ${r.url.path}');
          const pedido = {'id': 'p1', 'estado': 'cancelado', 'estado_nome': 'Cancelado'};
          final Object? corpo = switch (r.url.path) {
            '/v1/pedidos' => [pedido],
            '/v1/pedidos/p1' => pedido,
            '/v1/pedidos/p1/cobrancas' => [
                {
                  'valor_centavos': 15000,
                  'meio': 'pix',
                  'instrucao': null,
                  'estorno_status': 'solicitado',
                  'estorno_valor_centavos': 15000,
                }
              ],
            _ => null,
          };
          return http.Response.bytes(
              utf8.encode(jsonEncode(corpo ?? {'detail': 'Nada.'})), corpo == null ? 404 : 200,
              headers: const {'content-type': 'application/json'});
        }),
      )),
    );
    final nav = GlobalKey<NavigatorState>();
    t.view.physicalSize = const Size(320, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t
        .pumpWidget(MaterialApp(theme: TemaTrato.claro, navigatorKey: nav, home: const Scaffold()));
    RotasTrato.contaFoiBloqueada(() => nav.currentState, 'Conta bloqueada.');
    await t.pumpAndSettle();
    RotasTrato.abrirPedidoContratado(nav.currentState!.overlay!.context, 'p1');
    await t.pumpAndSettle();
    expect(find.byType(PedidoContratadoTela), findsOneWidget);
    expect(find.text('Estorno solicitado', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Valor mandado devolver', skipOffstage: false), findsOneWidget);
    expect(chamadas, contains('GET /v1/pedidos/p1/cobrancas'));
    expect(chamadas.where((c) => !c.startsWith('GET ')), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('seção sem estorno não mostra nada', (t) async {
    await _abrir(t, SecaoEstorno(carregar: () async => const []));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('falha mostra o erro e "Tentar de novo" recupera', (t) async {
    var falhar = true;
    await _abrir(
      t,
      SecaoEstorno(
        carregar: () async {
          if (falhar) throw ErroTrato.semInternet;
          return const [EstornoDoPedido(status: 'falhou')];
        },
      ),
    );
    expect(find.byKey(const ValueKey('erro-estorno-pedido')), findsOneWidget);
    falhar = false;
    await t.tap(find.byKey(const ValueKey('tentar-estorno-pedido')));
    await t.pumpAndSettle();
    expect(find.text('Falha no estorno'), findsOneWidget);
  });
}
