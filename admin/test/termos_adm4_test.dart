import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/componentes/base.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/escopo.dart';
import 'package:trato_admin/telas/provas_modal.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const motivo = 'Análise do caso aberto';

CasoAusencia contestado() => CasoAusencia(
      pedidoId: 'aus-contest-9',
      pedidoNumero: 77,
      clienteNome: 'Ana (exemplo)',
      profissionalNome: 'Beto (exemplo)',
      valorServicoCentavos: 20000,
      status: CasoAusencia.recusada,
      chegadaEm: DateTime(2026, 11, 1),
      retencaoCentavos: 4500,
      cancelamentoStatus: CasoAusencia.propostaRetencao,
      contestarAte: DateTime(2026, 11, 9, 23, 59),
      contestacao: ContestacaoAusencia(
        status: ContestacaoAusencia.aberta,
        texto: 'Eu estava em casa (exemplo).',
        abertaEm: DateTime(2026, 11, 3),
        responderAte: DateTime(2026, 11, 17),
      ),
    );

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));

Future<void> escrever(WidgetTester tester, String rotulo, String texto, {bool modal = false}) async {
  final campo = find.widgetWithText(TextField, rotulo);
  await tester.enterText(modal ? find.descendant(of: find.byType(Dialog), matching: campo) : campo, texto);
  await tester.pumpAndSettle();
}

Future<ApiFake> abrirContestado(WidgetTester tester, {ApiFake? api}) async {
  final fake = api ?? ApiFake()
    ..ausencias = [contestado()];
  await abrirPainel(tester, papel: 'mediador', api: fake, secao: 'ausencias');
  return fake;
}

