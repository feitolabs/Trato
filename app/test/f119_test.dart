// APP-RETORNO209: pedido de retorno de conta encerrada (Termos 20.9).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/medidas/medidas_tela.dart';
import 'package:trato/telas/medidas/modelos.dart';
import 'package:trato/telas/medidas/retorno_conta.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _pedido = {
  'id': 'r1',
  'protocolo': 'RET-0001',
  'medida_id': 'm1',
  'justificativa_usuario': 'Quero voltar a trabalhar pelo app.',
  'canal': 'app',
  'status': 'recusado',
  'solicitado_em': '2026-11-20T15:00:00Z',
  'prazo_dias_aplicado': 120,
  'elegivel_a_partir_de': '2026-11-18T15:00:00Z',
  'decisao_motivo': 'Ainda há risco a outras pessoas.',
  'decidido_em': '2026-11-25T15:00:00Z',
};

Map<String, Object> _lista(List<Object> itens) => {'itens': itens, 'total': itens.length};

ServicoMedidasApi _api(
  (int, Object) Function(http.Request) responder, {
  List<http.Request>? pedidos,
  SessaoTrato? sessao,
}) =>
    ServicoMedidasApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: sessao ?? (SessaoTrato()..entrar('t')),
      cliente: MockClient((r) async {
        pedidos?.add(r);
        final (status, corpo) = responder(r);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
            headers: const {'content-type': 'application/json'});
      }),
    ));

Future<void> _abrir(WidgetTester t, Widget tela, {GlobalKey<NavigatorState>? nav}) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, navigatorKey: nav, home: tela));
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

final _enviar = find.byKey(const ValueKey('botao-enviar-retorno'));
final _campo = find.byKey(const ValueKey('justificativa-retorno'));

