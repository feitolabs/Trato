import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder campo(String rotulo) =>
    find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> escrever(WidgetTester tester, String rotulo, String texto) async {
  await tester.ensureVisible(campo(rotulo));
  await tester.enterText(campo(rotulo), texto);
  await tester.pumpAndSettle();
}

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'mediador', double largura = 1400}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: largura < 700 ? null : 'avaliacoes', largura: largura);
  return fake;
}

void main() {
  test('permissão avaliacoes_moderar corresponde ao backend', () {
    final quem = {for (final p in Papel.values) if (p.pode(Permissao.avaliacoesModerar)) p};
    expect(quem, {Papel.mediador, Papel.liderSuporte, Papel.seguranca, Papel.administrador});
  });

  testWidgets('sem permissão a seção não aparece no menu', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2');
    expect(find.byKey(const ValueKey('menu-avaliacoes')), findsNothing);
  });

  testWidgets('listagem, filtros de situação e código da avaliação vão ao servidor', (tester) async {
    final api = await abrir(tester);
    expect(find.text('REV-2026-0001'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('avaliacao-situacao')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Em análise').last);
    await tester.pumpAndSettle();
    expect(api.ultimoStatusRevisaoAvaliacao, 'em_analise');

    await tester.enterText(find.byKey(const ValueKey('avaliacao-id-filtro')), 'aval-99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.ultimoAvaliacaoIdFiltro, 'aval-99');
  });

  testWidgets('estado vazio na listagem', (tester) async {
    await abrir(tester, api: ApiFake()..revisoesAvaliacao = []);
    expect(find.text('Nenhum pedido de revisão com esse filtro.'), findsOneWidget);
  });

  testWidgets('erro 503 na listagem mostra detalhe do backend', (tester) async {
    await abrir(
      tester,
      api: ApiFake()
        ..falhaListaAvaliacao = const ErroApi(
          'Moderação de avaliações indisponível: as tabelas ainda não existem no banco de dados.',
          status: 503,
        ),
    );
    expect(find.textContaining('Moderação de avaliações indisponível', findRichText: true), findsWidgets);
  });

  testWidgets('iniciar análise pede confirmação e chama a API', (tester) async {
    final api = await abrir(tester);
    await rolarListaAte(tester, find.text('Iniciar análise'));
    await tester.tap(find.text('Iniciar análise'));
    await tester.pumpAndSettle();
    expect(api.chamadasAvaliacao, isEmpty);
    await clicar(tester, noModal('Iniciar análise'));
    expect(api.chamadasAvaliacao.single.$1, 'analisar');
    expect(api.chamadasAvaliacao.single.$2, {'id': 'rev-1'});
  });

  testWidgets('decidir revisão: aceita exige ocultar_motivo; recusada não envia ocultar_motivo', (tester) async {
    final api = await abrir(tester);
    await rolarListaAte(tester, find.text('Decidir revisão'));
    await tester.tap(find.text('Decidir revisão'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Motivo da ocultação')), findsOneWidget);
    await escrever(tester, 'Resposta', 'Confirmada ofensa contra o profissional.');
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasAvaliacao, isEmpty);
    await clicar(tester, noModal('Confirmar decisão'));
    expect(api.chamadasAvaliacao.single.$1, 'decidir');
    expect(api.chamadasAvaliacao.single.$2, {
      'id': 'rev-1',
      'status': 'aceita',
      'resposta': 'Confirmada ofensa contra o profissional.',
      'ocultar_motivo': 'ofensa_ou_ilegal',
      'mesmo_analista_justificativa': null,
    });

    // Recusada não envia ocultar_motivo
    api.chamadasAvaliacao.clear();
    await rolarListaAte(tester, find.text('Decidir revisão'));
    await tester.tap(find.text('Decidir revisão'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Aceitar pedido')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recusar pedido').last);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Motivo da ocultação')), findsNothing);
    await escrever(tester, 'Resposta', 'O comentário relata apenas o atraso no serviço.');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar decisão'));
    expect(api.chamadasAvaliacao.single.$1, 'decidir');
    expect(api.chamadasAvaliacao.single.$2, {
      'id': 'rev-1',
      'status': 'recusada',
      'resposta': 'O comentário relata apenas o atraso no serviço.',
      'ocultar_motivo': null,
      'mesmo_analista_justificativa': null,
    });
  });

  testWidgets('decidir contestação de ocultação aceita permite mesmo_analista_justificativa', (tester) async {
    final api = ApiFake()
      ..revisoesAvaliacao = [
        ApiFake.revisaoAvaliacaoDeExemplo(
          id: 'rev-2',
          tipo: 'contestacao_ocultacao',
          ocultacaoId: 'ocu-9',
          status: 'em_analise',
        ),
      ];
    await abrir(tester, api: api);
    await rolarListaAte(tester, find.text('Decidir revisão'));
    await tester.tap(find.text('Decidir revisão'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Motivo da ocultação')), findsNothing);
    await escrever(tester, 'Resposta', 'Contestação procedente após revisão das provas.');
    await escrever(
      tester,
      'Justificativa do mesmo analista (opcional)',
      'Único analista disponível no plantão atual.',
    );
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar decisão'));
    expect(api.chamadasAvaliacao.single.$1, 'decidir');
    expect(api.chamadasAvaliacao.single.$2, {
      'id': 'rev-2',
      'status': 'aceita',
      'resposta': 'Contestação procedente após revisão das provas.',
      'ocultar_motivo': null,
      'mesmo_analista_justificativa': 'Único analista disponível no plantão atual.',
    });
  });

  testWidgets('ocultar avaliação e reverter ocultação por ID com confirmação e erro 409', (tester) async {
    final api = await abrir(tester);
    await tester.tap(find.text('Ocultar avaliação'));
    await tester.pumpAndSettle();
    await escrever(tester, 'Código da avaliação', 'aval-42');
    await escrever(tester, 'Explicação', 'Expôs telefone pessoal do cliente no texto.');
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasAvaliacao, isEmpty);
    await clicar(tester, noModal('Confirmar ocultação'));
    expect(api.chamadasAvaliacao.single.$1, 'ocultar');
    expect(api.chamadasAvaliacao.single.$2, {
      'avaliacao_id': 'aval-42',
      'motivo': 'ofensa_ou_ilegal',
      'explicacao': 'Expôs telefone pessoal do cliente no texto.',
    });

    api.chamadasAvaliacao.clear();
    await tester.tap(find.text('Reverter ocultação'));
    await tester.pumpAndSettle();
    await escrever(tester, 'Código da avaliação', 'aval-42');
    await escrever(tester, 'Motivo', 'Ocultação aplicada por engano na conferência.');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar reversão'));
    expect(api.chamadasAvaliacao.single.$1, 'reverter');
    expect(api.chamadasAvaliacao.single.$2, {
      'avaliacao_id': 'aval-42',
      'motivo': 'Ocultação aplicada por engano na conferência.',
    });

    // Erro 409 fica no modal
    api.falhaAvaliacao = const ErroApi('Esta avaliação já possui uma ocultação ativa.', status: 409);
    await tester.tap(find.text('Ocultar avaliação'));
    await tester.pumpAndSettle();
    await escrever(tester, 'Código da avaliação', 'aval-42');
    await escrever(tester, 'Explicação', 'Tentativa repetida de ocultação.');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar ocultação'));
    expect(find.textContaining('já possui uma ocultação ativa', findRichText: true), findsOneWidget);
  });

  test('API: rotas, corpos e erros 409/503 de avaliações', () async {
    final pedidos = <http.Request>[];
    (int, String)? recusa;
    const revJson = {
      'id': 'rev-1',
      'protocolo': 'REV-1',
      'avaliacao_id': 'aval-1',
      'tipo': 'revisao',
      'ocultacao_id': null,
      'solicitante_id': 'usr-1',
      'justificativa': 'Ofensa grave',
      'anexos': ['a.png'],
      'canal': 'app',
      'aberta_em': '2026-11-20T10:00:00Z',
      'responder_ate': '2026-11-25T10:00:00Z',
      'status': 'aberta',
    };
    const ocuJson = {
      'id': 'ocu-1',
      'avaliacao_id': 'aval-1',
      'motivo': 'ofensa_ou_ilegal',
      'explicacao': 'Ofensa no texto da avaliação.',
      'analista_id': 'u1',
      'ocultada_em': '2026-11-21T10:00:00Z',
      'status_anterior': 'publicada',
    };
    http.Response okJson(Object body, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status);
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return okJson({'access_token': 't'});
        if (r.url.path == '/v1/admin/eu') return okJson({'id': 'u1', 'papel': 'mediador'});
        pedidos.add(r);
        if (recusa != null) return okJson({'detail': recusa.$2}, recusa.$1);
        if (r.method == 'GET' && r.url.path == '/v1/admin/avaliacoes/revisoes') {
          return okJson({'itens': [revJson], 'total': 1});
        }
        if (r.url.path.endsWith('/ocultar') || r.url.path.endsWith('/reverter-ocultacao')) {
          return okJson(ocuJson, r.url.path.endsWith('/ocultar') ? 201 : 200);
        }
        return okJson(revJson);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');

    final lista = await api.listarRevisoesAvaliacao(status: 'aberta', avaliacaoId: 'aval-1');
    expect(lista.itens.single.protocolo, 'REV-1');
    expect(pedidos.last.url.queryParameters,
        {'status': 'aberta', 'avaliacao_id': 'aval-1', 'limite': '50', 'deslocamento': '0'});

    await api.analisarRevisaoAvaliacao('rev-1');
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/avaliacoes/revisoes/rev-1/analisar');

    await api.decidirRevisaoAvaliacao(
      'rev-1',
      status: 'aceita',
      resposta: 'Confirmado motivo.',
      ocultarMotivo: 'ofensa_ou_ilegal',
    );
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/avaliacoes/revisoes/rev-1/decidir');
    expect(jsonDecode(pedidos.last.body), {
      'status': 'aceita',
      'resposta': 'Confirmado motivo.',
      'ocultar_motivo': 'ofensa_ou_ilegal',
    });

    await api.ocultarAvaliacao('aval-1', motivo: 'dados_pessoais', explicacao: 'CPF exposto no texto.');
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/avaliacoes/aval-1/ocultar');
    expect(jsonDecode(pedidos.last.body), {'motivo': 'dados_pessoais', 'explicacao': 'CPF exposto no texto.'});

    await api.reverterOcultacaoAvaliacao('aval-1', motivo: 'Reversão após contestação.');
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/avaliacoes/aval-1/reverter-ocultacao');
    expect(jsonDecode(pedidos.last.body), {'motivo': 'Reversão após contestação.'});

    for (final (status, texto) in [
      (409, 'Este pedido de revisão já foi decidido.'),
      (503, 'Moderação de avaliações indisponível: as tabelas ainda não existem no banco de dados.'),
    ]) {
      recusa = (status, texto);
      await expectLater(
        api.analisarRevisaoAvaliacao('rev-1'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', texto).having((e) => e.status, 'status', status)),
      );
    }
  });
}
