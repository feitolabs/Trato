import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/componentes/base.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/escopo.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/provas_modal.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder contem(Pattern texto) => find.textContaining(texto, findRichText: true);

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> escrever(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'mediador'}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'materiais', largura: 1400);
  return fake;
}

Future<void> abrirDecisao(WidgetTester tester, String decisao) async {
  await rolarListaAte(tester, find.text('Decidir contestação'));
  await clicar(tester, find.text('Decidir contestação'));
  await clicar(tester, find.byKey(const ValueKey('material-decisao')));
  await tester.tap(find.text(decisao).last);
  await tester.pumpAndSettle();
}

const resposta = 'Conferimos a nota e os comprovantes enviados.';

void main() {
  test('permissão 6.9 corresponde ao backend', () {
    expect({for (final x in Papel.values) if (x.pode(Permissao.materiaisContestacaoAnalisar)) x},
        {Papel.mediador, Papel.liderSuporte, Papel.seguranca, Papel.administrador});
  });

  testWidgets('iniciar análise só depois de confirmar', (tester) async {
    final api = await abrir(tester);
    await rolarListaAte(tester, find.text('Iniciar análise'));
    await clicar(tester, find.text('Iniciar análise'));
    expect(api.chamadasMaterial, isEmpty);
    await clicar(tester, noModal('Iniciar análise'));
    expect(api.chamadasMaterial.single.$1, 'analisar');
    expect(api.chamadasMaterial.single.$2, {'id': 'cm-1'});
  });

  for (final (rotulo, status) in [('Procedente', 'procedente'), ('Improcedente', 'improcedente')]) {
    testWidgets('decisão $status confirma e não envia valor', (tester) async {
      final api = await abrir(tester);
      await abrirDecisao(tester, rotulo);
      await escrever(tester, 'Resposta', resposta);
      await clicar(tester, noModal('Revisar'));
      expect(api.chamadasMaterial, isEmpty);
      await clicar(tester, noModal('Confirmar decisão'));
      expect(api.chamadasMaterial.single.$2, {'id': 'cm-1', 'status': status, 'resposta': resposta, 'valor': null});
    });
  }

  testWidgets('parcial lê reais em centavos e mostra a recusa do backend', (tester) async {
    const recusa = 'Valor reconhecido inválido: parcial = mais que zero e menos que o contestado.';
    final api = await abrir(tester, api: ApiFake()..falhaMaterial = const ErroApi(recusa, status: 422));
    await abrirDecisao(tester, 'Parcial');
    await escrever(tester, 'Resposta', resposta);
    await escrever(tester, r'Valor reconhecido (R$)', '50.00');
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Confirmar decisão'), findsNothing);
    // Acima do contestado: o painel envia e o backend é quem recusa.
    await escrever(tester, r'Valor reconhecido (R$)', '999,90');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar decisão'));
    expect(api.chamadasMaterial.single.$2['valor'], 99990);
    expect(contem(recusa), findsWidgets);
  });

  for (final efeito in ['nenhum', 'pendente_financeiro', 'executado']) {
    testWidgets('decidida com efeito $efeito: sem ações e sem afirmar que o dinheiro saiu', (tester) async {
      await abrir(
        tester,
        papel: 'administrador',
        api: ApiFake()
          ..contestacoesMaterial = [
            ApiFake.contestacaoMaterialDeExemplo(
                status: 'parcial', valorReconhecidoCentavos: 5000, efeitoFinanceiro: efeito),
          ],
      );
      await rolarListaAte(tester, contem('a decisão não pode ser mudada'));
      expect(find.text('Decidir contestação'), findsNothing);
      expect(find.text('Iniciar análise'), findsNothing);
      expect(contem(RegExp('aprovar', caseSensitive: false)), findsNothing);
      expect(contem(RegExp(r'devolvid|estornad|\bpago', caseSensitive: false)), findsNothing);
      expect(contem('Efeito financeiro pendente'), efeito == 'pendente_financeiro' ? findsWidgets : findsNothing);
    });
  }

  testWidgets('prazo vencido é destacado', (tester) async {
    await abrir(tester,
        api: ApiFake()..contestacoesMaterial = [ApiFake.contestacaoMaterialDeExemplo(responderAte: DateTime(2020))]);
    expect(find.text('Prazo vencido'), findsWidgets);
  });

  testWidgets('estado desconhecido não tem ações', (tester) async {
    await abrir(tester, api: ApiFake()..contestacoesMaterial = [ApiFake.contestacaoMaterialDeExemplo(status: 'nova')]);
    await rolarListaAte(tester, contem('nenhuma ação disponível'));
    expect(find.text('Decidir contestação'), findsNothing);
    expect(find.text('Iniciar análise'), findsNothing);
  });

  testWidgets('lista vazia', (tester) async {
    await abrir(tester, api: ApiFake()..contestacoesMaterial = []);
    expect(contem('Nenhuma contestação de materiais'), findsWidgets);
  });

  for (final status in [404, 503]) {
    testWidgets('erro $status na lista aparece sem quebrar', (tester) async {
      await abrir(tester, api: ApiFake()..falhaListaMaterial = ErroApi('Indisponível ($status).', status: status));
      expect(contem('Indisponível ($status).'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('conflito 409 ao analisar aparece no detalhe', (tester) async {
    await abrir(tester,
        api: ApiFake()..falhaMaterial = const ErroApi('Esta contestação já foi decidida.', status: 409));
    await rolarListaAte(tester, find.text('Iniciar análise'));
    await clicar(tester, find.text('Iniciar análise'));
    await clicar(tester, noModal('Iniciar análise'));
    expect(contem('já foi decidida'), findsWidgets);
  });

  Future<void> abrirModalDeAnexos(WidgetTester tester) async {
    await rolarListaAte(tester, find.text('Ver nota e provas'));
    await clicar(tester, find.text('Ver nota e provas'));
  }

  testWidgets('anexos: só pede após o motivo, abre, vence, renova e some com a sessão', (tester) async {
    final abertas = <String>[];
    final original = abridorDeProva;
    abridorDeProva = (u) {
      abertas.add(u);
      return true;
    };
    addTearDown(() => abridorDeProva = original);
    final api = await abrir(tester);
    await abrirModalDeAnexos(tester);
    expect(api.chamadasMaterial, isEmpty);
    await escrever(tester, 'Motivo do acesso', 'curto');
    await clicar(tester, noModal('Ver provas do caso'));
    expect(api.chamadasMaterial, isEmpty);

    // Acima de 500 (limite das outras rotas) e dentro dos 2000 desta.
    final motivo = 'Conferir a nota. ' * 40;
    await escrever(tester, 'Motivo do acesso', motivo);
    await clicar(tester, noModal('Ver provas do caso'));
    expect(api.chamadasMaterial.single.$2, {'id': 'cm-1', 'motivo': motivo.trim()});
    expect(noModal('Foto da nota de material · foto · enviado pelo profissional'), findsOneWidget);
    expect(noModal('Prova da contestação · enviado pelo cliente'), findsOneWidget);
    expect(noModal('Arquivo indisponível'), findsOneWidget);
    await clicar(tester, noModal('Abrir'));
    expect(abertas, ['https://exemplo.supabase.co/ver/nota-1']);

    await tester.pump(const Duration(seconds: 301));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsNothing);
    expect(contem('links venceram'), findsOneWidget);
    expect(api.chamadasMaterial, hasLength(1)); // nada é pedido sozinho
    await clicar(tester, noModal('Ver provas do caso'));
    expect(api.chamadasMaterial, hasLength(2));
    expect(noModal('Abrir'), findsOneWidget);

    tester.element(find.byType(CorpoModal)).sessao.saiu();
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsNothing);
  });

  testWidgets('anexos: motivo acima de 2000 não é enviado', (tester) async {
    final api = await abrir(tester);
    await abrirModalDeAnexos(tester);
    await escrever(tester, 'Motivo do acesso', 'a' * 2001);
    await clicar(tester, noModal('Ver provas do caso'));
    expect(api.chamadasMaterial, isEmpty);
  });

  for (final status in [403, 404, 422, 503]) {
    testWidgets('anexos: erro $status aparece no modal', (tester) async {
      await abrir(tester, api: ApiFake()..falhaAnexosMaterial = ErroApi('Recusa $status.', status: status));
      await abrirModalDeAnexos(tester);
      await escrever(tester, 'Motivo do acesso', 'Conferir a nota do pedido.');
      await clicar(tester, noModal('Ver provas do caso'));
      expect(contem('Recusa $status.'), findsWidgets);
      expect(find.text('Abrir'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('API: anexos vão por POST com o motivo no corpo e aceitam url nula', () async {
    final pedidos = <http.Request>[];
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u1","papel":"mediador"}', 200);
        pedidos.add(r);
        return http.Response(
            jsonEncode([
              {
                'tipo': 'nota_material',
                'arquivo_id': null,
                'enviado_por': 'profissional',
                'url': null,
                'content_type': null,
                'expira_em_segundos': null,
              },
            ]),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final a = (await api.abrirAnexosContestacaoMaterial('cm-1', motivo: 'Conferir a nota.')).single;
    expect(a.url, isNull);
    expect('${pedidos.single.method} ${pedidos.single.url}',
        'POST http://api.teste/v1/admin/materiais/contestacoes/cm-1/anexos');
    expect(jsonDecode(pedidos.single.body), {'motivo': 'Conferir a nota.'});
  });

  test('API: caminhos, filtros, corpo da decisão e erro detail', () async {
    final pedidos = <http.Request>[];
    (int, String)? recusa;
    const item = {
      'id': 'cm-1',
      'protocolo': 'MAT-1',
      'pedido_id': 'ped-1',
      'nota_id': 'nota-1',
      'item_id': null,
      'cliente_id': 'cli-1',
      'motivo': 'nao_comprovado',
      'descricao': 'Sem comprovante.',
      'anexos': ['a/1.jpg'],
      'valor_contestado_centavos': 15000,
      'aberta_em': '2026-11-20T10:00:00Z',
      'responder_ate': '2026-11-27T10:00:00Z',
      'status': 'aberta',
      'valor_reconhecido_centavos': null,
      'efeito_financeiro': 'nenhum',
    };
    http.Response json(Object body, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status);
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return json({'access_token': 't'});
        if (r.url.path == '/v1/admin/eu') return json({'id': 'u1', 'papel': 'mediador'});
        pedidos.add(r);
        if (recusa != null) return json({'detail': recusa.$2}, recusa.$1);
        if (r.method == 'GET') {
          return json({'itens': [item], 'total': 1});
        }
        return json(item);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');

    final lida = (await api.listarContestacoesMaterial(status: 'aberta', pedidoId: 'ped-1')).itens.single;
    expect(lida.valorReconhecidoCentavos, isNull);
    expect(pedidos.last.url.path, '/v1/admin/materiais/contestacoes');
    expect(pedidos.last.url.queryParameters,
        {'status': 'aberta', 'pedido_id': 'ped-1', 'limite': '50', 'deslocamento': '0'});

    await api.analisarContestacaoMaterial('cm-1');
    expect(pedidos.last.url.path, '/v1/admin/materiais/contestacoes/cm-1/analisar');

    await api.decidirContestacaoMaterial('cm-1', status: 'procedente', resposta: resposta);
    expect(pedidos.last.url.path, '/v1/admin/materiais/contestacoes/cm-1/decidir');
    expect(jsonDecode(pedidos.last.body), {'status': 'procedente', 'resposta': resposta});
    await api.decidirContestacaoMaterial('cm-1', status: 'parcial', resposta: resposta, valorReconhecidoCentavos: 5000);
    expect(jsonDecode(pedidos.last.body)['valor_reconhecido_centavos'], 5000);

    for (final status in [403, 404, 409, 422, 503]) {
      recusa = (status, 'Recusa $status.');
      await expectLater(
        api.decidirContestacaoMaterial('cm-1', status: 'improcedente', resposta: resposta),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Recusa $status.')),
      );
    }
  });
}
