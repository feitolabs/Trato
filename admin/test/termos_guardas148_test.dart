import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/guardas_pedido_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 14.8 e 16.3: guarda de retenção do pedido.
const motivo = 'Investigação interna em andamento.';

Finder modal() => find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet).last;
Finder noModal(String texto) => find.descendant(of: modal(), matching: find.text(texto));
Finder contem(String texto) => find.textContaining(texto, findRichText: true);

/// Segura a resposta para dar tempo de tocar de novo.
class _ApiLenta extends ApiFake {
  final liberar = Completer<void>();

  @override
  Future<({GuardaPedido guarda, bool repetida})> abrirGuardaPedido(String pedidoId,
      {required String tipo, required String motivo}) async {
    final r = super.abrirGuardaPedido(pedidoId, tipo: tipo, motivo: motivo);
    await liberar.future;
    return r;
  }
}

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _consultar(WidgetTester tester, ApiFake api, {String papel = 'dpo', double largura = 1400}) async {
  await abrirPainel(tester, papel: papel, api: api, largura: largura);
  if (largura < 600) {
    await tester.tap(find.byKey(const ValueKey('menu-mais')));
    await tester.pumpAndSettle();
    await tocarNoMais(tester, 'guardas');
  } else {
    await irPara(tester, 'guardas');
  }
  await tester.enterText(find.byKey(const ValueKey('guarda-pedido')), ' ped-1 ');
  await tester.pumpAndSettle();
  await clicar(tester, find.text('Consultar'));
}

