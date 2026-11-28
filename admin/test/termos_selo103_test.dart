import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/disputas_tela.dart';
import 'package:trato_admin/telas/selo_profissional.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Finder _modal() => find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet);

Finder _noModal(Finder alvo) => find.descendant(of: _modal(), matching: alvo);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _motivo(WidgetTester tester, String texto) async {
  await tester.enterText(_noModal(find.widgetWithText(TextField, 'Motivo')), texto);
  await tester.pump();
}

TextField _campoMotivo(WidgetTester tester) =>
    tester.widget<TextField>(_noModal(find.widgetWithText(TextField, 'Motivo')));

Future<void> _confirmar(WidgetTester tester) async {
  await _clicar(tester, _noModal(find.text('Revisar')));
  await _clicar(tester, _noModal(find.text('Confirmar')));
}

Future<void> _abrirProfissional(WidgetTester tester, ApiFake api, String papel) async {
  await abrirPainel(tester, papel: papel, api: api, secao: 'busca');
  final pro = api.usuariosFake.firstWhere((u) => u.tipo == 'Profissional');
  await _clicar(tester, find.text(pro.nome).first);
}

void main() {
  test('permissões do selo por papel', () {
    Set<Papel> quem(Permissao p) => {for (final x in Papel.values) if (x.pode(p)) x};
    expect(quem(Permissao.seloRetirar), {Papel.cadastro, Papel.seguranca, Papel.administrador});
    expect(quem(Permissao.seloRegularizar), {Papel.cadastro, Papel.administrador});
  });

  test('chave tem de 8 a 100 caracteres e não repete', () {
    final a = gerarChaveDoSelo();
    expect(a.length, inInclusiveRange(8, 100));
    expect(gerarChaveDoSelo(), isNot(a));
  });

  testWidgets('segurança retira e pede reconferência, mas não regulariza', (tester) async {
    await _abrirProfissional(tester, ApiFake(), 'seguranca');
    await tester.ensureVisible(find.text('Retirar selo'));
    expect(find.text('Pedir reconferência'), findsOneWidget);
    expect(find.text('Regularizar selo'), findsNothing);
  });

  testWidgets('quem não tem permissão de selo não vê o cartão', (tester) async {
    await _abrirProfissional(tester, ApiFake(), 'atendente_n1');
    expect(find.text('Selo de verificação'), findsNothing);
    expect(find.text('Retirar selo'), findsNothing);
  });

  testWidgets('sem resposta, a repetição usa a mesma chave, mesmo reabrindo; depois do sucesso, chave nova',
      (tester) async {
    final api = ApiFake()
      ..falhasSelo.addAll([
        const ErroApi('Não foi possível falar com o servidor.'),
        const ErroApi('Não foi possível falar com o servidor.'),
      ]);
    await _abrirProfissional(tester, api, 'cadastro');
    await _clicar(tester, find.text('Retirar selo'));
    expect(_noModal(_contem(kAvisoMotivoDoSelo)), findsOneWidget);
    await _motivo(tester, 'curto');
    await _clicar(tester, _noModal(find.text('Revisar')));
    expect(_noModal(find.text('Confirmar')), findsNothing);
    await _motivo(tester, 'Documento com divergência');
    expect(_noModal(_contem(kMotivoTravado)), findsNothing);
    await _confirmar(tester);
    expect(_noModal(_contem('Não foi possível falar')), findsOneWidget);
    expect(_noModal(_contem(kMotivoTravado)), findsOneWidget);
    expect(_campoMotivo(tester).readOnly, isTrue);
    await _confirmar(tester);
    await _clicar(tester, _noModal(find.text('Cancelar')));
    await _clicar(tester, find.text('Retirar selo'));
    expect(_noModal(find.text('Documento com divergência')), findsOneWidget);
    expect(_campoMotivo(tester).readOnly, isTrue);
    await _confirmar(tester);
    expect(api.chamadasSelo, hasLength(3));
    expect({for (final c in api.chamadasSelo) c.motivo}, {'Documento com divergência'});
    expect({for (final c in api.chamadasSelo) c.chave}, hasLength(1));
    expect(api.chamadasSelo.last.operacao, 'retirar');
    expect(find.text('Selo retirado.'), findsOneWidget);
    expect(find.text('basico'), findsOneWidget);
    expect(find.text('Retirada em aberto'), findsOneWidget);

    await _clicar(tester, find.text('Retirar selo'));
    expect(_campoMotivo(tester).readOnly, isFalse);
    await _motivo(tester, 'Outra divergência encontrada');
    await _confirmar(tester);
    expect(api.chamadasSelo.last.chave, isNot(api.chamadasSelo.first.chave));
  });

  testWidgets('403 depois de envio sem resposta não libera; 409 libera com chave nova', (tester) async {
    final api = ApiFake()
      ..falhasSelo.addAll([
        const ErroApi('Algo deu errado no servidor (500).'),
        const ErroApi('Seu papel não pode fazer isso.', status: 403),
        const ErroApi('Este profissional não tem selo para retirar.', status: 409),
        const ErroApi('Algo deu errado no servidor (500).'),
      ]);
    await _abrirProfissional(tester, api, 'cadastro');
    await _clicar(tester, find.text('Retirar selo'));
    await _motivo(tester, 'Documento com divergência');
    await _confirmar(tester);
    await _confirmar(tester);
    expect(_campoMotivo(tester).readOnly, isTrue);
    await _confirmar(tester);
    expect(_campoMotivo(tester).readOnly, isFalse);
    await _motivo(tester, 'Motivo corrigido depois da recusa');
    await _confirmar(tester);
    // Sem resposta no mesmo modal, depois de uma recusa: reabrir mantém a chave e o motivo.
    await _clicar(tester, _noModal(find.text('Cancelar')));
    await _clicar(tester, find.text('Retirar selo'));
    expect(_campoMotivo(tester).readOnly, isTrue);
    await _confirmar(tester);
    final chaves = [for (final c in api.chamadasSelo) c.chave];
    expect({chaves[0], chaves[1], chaves[2]}, hasLength(1));
    expect(chaves[3], isNot(chaves[0]));
    expect(chaves[4], chaves[3]);
    expect(api.chamadasSelo.last.motivo, 'Motivo corrigido depois da recusa');
  });

  testWidgets('recusa 409 aparece no modal e regularizar envia a operação certa', (tester) async {
    final api = ApiFake()..falhasSelo.add(const ErroApi('Não há retirada de selo para regularizar.', status: 409));
    await _abrirProfissional(tester, api, 'cadastro');
    await _clicar(tester, find.text('Regularizar selo'));
    await _motivo(tester, 'Conferência concluída sem problema');
    await _confirmar(tester);
    expect(_noModal(_contem('Não há retirada de selo')), findsOneWidget);
    expect(find.text('Retirada em aberto'), findsNothing);
    await _confirmar(tester);
    expect([for (final c in api.chamadasSelo) c.operacao], ['regularizar', 'regularizar']);
    expect(find.text('Selo regularizado.'), findsOneWidget);
  });

  testWidgets('verificação: selo_retirado mostra a recusa e orienta, sem regularizar sozinho', (tester) async {
    final api = ApiFake()
      ..falhaDecisaoVerificacao = const ErroApi('O selo deste profissional foi retirado (Termos 10.3).',
          status: 409, codigo: 'selo_retirado');
    await abrirPainel(tester, papel: 'cadastro', api: api, secao: 'verificacao');
    await _clicar(tester, find.text('Aprovar profissional').first);
    await confirmarMotivo(tester, 'Aprovar profissional');
    expect(_contem('O selo deste profissional foi retirado'), findsWidgets);
    expect(_contem(kOrientacaoSeloRetirado), findsOneWidget);
    expect(api.chamadasSelo, isEmpty);
  });

  testWidgets('disputa sem o campo não mostra "o que o cliente pede"', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    expect(find.text('Evidências'), findsOneWidget);
    expect(find.text('O que o cliente pede'), findsNothing);
    expect(rotuloResultadoEsperado('reembolso_total'), 'Reembolso total');
    expect(rotuloResultadoEsperado('retrabalho'), 'Retrabalho');
  });

  test('API: rotas do selo, corpo sem campo extra, nível do usuário e resultado esperado', () async {
    final pedidos = <http.Request>[];
    var esperado = <String, Object?>{'resultado_esperado': 'reembolso_parcial'};
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
        pedidos.add(r);
        final Object corpo = switch (r.url.path) {
          '/v1/admin/usuarios' => {
              'itens': [
                {'id': 'p1', 'nome': 'Pro', 'tipo': 'profissional', 'status': 'ativo', 'nivel_verificacao': 'verificado'},
              ],
            },
          '/v1/admin/disputas/d1' => {
              'pedido_id': 'abcd-1234',
              'valor_congelado_centavos': 100,
              'decisao_ate': '2026-11-30T12:00:00Z',
              'estado': 'aberta',
              ...esperado,
            },
          _ => {'resultado': 'ja_existe', 'evento_id': 'e1', 'nivel_verificacao': 'basico', 'retirada_aberta': true},
        };
        return http.Response(jsonEncode(corpo), 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    for (final op in ['retirar', 'reconferencia', 'regularizar']) {
      final r = await api.mudarSelo('p1', op, motivo: 'motivo de teste', chaveIdempotencia: 'chave-123');
      expect(pedidos.last.url.path, '/v1/admin/profissionais/p1/selo/$op');
      expect(jsonDecode(pedidos.last.body), {'motivo': 'motivo de teste', 'chave_idempotencia': 'chave-123'});
      expect((r.jaExistia, r.nivelVerificacao, r.retiradaAberta), (true, 'basico', true));
    }
    expect((await api.buscarUsuarios('')).single.nivelVerificacao, 'verificado');
    expect((await api.obterDisputa('d1')).resultadoEsperado, 'reembolso_parcial');
    esperado = {};
    expect((await api.obterDisputa('d1')).resultadoEsperado, isNull);
  });

  testWidgets('disputa com o campo mostra o pedido do cliente', (tester) async {
    final api = ApiFake()..definirResultadoEsperado('retrabalho');
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas');
    expect(find.text('O que o cliente pede'), findsOneWidget);
    expect(find.text('Retrabalho'), findsWidgets);
  });
}
