// APP-CONTESTA-OCULTA: Termos 11.8, o autor pede revisão da avaliação ocultada.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/avaliacao_ocultada/revisao_ocultacao.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';

import 'apoio/fontes.dart';

Map<String, Object?> _pedido(String status, {String? resposta}) => {
      'avaliacao_id': 'av1',
      'tipo': 'contestacao_ocultacao',
      'protocolo': 'REV-1',
      'status': status,
      'responder_ate': '2026-12-04T15:00:00Z',
      'resposta': resposta,
    };

class _Servidor {
  (int, Object) lista = (200, {'itens': <Object>[]});
  (int, Object) envio = (201, _pedido('aberta'));
  Completer<void>? trava;
  final corpos = <Object?>[];

  late final servico = ServicoRevisaoOcultacaoApi(ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato(),
    cliente: MockClient((r) async {
      if (r.method == 'POST') {
        expect(r.url.path, '/v1/avaliacoes/av1/revisoes');
        corpos.add(jsonDecode(r.body));
        await trava?.future;
      }
      final (status, corpo) = r.method == 'POST' ? envio : lista;
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  ));
}

Future<void> _abrir(WidgetTester t, _Servidor s) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: RevisaoOcultacaoTela(servico: s.servico, avaliacaoId: 'av1'),
  ));
  await t.pumpAndSettle();
}

Future<void> _tocarEnviar(WidgetTester t) async {
  final botao = find.text('Pedir revisão');
  await t.scrollUntilVisible(botao, 150, scrollable: find.byType(Scrollable).first);
  await t.ensureVisible(botao);
  await t.pumpAndSettle();
  await t.tap(botao);
}

final _campo = find.byKey(const ValueKey('justificativa-revisao'));

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('valida o texto, mostra "enviando" e o protocolo do servidor', (t) async {
    final s = _Servidor()..trava = Completer<void>();
    await _abrir(t, s);
    await t.enterText(_campo, 'curto');
    await _tocarEnviar(t);
    await t.pumpAndSettle();
    expect(find.textContaining('pelo menos 10'), findsOneWidget);
    expect(s.corpos, isEmpty);
    await t.scrollUntilVisible(_campo, -150, scrollable: find.byType(Scrollable).first);
    await t.enterText(_campo, '  O comentário era sobre o serviço.  ');
    await _tocarEnviar(t);
    await t.pump();
    expect(find.text('Enviando...'), findsOneWidget);
    s.trava!.complete();
    await t.pumpAndSettle();
    expect(s.corpos, [
      {'tipo': 'contestacao_ocultacao', 'justificativa': 'O comentário era sobre o serviço.'}
    ]);
    expect(find.text('Pedido recebido'), findsOneWidget);
    expect(find.text('Protocolo REV-1'), findsOneWidget);
    expect(find.text('Resposta prevista até 04/12/2026.'), findsOneWidget);
    expect(_campo, findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('já pedido: mostra a situação e não oferece enviar', (t) async {
    final s = _Servidor()..lista = (200, {'itens': [_pedido('em_analise')]});
    await _abrir(t, s);
    expect(find.text('Em análise'), findsOneWidget);
    expect(_campo, findsNothing);
    expect(find.text('Pedir revisão'), findsNothing);
  });

  testWidgets('decidido: mostra a resposta e deixa o servidor decidir um novo pedido', (t) async {
    final s = _Servidor()
      ..lista = (200, {'itens': [_pedido('recusada', resposta: 'Resposta de exemplo.')]});
    await _abrir(t, s);
    expect(find.text('Pedido recusado'), findsOneWidget);
    expect(find.text('Resposta de exemplo.'), findsOneWidget);
    expect(find.textContaining('Resposta prevista'), findsNothing);
    await t.scrollUntilVisible(find.text('Pedir revisão'), 150,
        scrollable: find.byType(Scrollable).first);
  });

  testWidgets('recusa do servidor aparece junto do botão e o texto fica', (t) async {
    final s = _Servidor()
      ..envio = (409, {'detail': 'Esta avaliação não tem ocultação ativa para contestar.'});
    await _abrir(t, s);
    await t.enterText(_campo, 'Texto de exemplo longo.');
    await _tocarEnviar(t);
    await t.pumpAndSettle();
    expect(find.textContaining('não tem ocultação ativa'), findsOneWidget);
    expect(find.text('Texto de exemplo longo.', skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final status in [404, 503]) {
    testWidgets('consulta $status: indisponível, sem formulário', (t) async {
      await _abrir(t, _Servidor()..lista = (status, {'detail': 'x'}));
      expect(find.textContaining('indisponível'), findsOneWidget);
      expect(_campo, findsNothing);
    });
  }

  testWidgets('erro na consulta: tenta de novo', (t) async {
    final s = _Servidor()..lista = (500, {'detail': 'x'});
    await _abrir(t, s);
    expect(find.textContaining('Tentar'), findsOneWidget);
    s.lista = (200, {'itens': <Object>[]});
    await t.tap(find.textContaining('Tentar'));
    await t.pumpAndSettle();
    expect(_campo, findsOneWidget);
  });

  test('o aviso com avaliacao_id abre a revisão (push e caixa); sem ele, o pedido', () {
    const esperado =
        ResultadoLink.valido(DestinoApp.contestarOcultacao, 'av1', papel: 'cliente');
    expect(
        resultadoDoPush({
          'evento': 'conta.avaliacao_ocultada',
          'tela': 'pedido',
          'pedido_id': 'p1',
          'avaliacao_id': 'av1',
          'papel': 'cliente',
        }),
        esperado);
    Notificacao aviso(String? avaliacao) => Notificacao(
          id: 'n1',
          tipo: TipoNotificacao.sistema,
          titulo: 't',
          texto: 'x',
          quando: 'agora',
          tela: 'pedido',
          papel: 'cliente',
          destinoId: 'p1',
          tipoApi: 'conta.avaliacao_ocultada',
          avaliacaoId: avaliacao,
        );
    expect(RotasTrato.destinoDaCaixa(aviso('av1'), modoAtualProfissional: false), esperado);
    expect(aviso('av1').comoLida().avaliacaoId, 'av1');
    for (final ruim in [null, 'a/b']) {
      expect(RotasTrato.destinoDaCaixa(aviso(ruim), modoAtualProfissional: false),
          const ResultadoLink.valido(DestinoApp.pedido, 'p1', papel: 'cliente'));
    }
  });
}