void main() {
  testWidgets('contestação aberta mostra dados e não oferece confirmar', (tester) async {
    await abrirContestado(tester);
    expect(find.text('PED-77'), findsWidgets);
    expect(find.text('Ana (exemplo)'), findsOneWidget);
    expect(find.text('R\$ 200,00'), findsOneWidget);
    expect(find.text('Cliente contesta até'), findsOneWidget);
    await rolarListaAte(tester, find.text('Revisar resposta'));
    expect(find.text('Confirmar com retenção'), findsNothing);
    expect(find.text('Cancelar sem retenção'), findsNothing);
  });

  testWidgets('reduzir retenção envia centavos só depois de confirmar', (tester) async {
    final api = await abrirContestado(tester);
    await tocar(tester, find.text('Reduzir retenção'));
    await rolarListaAte(tester, find.widgetWithText(TextField, 'Nova retenção'));
    await escrever(tester, 'Nova retenção', '20,50');
    await rolarListaAte(tester, find.widgetWithText(TextField, 'Resposta fundamentada (o cliente recebe)'));
    await escrever(tester, 'Resposta fundamentada (o cliente recebe)', 'Parte dos custos foi comprovada');
    await tocar(tester, find.text('Revisar resposta'));
    expect(api.ultimaRevisao, isNull);
    await tester.tap(noModal('Enviar resposta'));
    await tester.pumpAndSettle();
    expect(api.ultimaRevisao, {'resultado': 'alterada', 'resposta': 'Parte dos custos foi comprovada', 'retencao': 2050});
  });

  testWidgets('403 de quem decidiu a ausência fica na tela', (tester) async {
    final api = ApiFake()
      ..falhaAusencia = const ErroApi('Quem decidiu a ausência não responde a contestação (8.7).',
          proibido: true, status: 403);
    await abrirContestado(tester, api: api);
    await tocar(tester, find.text('Manter retenção'));
    await rolarListaAte(tester, find.widgetWithText(TextField, 'Resposta fundamentada (o cliente recebe)'));
    await escrever(tester, 'Resposta fundamentada (o cliente recebe)', 'Os custos foram comprovados');
    await tocar(tester, find.text('Revisar resposta'));
    await tester.tap(noModal('Enviar resposta'));
    await tester.pumpAndSettle();
    expect(find.textContaining('não responde a contestação', findRichText: true), findsWidgets);
  });

  testWidgets('provas: nada carrega sem motivo, abre o link e some quando vence', (tester) async {
    final abertas = <String>[];
    final original = abridorDeProva;
    abridorDeProva = (u) {
      abertas.add(u);
      return true;
    };
    addTearDown(() => abridorDeProva = original);
    final api = await abrirContestado(tester);
    await tocar(tester, find.text('Ver provas'));
    expect(api.chamadasAnexos, isEmpty);
    expect(find.textContaining('fica registrado na auditoria'), findsWidgets);
    await escrever(tester, 'Motivo do acesso', motivo);
    await tester.tap(noModal('Ver provas do caso'));
    await tester.pumpAndSettle();
    expect(api.chamadasAnexos, [('aus-contest-9', motivo)]);
    expect(find.text('Arquivo indisponível'), findsOneWidget);
    expect(find.text('Anexo da justificativa · foto · enviado pelo cliente'), findsOneWidget);
    await tester.tap(noModal('Abrir'));
    expect(abertas, ['https://exemplo.supabase.co/assinado']);
    await tester.pump(const Duration(seconds: 301));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsNothing);
    expect(find.textContaining('links venceram', findRichText: true), findsOneWidget);
  });

  Future<ApiFake> abrirAConversa(WidgetTester tester, {ApiFake? api, String papel = 'mediador'}) async {
    final fake = api ?? ApiFake();
    await abrirPainel(tester, papel: papel, api: fake, secao: 'disputas');
    await tocar(tester, find.text('Ver conversa'));
    return fake;
  }

  testWidgets('conversa: sem pré-carregar, e fechar apaga o texto', (tester) async {
    final api = await abrirAConversa(tester);
    expect(api.chamadasConversa, isEmpty);
    await escrever(tester, 'Motivo', motivo, modal: true);
    await tester.tap(noModal('Ler mensagens'));
    await tester.pumpAndSettle();
    expect(api.chamadasConversa.single.$3, 'disputa');
    expect(api.chamadasConversa.single.$4, isNull);
    expect(find.textContaining('31 99999-0000'), findsOneWidget);
    expect(find.textContaining('No app apareceu'), findsOneWidget);
    await tester.tap(noModal('Fechar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('31 99999-0000'), findsNothing);
    await tocar(tester, find.text('Ver conversa'));
    expect(find.textContaining('31 99999-0000'), findsNothing);
    expect(api.chamadasConversa.length, 1);
  });

  testWidgets('conversa: ordem judicial exige referência e 409 não mostra nada', (tester) async {
    final api = ApiFake()..falhaConversa = const ErroApi('Este pedido não tem o vínculo.', status: 409);
    await abrirAConversa(tester, api: api, papel: 'administrador'); // ordem judicial é só dele
    await tester.tap(find.text('Disputa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordem judicial').last);
    await tester.pumpAndSettle();
    await escrever(tester, 'Motivo', motivo, modal: true);
    await tester.tap(noModal('Ler mensagens'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.chamadasConversa, isEmpty);
    await escrever(tester, 'Número do processo', '0001234-56');
    await tester.tap(noModal('Ler mensagens'));
    await tester.pumpAndSettle();
    expect(find.textContaining('não tem o vínculo', findRichText: true), findsOneWidget);
    expect(find.textContaining('31 99999-0000'), findsNothing);
  });

  testWidgets('conversa some se a sessão cair', (tester) async {
    await abrirAConversa(tester);
    await escrever(tester, 'Motivo', motivo, modal: true);
    await tester.tap(noModal('Ler mensagens'));
    await tester.pumpAndSettle();
    tester.element(find.byType(CorpoModal)).sessao.saiu();
    await tester.pumpAndSettle();
    expect(find.textContaining('31 99999-0000'), findsNothing);
    expect(find.byType(CorpoModal), findsNothing);
  });

  testWidgets('sem conversas_ler não há botão', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2', secao: 'disputas');
    expect(find.text('Ver conversa'), findsNothing);
  });

  test('API: anexos, contestação e leitura de conversa', () async {
    final pedidos = <http.Request>[];
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        final Object corpo = r.url.path.endsWith('/anexos')
            ? [
                {'tipo': 'justificativa', 'arquivo_id': 'a', 'url': null, 'content_type': 'application/pdf'}
              ]
            : r.url.path.endsWith('/leitura')
                ? {
                    'conversas': [
                      {'conversa_id': 'c', 'profissional_id': 'p', 'mensagens': []}
                    ]
                  }
                : {
                    'pedido_id': 'p1',
                    'status': 'justificativa_recusada',
                    'chegada_em': '2026-11-25T10:00:00Z',
                    'contestar_ate': '2026-12-02T23:59:59-03:00',
                    'valor_servico_centavos': 20000,
                    'pedido_numero': 5,
                    'contestacao': {
                      'status': 'aberta',
                      'texto': 't',
                      'aberta_em': '2026-11-25T10:00:00Z',
                      'responder_ate': '2026-12-09T10:00:00Z',
                    },
                  };
        return http.Response(jsonEncode(corpo), 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final anexo = (await api.anexosAusencia('p1', motivo: motivo)).single;
    expect(anexo.url, isNull);
    expect(anexo.tipoConteudo, 'application/pdf');
    expect(pedidos.last.method, 'POST');
    expect(pedidos.last.url.toString(), 'http://api.teste/v1/admin/ausencias/p1/anexos'); // nada na URL
    expect(pedidos.last.url.hasQuery, isFalse);
    expect(jsonDecode(pedidos.last.body), {'motivo': motivo});
    final caso = await api.decidirContestacaoAusencia('p1', resultado: 'mantida', resposta: motivo);
    expect(jsonDecode(pedidos.last.body), {'resultado': 'mantida', 'resposta': motivo, 'retencao_centavos': null});
    expect(caso.contestacaoAberta, isTrue);
    expect(caso.pedido, 'PED-5');
    expect(caso.valorServicoCentavos, 20000);
    await api.lerConversas('p1', motivo: motivo, base: 'disputa');
    expect(pedidos.last.method, 'POST');
    expect(pedidos.last.url.path, '/v1/admin/pedidos/p1/conversas/leitura');
    expect(jsonDecode(pedidos.last.body), {'motivo': motivo, 'base': 'disputa', 'referencia': null});
  });
}
