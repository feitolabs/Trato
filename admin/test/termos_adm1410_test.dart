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

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'dpo', double largura = 1400}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: largura < 700 ? null : 'lgpd', largura: largura);
  return fake;
}

void main() {
  test('permissões LGPD correspondem ao backend', () {
    Set<Papel> quem(Permissao p) => {for (final x in Papel.values) if (x.pode(p)) x};
    expect(quem(Permissao.lgpdPedidosGerenciar), {Papel.dpo, Papel.administrador});
    expect(quem(Permissao.lgpdRevisaoAutomatizada), {Papel.dpo, Papel.seguranca, Papel.administrador});
  });

  testWidgets('outros papéis não veem Pedidos LGPD no menu', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2');
    expect(find.byKey(const ValueKey('menu-lgpd')), findsNothing);
  });

  testWidgets('segurança vê foco em revisão automatizada e já filtra pelo tipo', (tester) async {
    final api = await abrir(
      tester,
      papel: 'seguranca',
      api: ApiFake()
        ..pedidosLgpd = [
          ApiFake.pedidoLgpdDeExemplo(
            id: 'lgpd-auto',
            tipo: 'revisao_decisao_automatizada',
            decisaoAutomatizada: 'alerta_fraude',
          ),
        ],
    );
    expect(api.ultimoTipoLgpd, 'revisao_decisao_automatizada');
    expect(find.byKey(const ValueKey('lgpd-tipo')), findsNothing);
    expect(find.textContaining('revisão de decisão automatizada', findRichText: true), findsWidgets);
  });

  testWidgets('DPO lista, destaca prazo vencido e envia filtros ao servidor', (tester) async {
    final api = await abrir(
      tester,
      papel: 'dpo',
      api: ApiFake()..pedidosLgpd = [ApiFake.pedidoLgpdDeExemplo(responderAte: DateTime(2020))],
    );
    expect(find.text('Prazo vencido'), findsWidgets);
    expect(find.textContaining('Prazo legal vencido.', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lgpd-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Em análise').last);
    await tester.pumpAndSettle();
    expect(api.ultimoStatusLgpd, 'em_analise');

    await tester.tap(find.byKey(const ValueKey('lgpd-tipo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portabilidade').last);
    await tester.pumpAndSettle();
    expect(api.ultimoTipoLgpd, 'portabilidade');

    await tester.enterText(find.byKey(const ValueKey('lgpd-usuario-filtro')), 'usr-99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.ultimoUsuarioLgpd, 'usr-99');
  });

  testWidgets('estado vazio e erro 503/403 na listagem', (tester) async {
    await abrir(tester, api: ApiFake()..pedidosLgpd = []);
    expect(find.text('Nenhum pedido LGPD com esse filtro.'), findsOneWidget);
  });

  testWidgets('erro 503 na listagem mostra detalhe do servidor', (tester) async {
    await abrir(
      tester,
      api: ApiFake()
        ..falhaListaLgpd = const ErroApi(
          'Pedidos de titular LGPD indisponíveis: a tabela ainda não existe no banco de dados.',
          status: 503,
        ),
    );
    expect(find.textContaining('Pedidos de titular LGPD indisponíveis', findRichText: true), findsWidgets);
  });

  testWidgets('iniciar análise pede confirmação e mostra erro 403 se recusado', (tester) async {
    final api = await abrir(tester);
    await rolarListaAte(tester, find.text('Iniciar análise'));
    await tester.tap(find.text('Iniciar análise'));
    await tester.pumpAndSettle();
    expect(api.chamadasLgpd, isEmpty);
    await clicar(tester, noModal('Iniciar análise'));
    expect(api.chamadasLgpd.single.$1, 'analisar');
    expect(api.chamadasLgpd.single.$2, {'id': 'lgpd-1'});

    api.falhaLgpd = const ErroApi('Apenas DPO ou administrador pode tratar pedidos de titular deste tipo.', status: 403);
    await rolarListaAte(tester, find.text('Iniciar análise'));
    await tester.tap(find.text('Iniciar análise'));
    await tester.pumpAndSettle();
    await clicar(tester, noModal('Iniciar análise'));
    expect(find.textContaining('Apenas DPO ou administrador', findRichText: true), findsOneWidget);
  });

  testWidgets('responder pedido: negado exige motivo_nao_atendido; revisão automatizada exige criterios_informados',
      (tester) async {
    final api = ApiFake()
      ..pedidosLgpd = [
        ApiFake.pedidoLgpdDeExemplo(
          id: 'lgpd-auto',
          tipo: 'revisao_decisao_automatizada',
          decisaoAutomatizada: 'alerta_fraude',
        ),
      ];
    await abrir(tester, papel: 'administrador', api: api);
    await rolarListaAte(tester, find.text('Responder pedido'));
    await tester.tap(find.text('Responder pedido'));
    await tester.pumpAndSettle();

    // Troca desfecho para Negado: exige motivo_nao_atendido além de criterios_informados
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Atendido')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Negado').last);
    await tester.pumpAndSettle();

    await escrever(tester, 'Resposta ao titular', 'A decisão foi revisada por analista humano e mantida.');
    // Sem motivo_nao_atendido e criterios_informados, Revisar fica desabilitado
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Confirmar resposta'), findsNothing);

    await escrever(tester, 'Motivo do não atendimento', 'Há inconsistência cadastral pendente de regularização.');
    await escrever(tester, 'Critérios informados', 'Verificação de documentos e histórico de risco da conta.');
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasLgpd, isEmpty);
    await clicar(tester, noModal('Confirmar resposta'));
    expect(api.chamadasLgpd.single.$1, 'responder');
    expect(api.chamadasLgpd.single.$2, {
      'id': 'lgpd-auto',
      'status': 'negado',
      'resposta': 'A decisão foi revisada por analista humano e mantida.',
      'motivo_nao_atendido': 'Há inconsistência cadastral pendente de regularização.',
      'criterios_informados': 'Verificação de documentos e histórico de risco da conta.',
    });
  });

  test('API: rotas, corpos e erros 403/409/422/503 de Pedidos LGPD', () async {
    final pedidos = <http.Request>[];
    (int, String)? recusa;
    const item = {
      'id': 'lgpd-1',
      'protocolo': 'LGPD-1',
      'usuario_id': 'usr-1',
      'contato': 'a@teste.local',
      'tipo': 'revisao_decisao_automatizada',
      'decisao_automatizada': 'alerta_fraude',
      'descricao': 'Revisar bloqueio',
      'canal': 'app',
      'aberto_em': '2026-11-20T10:00:00Z',
      'responder_ate': '2026-12-05T10:00:00Z',
      'status': 'aberto',
    };
    http.Response okJson(Object body, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status);
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return okJson({'access_token': 't'});
        if (r.url.path == '/v1/admin/eu') return okJson({'id': 'u1', 'papel': 'dpo'});
        pedidos.add(r);
        if (recusa != null) return okJson({'detail': recusa.$2}, recusa.$1);
        if (r.method == 'GET' && r.url.path == '/v1/admin/lgpd/pedidos') {
          return okJson({'itens': [item], 'total': 1});
        }
        return okJson(item);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');

    final lista = await api.listarPedidosLgpd(status: 'aberto', tipo: 'acesso', usuarioId: 'usr-1');
    expect(lista.itens.single.protocolo, 'LGPD-1');
    expect(pedidos.last.url.queryParameters,
        {'status': 'aberto', 'tipo': 'acesso', 'usuario_id': 'usr-1', 'limite': '50', 'deslocamento': '0'});

    await api.analisarPedidoLgpd('lgpd-1');
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/lgpd/pedidos/lgpd-1/analisar');

    await api.responderPedidoLgpd(
      'lgpd-1',
      status: 'atendido_parcial',
      resposta: 'Resposta registrada ao titular.',
      motivoNaoAtendido: 'Parte retida por obrigação legal.',
      criteriosInformados: 'Critérios objetivos de antifraude.',
    );
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/lgpd/pedidos/lgpd-1/responder');
    expect(jsonDecode(pedidos.last.body), {
      'status': 'atendido_parcial',
      'resposta': 'Resposta registrada ao titular.',
      'motivo_nao_atendido': 'Parte retida por obrigação legal.',
      'criterios_informados': 'Critérios objetivos de antifraude.',
    });

    for (final (status, texto) in [
      (403, 'Apenas DPO ou administrador pode tratar pedidos de titular deste tipo.'),
      (409, 'Este pedido de titular já foi respondido.'),
      (422, 'Informe criterios_informados na revisão de decisão automatizada.'),
      (503, 'Pedidos de titular LGPD indisponíveis: a tabela ainda não existe no banco de dados.'),
    ]) {
      recusa = (status, texto);
      await expectLater(
        api.analisarPedidoLgpd('lgpd-1'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', texto).having((e) => e.status, 'status', status)),
      );
    }
  });
}