Future<void> _verFim(WidgetTester t) async {
  await t.scrollUntilVisible(_enviar, 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('mostra o pedido com o prazo do servidor e a decisão', (t) async {
    await _abrir(t, RetornoContaTela(servico: _api((_) => (200, _lista([_pedido])))));
    for (final texto in [
      'Recusado',
      'Prazo mínimo aplicado: 120 dias',
      'Podia pedir a partir de 18/11/2026',
      'Ainda há risco a outras pessoas.',
    ]) {
      expect(find.text(texto, skipOffstage: false), findsOneWidget, reason: texto);
    }
    expect(find.textContaining('90'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('pedido em andamento esconde o formulário', (t) async {
    await _abrir(
      t,
      RetornoContaTela(
        servico: _api((_) => (
              200,
              _lista([
                {..._pedido, 'status': 'em_analise'}
              ])
            )),
      ),
    );
    expect(find.text('Em análise'), findsOneWidget);
    expect(_campo, findsNothing);
  });

  testWidgets('envia a justificativa, valida o mínimo e recarrega', (t) async {
    final chamadas = <http.Request>[];
    var criado = false;
    await _abrir(
      t,
      RetornoContaTela(
        servico: _api((r) {
          if (r.method == 'POST') {
            criado = true;
            return (201, {..._pedido, 'status': 'aberto'});
          }
          return (
            200,
            _lista(criado
                ? [
                    {..._pedido, 'status': 'aberto'}
                  ]
                : [])
          );
        }, pedidos: chamadas),
      ),
    );
    expect(find.text('Você ainda não pediu o retorno.'), findsOneWidget);
    await _verFim(t);
    await t.enterText(_campo, 'curto');
    await _tocar(t, _enviar);
    expect(find.text('Escreva pelo menos 10 caracteres.'), findsOneWidget);
    expect(chamadas.where((r) => r.method == 'POST'), isEmpty);

    await t.enterText(_campo, '  Quero voltar a usar o app.  ');
    await _tocar(t, _enviar);
    final post = chamadas.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, '/v1/me/conta/retorno');
    expect(jsonDecode(post.body), {'justificativa': 'Quero voltar a usar o app.'});
    expect(find.text('Pedido de retorno registrado. Protocolo RET-0001.'), findsOneWidget);
    expect(find.text('Pedido recebido'), findsOneWidget);
    expect(_campo, findsNothing);
  });

  for (final (status, detalhe) in [
    (409, 'O prazo mínimo de 120 dias para solicitar o retorno ainda não foi cumprido.'),
    (403, 'Conta encerrada por infração grave não é elegível para pedido de retorno.'),
  ]) {
    testWidgets('erro $status no envio mostra o detail e mantém o texto', (t) async {
      await _abrir(
        t,
        RetornoContaTela(
          servico: _api(
            (r) => r.method == 'POST' ? (status, {'detail': detalhe}) : (200, _lista([])),
          ),
        ),
      );
      await _verFim(t);
      await t.enterText(_campo, 'Quero voltar a usar o app.');
      await _tocar(t, _enviar);
      expect(find.text(detalhe), findsOneWidget);
      expect(find.text('Quero voltar a usar o app.'), findsOneWidget);
    });
  }

  for (final status in [404, 503]) {
    testWidgets('servidor antigo ($status): aviso claro', (t) async {
      await _abrir(t, RetornoContaTela(servico: _api((_) => (status, {'detail': 'x'}))));
      expect(find.text('Ainda não disponível'), findsOneWidget);
      expect(_campo, findsNothing);
    });
  }

  testWidgets('campos ausentes usam texto padrão', (t) async {
    await _abrir(
      t,
      RetornoContaTela(
        servico: _api((_) => (
              200,
              {
                'itens': [<String, Object>{}]
              }
            )),
      ),
    );
    expect(find.text('Situação não informada'), findsOneWidget);
    expect(find.text('Protocolo: não informado', findRichText: true), findsOneWidget);
    expect(find.textContaining('Prazo mínimo aplicado'), findsNothing);
    expect(t.takeException(), isNull);
  });

  // O servidor de hoje recusa a conta encerrada nessas rotas (403 `conta_bloqueada`).
  testWidgets('403 conta_bloqueada mostra o texto do servidor e não derruba a tela', (t) async {
    var avisos = 0;
    final sessao = SessaoTrato()..entrar('t');
    sessao.aoBloquear = (_) => avisos++;
    await _abrir(
      t,
      RetornoContaTela(
        servico: _api(
          (_) => (403, {'detail': 'Sua conta está bloqueada.', 'codigo': 'conta_bloqueada'}),
          sessao: sessao,
        ),
      ),
    );
    expect(find.text('Sua conta está bloqueada.'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect((avisos, sessao.logada), (1, true));
  });

  for (final (tipo, aparece) in [('encerramento', true), ('suspensao', false)]) {
    testWidgets('tela de bloqueio com $tipo: entrada do retorno = $aparece', (t) async {
      final anterior = RotasTrato.repos;
      addTearDown(() {
        RotasTrato.repos = anterior;
        RotasTrato.esquecerBloqueio();
      });
      RotasTrato.repos = repositoriosDemo(
        medidas: _api((r) => r.url.path == '/v1/me/medidas'
            ? (
                200,
                [
                  {'id': 'm1', 'tipo': tipo, 'vigente': true}
                ]
              )
            : (200, _lista([]))),
      );
      final nav = GlobalKey<NavigatorState>();
      await _abrir(t, const Scaffold(), nav: nav);
      RotasTrato.contaFoiBloqueada(() => nav.currentState, null);
      await t.pumpAndSettle();
      expect(find.byType(ContaBloqueadaTela), findsOneWidget);
      final entrada = find.byKey(const Key('bloqueio-retorno'));
      expect(entrada, aparece ? findsOneWidget : findsNothing);
      if (aparece) {
        await _tocar(t, entrada);
        expect(find.byType(RetornoContaTela), findsOneWidget);
        expect(find.text('Você ainda não pediu o retorno.'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
}
