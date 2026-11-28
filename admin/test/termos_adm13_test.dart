import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/formato.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/regressos_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const ref = '0f8fad5b-d9cb-469f-a165-70867728950e';
const motivo = 'Dano que o Trato pagou ao cliente';

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

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'lider_suporte'}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'compensacoes');
  if (find.text('Pedidos de volta').evaluate().isNotEmpty) {
    await tester.tap(find.text('Pedidos de volta'));
    await tester.pumpAndSettle();
  }
  return fake;
}

Future<void> preencher(WidgetTester tester, {String valor = '200,50'}) async {
  await tester.tap(find.text('Propor pedido de volta'));
  await tester.pumpAndSettle();
  await escrever(tester, 'Código do pedido', 'ped-1');
  await escrever(tester, 'Código do fato que gerou', ref);
  await escrever(tester, 'Valor a pedir de volta', valor);
  await escrever(tester, 'Motivo (o profissional lê)', motivo);
  await clicar(tester, noModal('Revisar'));
}

void main() {
  test('permissões do regresso', () {
    Set<Papel> quem(Permissao p) => {for (final x in Papel.values) if (x.pode(p)) x};
    expect(quem(Permissao.regressoPropor),
        {Papel.mediador, Papel.liderSuporte, Papel.seguranca, Papel.administrador});
    expect(quem(Permissao.regressoAprovar), {Papel.liderSuporte, Papel.administrador});
  });

  testWidgets('propor: confirma antes e envia centavos', (tester) async {
    final api = await abrir(tester);
    await preencher(tester);
    expect(api.chamadasRegresso, isEmpty);
    await clicar(tester, noModal('Confirmar proposta'));
    expect(api.chamadasRegresso.single.$2,
        {'pedido': 'ped-1', 'referencia': ref, 'valor': 20050, 'motivo': motivo});
  });

  testWidgets('"200.50" é recusado junto do campo', (tester) async {
    final api = await abrir(tester);
    await preencher(tester, valor: '200.50');
    expect(find.text(kErroReais), findsOneWidget);
    expect(noModal('Confirmar proposta'), findsNothing);
    expect(api.chamadasRegresso, isEmpty);
  });

  testWidgets('ja_proposta avisa e erro do servidor fica no modal', (tester) async {
    final api = ApiFake()..resultadoRegresso = 'ja_proposta';
    await abrir(tester, api: api);
    await preencher(tester);
    await clicar(tester, noModal('Confirmar proposta'));
    expect(find.textContaining('Nada novo foi criado'), findsOneWidget);
    api.falhaRegresso = const ErroApi('Esta referência já virou compensação.', status: 409, codigo: 'ja_registrada');
    await preencher(tester);
    await clicar(tester, noModal('Confirmar proposta'));
    expect(find.textContaining('já virou compensação', findRichText: true), findsOneWidget);
  });

  testWidgets('aprovar pede confirmação; aviso que não saiu é dito', (tester) async {
    final api = ApiFake()..avisoDaCompensacao = false;
    await abrir(tester, api: api);
    await rolarListaAte(tester, find.text('Aprovar'));
    await clicar(tester, find.text('Aprovar'));
    expect(api.chamadasRegresso, isEmpty);
    await clicar(tester, noModal('Aprovar pedido de volta'));
    expect(api.chamadasRegresso.single.$1, 'aprovar');
    expect(find.textContaining('sem aviso, nada é descontado'), findsOneWidget);
  });

  for (final (erro, frase) in [
    (const ErroApi('Quem propôs não pode aprovar.', proibido: true, status: 403, codigo: 'mesma_pessoa'),
        'Quem propôs não pode aprovar.'),
    (const ErroApi('O valor passa do que pode ser compensado.', status: 422, codigo: 'acima_do_devido',
        maximoCentavos: 5000), 'O máximo é R\$ 50,00.'),
    (const ErroApi('Quem propôs não está mais apto: proponha de novo.', status: 409, codigo: 'proponente_invalido'),
        'proponha de novo'),
    (const ErroApi('Recusa do servidor (exemplo).', status: 409, codigo: 'estorno_ja_ordenado'),
        'Recusa do servidor (exemplo). $kRegressoPendenteNoFinanceiro'),
  ]) {
    testWidgets('aprovação recusada: ${erro.codigo}', (tester) async {
      await abrir(tester, api: ApiFake()..falhaRegresso = erro);
      await rolarListaAte(tester, find.text('Aprovar'));
      await clicar(tester, find.text('Aprovar'));
      await clicar(tester, noModal('Aprovar pedido de volta'));
      expect(find.textContaining(frase, findRichText: true), findsWidgets);
    });
  }

  testWidgets('recusar pede motivo', (tester) async {
    final api = await abrir(tester);
    await rolarListaAte(tester, find.text('Recusar'));
    await clicar(tester, find.text('Recusar'));
    expect(api.chamadasRegresso, isEmpty);
    await confirmarMotivo(tester, 'Recusar', motivo: 'Sem prova do dano alegado');
    expect(api.chamadasRegresso.single.$2, {'id': 'reg-1', 'motivo': 'Sem prova do dano alegado'});
  });

  testWidgets('quem propôs não vê Aprovar', (tester) async {
    await abrir(tester, api: ApiFake()..regressos = [ApiFake.regressoDeExemplo(por: 'eq-lider_suporte')]);
    await rolarListaAte(tester, find.text('Recusar'));
    expect(find.text('Aprovar'), findsNothing);
  });

  testWidgets('mediador propõe, mas não decide', (tester) async {
    await abrir(tester, papel: 'mediador');
    expect(find.text('Propor pedido de volta'), findsOneWidget);
    expect(find.text('Aprovar'), findsNothing);
    expect(find.text('Recusar'), findsNothing);
  });

  testWidgets('segurança só vê os pedidos de volta, sem a aba de descontos', (tester) async {
    await abrir(tester, papel: 'seguranca');
    expect(find.text('Propor pedido de volta'), findsOneWidget);
    expect(find.text('Descontos'), findsNothing);
    expect(find.text('Registrar compensação'), findsNothing);
  });

  testWidgets('vazio', (tester) async {
    await abrir(tester, api: ApiFake()..regressos = []);
    expect(find.text('Nenhum pedido de volta com esse filtro.'), findsOneWidget);
  });

  test('API: rotas, corpos, aprovação sem corpo e centavos', () async {
    final pedidos = <http.Request>[];
    const proposta = {
      'id': 'r1',
      'pedido_id': 'p1',
      'profissional_id': 'u1',
      'referencia': ref,
      'valor_centavos': 20050,
      'motivo': 'm',
      'status': 'proposta',
      'proposta_por': 'x',
      'proposta_em': '2026-11-25T10:00:00Z',
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"lider_suporte"}', 200);
        pedidos.add(r);
        return http.Response(
            jsonEncode(r.method == 'GET'
                ? {'itens': [proposta], 'total': 1}
                : {'resultado': 'ok', 'proposta': proposta, 'avisado': true}),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    const base = '/v1/admin/compensacoes/regressos';
    expect((await api.listarRegressos(status: 'proposta')).itens.single.valorCentavos, 20050);
    expect(pedidos.last.url.queryParameters, {'status': 'proposta', 'limite': '50', 'deslocamento': '0'});
    await api.proporRegresso(pedidoId: 'p1', referencia: ref, valorCentavos: 20050, motivo: motivo);
    expect(pedidos.last.url.path, base);
    expect(jsonDecode(pedidos.last.body),
        {'pedido_id': 'p1', 'referencia': ref, 'valor_centavos': 20050, 'motivo': motivo});
    expect((await api.aprovarRegresso('r1')).avisado, isTrue);
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST $base/r1/aprovacao');
    expect(pedidos.last.body, isEmpty);
    await api.recusarRegresso('r1', motivo: motivo);
    expect(pedidos.last.url.path, '$base/r1/recusa');
    expect(jsonDecode(pedidos.last.body), {'motivo': motivo});
  });
}
