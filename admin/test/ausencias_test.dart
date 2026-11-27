import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/ausencias_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> preencher(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.widgetWithText(TextField, rotulo);
  await rolarListaAte(tester, campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'mediador', double largura = 1400}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'ausencias', largura: largura);
  return fake;
}

/// Seleciona o caso pelo número curto, na lista da esquerda.
Future<void> selecionar(WidgetTester tester, String pedido) async {
  await tester.tap(find.text(pedido).first);
  await tester.pumpAndSettle();
}

void main() {
  test('fila ordena pelo prazo e deixa sem prazo no fim', () {
    CasoAusencia c(String id, DateTime? ate) =>
        CasoAusencia(pedidoId: id, status: 'em_analise', chegadaEm: DateTime(2026), justificativaAte: ate);
    final r = AusenciasTela.porPrazo([c('c', null), c('b', DateTime(2026, 3)), c('a', DateTime(2026, 2))]);
    expect([for (final x in r) x.pedidoId], ['a', 'b', 'c']);
  });

  testWidgets('aceitar pede motivo e confirmação antes de enviar, sem retenção', (tester) async {
    final api = await abrir(tester);
    await selecionar(tester, 'PED-AUSANALI');
    await tocar(tester, find.text('Aceitar'));
    await tocar(tester, find.text('Revisar decisão'));
    expect(find.text('Escreva ao menos 10 caracteres'), findsOneWidget);
    expect(api.ultimaDecisaoAusencia, isNull);
    await preencher(tester, 'Motivo', 'Comprovante confere com o horário');
    await tocar(tester, find.text('Revisar decisão'));
    expect(api.ultimaDecisaoAusencia, isNull); // só depois de confirmar
    await tester.tap(noModal('Aceitar justificativa'));
    await tester.pumpAndSettle();
    expect(api.ultimaDecisaoAusencia!['aceitar'], true);
    expect(api.ultimaDecisaoAusencia!['retencao'], 0);
    expect(api.ultimaDecisaoAusencia!['comprovantes'], isEmpty);
  });

  testWidgets('retenção vai em centavos, com justificativa e comprovantes; o painel não limita o valor',
      (tester) async {
    final api = await abrir(tester);
    await selecionar(tester, 'PED-AUSANALI');
    await tocar(tester, find.text('Recusar'));
    await preencher(tester, 'Motivo', 'Justificativa sem comprovação');
    await preencher(tester, 'Retenção por custos comprovados (opcional)', '99.999,50');
    await tocar(tester, find.text('Revisar decisão'));
    expect(find.byType(Dialog), findsNothing); // faltam justificativa e comprovante
    await preencher(tester, 'Justificativa da retenção (o cliente vê)', 'Deslocamento já realizado');
    await tocar(tester, find.text('Escolher comprovantes'));
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
        'Conferir os custos informados');
    await tester.pump();
    await tester.ensureVisible(noModal('Listar arquivos do pedido'));
    await tester.tap(noModal('Listar arquivos do pedido'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(noModal('Usar escolhidos'));
    await tester.tap(noModal('Usar escolhidos'));
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Revisar decisão'));
    expect(find.textContaining('R\$ 99.999,50'), findsOneWidget);
    await tester.tap(noModal('Mostrar retenção ao cliente'));
    await tester.pumpAndSettle();
    expect(api.ultimaDecisaoAusencia!['retencao'], 9999950);
    expect(api.ultimaDecisaoAusencia!['comprovantes'], ['comp-1']);
  });

  testWidgets('cancelar no modal não envia nada', (tester) async {
    final api = await abrir(tester);
    await selecionar(tester, 'PED-AUSPROPO');
    await tocar(tester, find.text('Confirmar com retenção'));
    await tester.tap(noModal('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.ultimaRetirada, isNull);
  });

  testWidgets('retenção proposta: confirmar sem retenção envia retirar_retencao', (tester) async {
    final api = await abrir(tester);
    await selecionar(tester, 'PED-AUSPROPO');
    expect(find.text('R\$ 45,00'), findsOneWidget);
    await tocar(tester, find.text('Cancelar sem retenção'));
    await confirmarMotivo(tester, 'Cancelar sem retenção', motivo: 'Cliente comprovou o imprevisto');
    expect(api.ultimaRetirada, true);
    expect(api.ultimoMotivoConfirmacao, 'Cliente comprovou o imprevisto');
  });

  for (final (status, titulo) in [
    (403, 'Sem permissão.'),
    (409, 'O caso mudou ou não pode ser decidido agora.'),
    (503, 'Recurso indisponível no servidor.'),
  ]) {
    testWidgets('recusa $status aparece fixa na tela com o texto do backend', (tester) async {
      final api = await abrir(tester);
      api.falhaAusencia = ErroApi('Texto do servidor $status', status: status);
      await selecionar(tester, 'PED-AUSPROPO');
      await tocar(tester, find.text('Confirmar com retenção'));
      await confirmarMotivo(tester, 'Confirmar com retenção');
      expect(find.textContaining(titulo, findRichText: true), findsOneWidget);
      expect(find.textContaining('Texto do servidor $status', findRichText: true), findsWidgets);
    });
  }

  const bloqueado = 'A conta do cliente está bloqueada: não há retenção por ausência (Termos 20.6).';

  testWidgets('409 na confirmação: texto junto dos botões e saída por retirar_retencao', (tester) async {
    final api = await abrir(tester);
    api.falhaAusencia = const ErroApi(bloqueado, status: 409);
    await selecionar(tester, 'PED-AUSPROPO');
    await tocar(tester, find.text('Confirmar com retenção'));
    await confirmarMotivo(tester, 'Confirmar com retenção');
    expect(find.textContaining('Para seguir sem retenção'), findsOneWidget);
    expect(find.textContaining(bloqueado, findRichText: true), findsWidgets);

    api.falhaAusencia = null;
    await tocar(tester, find.text('Cancelar sem retenção'));
    await confirmarMotivo(tester, 'Cancelar sem retenção', motivo: 'Conta do cliente bloqueada');
    expect(api.ultimaRetirada, true);
  });

  testWidgets('409 na decisão com retenção: "Decidir sem retenção" confirma e envia zero', (tester) async {
    final api = await abrir(tester);
    await selecionar(tester, 'PED-AUSANALI');
    await tocar(tester, find.text('Recusar'));
    await preencher(tester, 'Motivo', 'Justificativa sem comprovação');
    await preencher(tester, 'Retenção por custos comprovados (opcional)', '45,00');
    await preencher(tester, 'Justificativa da retenção (o cliente vê)', 'Deslocamento já realizado');
    await tocar(tester, find.text('Escolher comprovantes'));
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
        'Conferir os custos informados');
    await tester.pump();
    await tester.ensureVisible(noModal('Listar arquivos do pedido'));
    await tester.tap(noModal('Listar arquivos do pedido'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(noModal('Usar escolhidos'));
    await tester.tap(noModal('Usar escolhidos'));
    await tester.pumpAndSettle();

    api.falhaAusencia = const ErroApi(bloqueado, status: 409);
    await tocar(tester, find.text('Revisar decisão'));
    await tester.tap(noModal('Mostrar retenção ao cliente'));
    await tester.pumpAndSettle();
    expect(api.ultimaDecisaoAusencia, isNull);

    api.falhaAusencia = null;
    await tocar(tester, find.text('Decidir sem retenção'));
    expect(api.ultimaDecisaoAusencia, isNull); // ainda pede confirmação
    await tester.tap(noModal('Cancelar e reembolsar'));
    await tester.pumpAndSettle();
    expect(api.ultimaDecisaoAusencia!['aceitar'], false);
    expect(api.ultimaDecisaoAusencia!['retencao'], 0);
    expect(api.ultimaDecisaoAusencia!['comprovantes'], isEmpty);
  });

  testWidgets('aceitar avisa que, com cliente bloqueado, o pedido fica parado', (tester) async {
    await abrir(tester);
    await selecionar(tester, 'PED-AUSANALI');
    expect(find.textContaining('deixa o pedido parado', findRichText: true), findsNothing);
    await tocar(tester, find.text('Aceitar'));
    expect(find.textContaining('deixa o pedido parado', findRichText: true), findsOneWidget);
    await preencher(tester, 'Motivo', 'Comprovante confere com o horário');
    await tocar(tester, find.text('Revisar decisão'));
    expect(
      find.descendant(
          of: find.byType(Dialog), matching: find.textContaining('deixa o pedido parado', findRichText: true)),
      findsOneWidget,
    );
  });

  testWidgets('dentro do prazo do cliente não há botão de decisão', (tester) async {
    await abrir(tester);
    await selecionar(tester, 'PED-AUSESPER');
    expect(find.textContaining('ainda está no prazo'), findsOneWidget);
    expect(find.text('Revisar decisão'), findsNothing);
  });

  testWidgets('sem justificativa no prazo só dá para recusar', (tester) async {
    final api = ApiFake()
      ..ausencias = [
        CasoAusencia(
          pedidoId: 'aus-vencido',
          status: CasoAusencia.aguardandoJustificativa,
          chegadaEm: DateTime(2020),
          justificativaAte: DateTime(2020, 1, 2),
        ),
      ];
    await abrir(tester, api: api);
    expect(find.text('Recusar'), findsOneWidget);
    expect(find.text('Aceitar'), findsNothing);
  });

  testWidgets('quem só vê não recebe ações', (tester) async {
    await abrir(tester, papel: 'atendente_n2');
    await selecionar(tester, 'PED-AUSANALI');
    expect(find.textContaining('mas não decide'), findsOneWidget);
    expect(find.text('Revisar decisão'), findsNothing);
  });

  testWidgets('sem disputas_ver o item não aparece no menu', (tester) async {
    await abrirPainel(tester, papel: 'dpo');
    expect(find.byKey(const ValueKey('menu-ausencias')), findsNothing);
  });

  testWidgets('estado vazio', (tester) async {
    await abrir(tester, api: ApiFake()..ausencias = []);
    expect(find.text('Nenhum caso de cliente ausente.'), findsOneWidget);
  });

  testWidgets('estado de erro na fila', (tester) async {
    await abrir(tester, api: ApiFake(erro: true));
    expect(find.text('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('desistência mostra o aviso do Stripe e esconde nova visita', (tester) async {
    final api = ApiFake();
    for (final d in await api.disputasDeTeste) {
      api.marcarDesistencia(d.id);
    }
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas');
    expect(find.textContaining('Não devolva à mão no Stripe', findRichText: true), findsOneWidget);
    await rolarListaAte(tester, find.text('Reembolso parcial'));
    expect(find.text('Nova visita do profissional'), findsNothing);
  });

  testWidgets('cabe no celular (360 dp)', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'mediador', api: api, largura: 360, altura: 740);
    await tester.tap(find.byKey(const ValueKey('menu-mais')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente ausente').last);
    await tester.pumpAndSettle();
    await selecionar(tester, 'PED-AUSANALI');
    await tocar(tester, find.text('Recusar'));
    await preencher(tester, 'Retenção por custos comprovados (opcional)', '10,00');
    await rolarListaAte(tester, find.text('Revisar decisão'));
    expect(tester.takeException(), isNull);
  });

  group('API', () {
    final pedidos = <http.Request>[];
    var respostas = <String, (int, Object?)>{};

    Future<ApiAdminHttp> api() async {
      pedidos.clear();
      final cliente = MockClient((r) async {
        pedidos.add(r);
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        final (status, corpo) = respostas['${r.method} ${r.url.path}'] ?? (404, null);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status);
      });
      final a = ApiAdminHttp(
          urlApi: 'http://api.teste', urlSupabase: 'http://supa.teste', chaveAnonSupabase: 'anon', cliente: cliente);
      await a.entrar('a@teste.local', 'senha-de-teste');
      return a;
    }

    const caso = {'pedido_id': 'p1', 'status': 'em_analise', 'chegada_em': '2026-11-25T10:00:00Z'};

    test('rotas, corpo da decisão e da confirmação', () async {
      respostas = {
        'GET /v1/admin/ausencias': (200, [caso]),
        'POST /v1/admin/ausencias/p1/decisao': (200, caso),
        'POST /v1/admin/ausencias/p1/confirmar': (200, caso),
      };
      final a = await api();
      expect((await a.listarAusencias()).single.pedidoId, 'p1');
      await a.decidirAusencia('p1', aceitarJustificativa: true, justificativa: 'Motivo válido aqui');
      expect(jsonDecode(pedidos.last.body), {
        'aceitar_justificativa': true,
        'justificativa': 'Motivo válido aqui',
        'retencao_centavos': 0,
        'retencao_justificativa': null,
        'retencao_comprovantes': <String>[],
      });
      await a.confirmarAusencia('p1', retirarRetencao: true, motivo: 'Motivo da confirmação');
      expect(jsonDecode(pedidos.last.body), {'motivo': 'Motivo da confirmação', 'retirar_retencao': true});
    });

    test('409 traz o texto do backend e o código', () async {
      respostas = {'POST /v1/admin/ausencias/p1/confirmar': (409, {'detail': 'Não há retenção esperando.'})};
      final a = await api();
      await expectLater(
        a.confirmarAusencia('p1', retirarRetencao: false, motivo: 'Motivo da confirmação'),
        throwsA(isA<ErroApi>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.mensagem, 'mensagem', 'Não há retenção esperando.')),
      );
    });

    test('desistência vem do campo do backend', () async {
      Map<String, Object?> disputa(bool v) => {
            'pedido_id': 'p1',
            'pedido_numero': 1,
            'motivo': 'diferente_do_combinado',
            'valor_congelado_centavos': 100,
            'decisao_ate': '2026-12-01T10:00:00Z',
            'estado': 'em_analise',
            'desistencia': v,
          };
      final a = await api();
      respostas = {'GET /v1/admin/disputas/p1': (200, disputa(true))};
      expect((await a.obterDisputa('p1')).desistencia, isTrue);
      respostas = {'GET /v1/admin/disputas/p1': (200, disputa(false))};
      expect((await a.obterDisputa('p1')).desistencia, isFalse);
    });
  });
}
