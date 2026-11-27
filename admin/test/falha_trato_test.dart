import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const codigo = '0f8fad5b-d9cb-469f-a165-70867728950e';
const botao = 'Registrar falha do Trato';

Future<ApiFake> abrirModal(WidgetTester tester, {ApiFake? api, double largura = 1400}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: 'mediador', api: fake, secao: 'disputas', largura: largura);
  await tester.tap(find.text(botao));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> noModalVisivel(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
}

Future<void> preencherERevisar(WidgetTester tester) async {
  final item = find.byKey(const ValueKey('exclusividade-$codigo'));
  await noModalVisivel(tester, item);
  await tester.tap(item);
  await tester.pump();
  final campo = find.widgetWithText(TextField, 'Motivo');
  await noModalVisivel(tester, campo);
  await tester.enterText(campo, 'Instabilidade do Trato no período');
  await tester.pump();
  await noModalVisivel(tester, find.text('Revisar'));
  await tester.tap(find.text('Revisar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('só envia depois da confirmação e mostra o que voltou', (tester) async {
    final api = await abrirModal(tester);
    await preencherERevisar(tester);
    expect(api.chamadasFalhaTrato, isEmpty);
    await noModalVisivel(tester, find.text('Confirmar devolução'));
    await tester.tap(find.text('Confirmar devolução'));
    await tester.pumpAndSettle();
    expect(api.chamadasFalhaTrato, [(codigo, 'Instabilidade do Trato no período')]);
    expect(find.textContaining('150 Tratinhos de volta'), findsOneWidget);
    expect(find.text('Confirmar devolução'), findsNothing);
  });

  testWidgets('sem escolher na lista não dá para revisar', (tester) async {
    final api = await abrirModal(tester);
    final campo = find.widgetWithText(TextField, 'Motivo');
    await noModalVisivel(tester, campo);
    await tester.enterText(campo, 'Instabilidade do Trato no período');
    await tester.pump();
    await noModalVisivel(tester, find.text('Revisar'));
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar devolução'), findsNothing);
    expect(api.chamadasFalhaTrato, isEmpty);
  });

  testWidgets('confirmação mostra o caso escolhido; voltar mantém escolha e filtro', (tester) async {
    final api = await abrirModal(tester);
    final filtro = find.widgetWithText(TextField, 'Filtrar por código do pedido');
    await tester.enterText(filtro, 'ped-exemplo-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.ultimoFiltroExclusividades!.pedidoId, 'ped-exemplo-1');
    await preencherERevisar(tester);
    expect(find.text('Ana (exemplo)'), findsOneWidget);
    expect(find.text('150 Tratinhos'), findsOneWidget);
    await noModalVisivel(tester, find.text('Voltar'));
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('ped-exemplo-1'), findsOneWidget);
    expect(find.text('Revisar'), findsOneWidget);
  });

  testWidgets('lista indisponível mostra o texto do servidor', (tester) async {
    await abrirModal(tester, api: ApiFake()..exclusividades = []);
    expect(find.text('Nenhuma exclusividade com esse filtro.'), findsOneWidget);
  });

  testWidgets('duplo clique envia uma vez só', (tester) async {
    final api = ApiFake(atraso: const Duration(milliseconds: 300));
    await abrirModal(tester, api: api);
    await preencherERevisar(tester);
    await noModalVisivel(tester, find.text('Confirmar devolução'));
    await tester.tap(find.text('Confirmar devolução'));
    await tester.tap(find.text('Confirmar devolução'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Registrando'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.chamadasFalhaTrato.length, 1);
  });

  testWidgets('ja_devolvida avisa que nada novo voltou', (tester) async {
    final api = ApiFake()..falhaTratoResultado = 'ja_devolvida';
    await abrirModal(tester, api: api);
    await preencherERevisar(tester);
    await noModalVisivel(tester, find.text('Confirmar devolução'));
    await tester.tap(find.text('Confirmar devolução'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nada novo foi devolvido'), findsOneWidget);
  });

  for (final (erro, frase) in [
    (const ErroApi('x', status: 404, codigo: 'nao_encontrada'), 'não achou esta exclusividade'),
    (const ErroApi('x', status: 409, codigo: 'nao_elegivel'), 'já foi concluída'),
    (const ErroApi('x', proibido: true, status: 403, codigo: 'analista_invalido'), 'não está habilitada'),
    (const ErroApi('Not Found', status: 404), 'backend novo já está publicado'),
    (const ErroApi('Texto do servidor sobre a tabela.', status: 503, codigo: 'indisponivel'),
        'Texto do servidor sobre a tabela.'),
  ]) {
    testWidgets('erro ${erro.status} "${erro.mensagem}" fica no modal com o texto digitado', (tester) async {
      final api = ApiFake()..falhaTratoErro = erro;
      await abrirModal(tester, api: api);
      await preencherERevisar(tester);
      await noModalVisivel(tester, find.text('Confirmar devolução'));
    await tester.tap(find.text('Confirmar devolução'));
      await tester.pumpAndSettle();
      expect(find.textContaining(frase, findRichText: true), findsOneWidget);
      expect(find.text('Instabilidade do Trato no período'), findsOneWidget);
    });
  }

  testWidgets('quem só vê disputas não tem o botão', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2', secao: 'disputas');
    expect(find.text(botao), findsNothing);
  });

  testWidgets('sem nenhuma disputa a ação continua disponível', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(vazio: true), secao: 'disputas');
    expect(find.text('Nenhuma disputa aberta.'), findsOneWidget);
    expect(find.text(botao), findsOneWidget);
  });

  testWidgets('cabe no celular (360 dp)', (tester) async {
    await abrirModal(tester, largura: 360);
    await preencherERevisar(tester);
    expect(tester.takeException(), isNull);
  });

  test('API: rota, corpo e resposta', () async {
    http.Request? ultimo;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        ultimo = r;
        return http.Response('{"resultado":"ok","moedas_devolvidas":7}', 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final r = await api.registrarFalhaTrato(codigo, motivo: 'Motivo bem explicado');
    expect(ultimo!.method, 'POST');
    expect(ultimo!.url.path, '/v1/admin/exclusividades/$codigo/falha-trato');
    expect(jsonDecode(ultimo!.body), {'motivo': 'Motivo bem explicado'});
    expect(r.moedasDevolvidas, 7);
  });
}