Future<void> _escrever(WidgetTester tester, String texto) async {
  final campo = find.descendant(of: modal(), matching: find.byType(TextField));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Future<void> _revisarAbertura(WidgetTester tester) async {
  await clicar(tester, find.text('Abrir guarda'));
  await clicar(tester, noModal('Investigação'));
  await _escrever(tester, '  $motivo  ');
  await clicar(tester, noModal('Revisar'));
}

void main() {
  test('permissão: dpo, juridico, seguranca e administrador', () {
    expect({for (final x in Papel.values) if (x.pode(Permissao.pedidoGuardasGerenciar)) x},
        {Papel.dpo, Papel.juridico, Papel.seguranca, Papel.administrador});
  });

  testWidgets('quem não tem a permissão não vê a seção', (tester) async {
    await abrirPainel(tester, papel: 'lider_suporte');
    expect(find.byKey(const ValueKey('menu-guardas')), findsNothing);
    expect(find.text('Guarda de retenção'), findsNothing);
  });

  for (final (papel, largura) in [('juridico', 1400.0), ('seguranca', 360.0)]) {
    testWidgets('$papel consulta em ${largura.toInt()} px: rótulos em português', (tester) async {
      await _consultar(tester, ApiFake(), papel: papel, largura: largura);
      expect(contem('Bloqueado'), findsWidgets);
      expect(contem('Guarda aberta neste pedido; Disputa aberta'), findsOneWidget);
      expect(contem('Processo'), findsWidgets);
      expect(contem('guarda_pedido'), findsNothing);
      expect(find.textContaining(RegExp('^(Apagar|Excluir)')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('guarda encerrada não oferece encerrar; lista vazia tem aviso', (tester) async {
    final api = ApiFake()..guardasPedido = [ApiFake.guardaDeExemplo(aberta: false)];
    await _consultar(tester, api);
    expect(find.text('Encerrar guarda'), findsNothing);
    api.guardasPedido = [];
    await clicar(tester, find.text('Consultar'));
    expect(contem('Nenhuma guarda registrada'), findsOneWidget);
  });

  testWidgets('falha da retenção não esconde as guardas, e dá para tentar de novo', (tester) async {
    final api = ApiFake()..falhaRetencao = const ErroApi('Retenção indisponível.', status: 503);
    await _consultar(tester, api);
    expect(contem('Retenção indisponível.'), findsOneWidget);
    expect(find.text('Encerrar guarda'), findsOneWidget);
    api.falhaRetencao = null;
    await clicar(tester, find.text('Tentar novamente'));
    expect(contem('Retenção indisponível.'), findsNothing);
  });

  testWidgets('404 ao listar mostra o erro e não oferece abrir', (tester) async {
    await _consultar(tester, ApiFake()..falhaListaGuardas = const ErroApi('Pedido não encontrado.', status: 404));
    expect(contem('Pedido não encontrado.'), findsOneWidget);
    expect(find.text('Abrir guarda'), findsNothing);
  });

  testWidgets('abrir: exige tipo e motivo, confirma e envia sem espaços nas pontas', (tester) async {
    final api = ApiFake();
    await _consultar(tester, api);
    await clicar(tester, find.text('Abrir guarda'));
    await _escrever(tester, motivo);
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Confirmar abertura'), findsNothing); // sem tipo
    await clicar(tester, noModal('Investigação'));
    await _escrever(tester, '   curto      ');
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Confirmar abertura'), findsNothing);
    await _escrever(tester, '  $motivo  ');
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasGuarda, isEmpty);
    await clicar(tester, noModal('Confirmar abertura'));
    expect(api.chamadasGuarda.single.$2, {'pedido': 'ped-1', 'tipo': 'investigacao', 'motivo': motivo});
    expect(contem('Guarda aberta.'), findsOneWidget);
  });

  testWidgets('guarda igual já aberta: avisa que nada novo foi criado', (tester) async {
    await _consultar(tester, ApiFake()..guardaRepetida = true);
    await _revisarAbertura(tester);
    await clicar(tester, noModal('Confirmar abertura'));
    expect(contem('Nada novo foi criado'), findsOneWidget);
  });

  testWidgets('encerrar: confirma antes de enviar', (tester) async {
    final api = ApiFake();
    await _consultar(tester, api);
    await clicar(tester, find.text('Encerrar guarda'));
    await _escrever(tester, motivo);
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasGuarda, isEmpty);
    await clicar(tester, noModal('Confirmar encerramento'));
    expect(api.chamadasGuarda.single.$2, {'pedido': 'ped-1', 'guarda': 'g-1', 'motivo': motivo});
  });

  for (final status in [403, 404, 422, 503, null]) {
    testWidgets('erro ${status ?? 'sem resposta'} ao abrir preserva o motivo', (tester) async {
      await _consultar(tester, ApiFake()..falhaGuarda = ErroApi('Recusa de exemplo.', status: status));
      await _revisarAbertura(tester);
      await clicar(tester, noModal('Confirmar abertura'));
      expect(contem('Recusa de exemplo.'), findsOneWidget);
      expect(contem(kRepetirGuarda), status == null ? findsOneWidget : findsNothing);
      expect(contem(motivo), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('toque duplo envia uma vez só', (tester) async {
    final api = _ApiLenta();
    await _consultar(tester, api);
    await _revisarAbertura(tester);
    final alvo = noModal('Confirmar abertura');
    await tester.ensureVisible(alvo);
    await tester.pump();
    final onde = tester.getCenter(alvo);
    await tester.tapAt(onde);
    await tester.tapAt(onde);
    await tester.pump();
    await tester.tapAt(onde);
    expect(api.chamadasGuarda, hasLength(1));
    api.liberar.complete();
    await tester.pumpAndSettle();
    expect(api.chamadasGuarda, hasLength(1));
  });

  test('API: rotas, corpos, 200 repetida e erro', () async {
    final pedidos = <http.Request>[];
    var status = 201;
    final guarda = {
      'id': 'g1',
      'pedido_id': 'p1',
      'tipo': 'processo',
      'motivo': motivo,
      'aberta': true,
      'criada_por': 'u1',
      'criada_em': '2026-11-28T12:00:00Z',
      'encerrada_em': null,
      'encerrada_por': null,
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"dpo"}', 200);
        pedidos.add(r);
        final Object corpo = status == 503
            ? {'detail': 'Indisponivel.'}
            : r.url.path.endsWith('/retencao')
                ? {
                    'pedido_id': 'p1',
                    'situacao': 'sem_marco',
                    'concluido_em': null,
                    'prazo_anos': 5,
                    'guarda_ate': null,
                    'bloqueios': ['guarda_usuario'],
                  }
                : r.method == 'GET'
                    ? [guarda]
                    : guarda;
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    expect((await api.abrirGuardaPedido('p1', tipo: 'processo', motivo: motivo)).repetida, isFalse);
    expect(pedidos.last.url.path, '/v1/admin/pedidos/p1/guardas');
    expect(jsonDecode(pedidos.last.body), {'tipo': 'processo', 'motivo': motivo});
    status = 200;
    expect((await api.abrirGuardaPedido('p1', tipo: 'processo', motivo: motivo)).repetida, isTrue);
    expect((await api.listarGuardasPedido('p1')).single.encerradaEm, isNull);
    await api.encerrarGuardaPedido('p1', 'g1', motivo: motivo);
    expect((pedidos.last.method, pedidos.last.url.path), ('POST', '/v1/admin/pedidos/p1/guardas/g1/encerrar'));
    expect(jsonDecode(pedidos.last.body), {'motivo': motivo});
    final r = await api.obterRetencaoPedido('p1');
    expect(pedidos.last.url.path, '/v1/admin/pedidos/p1/retencao');
    expect((r.situacao, r.guardaAte, r.bloqueios.single), ('sem_marco', null, 'guarda_usuario'));
    status = 503;
    await expectLater(api.abrirGuardaPedido('p1', tipo: 'processo', motivo: motivo),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Indisponivel.')));
  });

  test('auditoria tem texto próprio para abrir e encerrar', () {
    String texto(String acao) => descreverAcao(EntradaAuditoria(
        id: 1,
        ocorridaEm: DateTime(2026, 11, 28),
        ator: 'u1',
        acao: acao,
        entidade: 'pedido_guardas:g1',
        motivo: motivo,
        detalhes: const {'pedido_id': 'p1', 'tipo': 'investigacao'}));
    expect(texto('retencao.guarda_pedido_aberta'), 'abriu uma guarda de retenção no pedido p1 (Investigação)');
    expect(texto('retencao.guarda_pedido_encerrada'), 'encerrou uma guarda de retenção no pedido p1 (Investigação)');
  });
}
