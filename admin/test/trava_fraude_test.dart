import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/campos_trava.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Trava de saques por fraude (Termos 20.6): o painel só pede, mostra e avisa quando ela acaba.
Finder _noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Future<void> _escrever(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pump();
}

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Medida _travaPorFraude({bool fraude = true, ContestacaoMedida? contestacao}) => Medida(
      id: 'med-f',
      protocolo: 'MED-EXEMPLO-F',
      usuarioId: 'u-103',
      tipo: 'trava_saque',
      motivoAoUsuario: 'Texto (exemplo)',
      motivoCompleto: 'Texto (exemplo)',
      clausulas: const ['20.6'],
      inicioEm: DateTime(2026, 11, 20),
      fimEm: DateTime(2026, 12, 20),
      efeito: 'Efeito (exemplo)',
      comoContestar: 'Como contestar (exemplo)',
      vigente: true,
      motivoFraude: fraude,
      limiteRetencaoCentavos: fraude ? 123456 : null,
      contestacao: contestacao,
    );

ContestacaoMedida _contestacaoAberta() => ContestacaoMedida(
      status: 'aberta',
      versao: 'Não fui eu (exemplo)',
      canal: 'app',
      abertaEm: DateTime(2026, 11, 21),
      responderAte: DateTime(2026, 12, 5),
    );

Future<ApiFake> _abrirTravaNoRisco(WidgetTester tester) async {
  final api = ApiFake();
  await abrirPainel(tester, papel: 'administrador', api: api, secao: 'risco');
  await tester.tap(find.textContaining(RegExp(r'^Todos \d+$')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Troca de chave PIX').first);
  await tester.pumpAndSettle();
  await rolarListaAte(tester, find.text('Registrar trava'));
  await _clicar(tester, find.text('Registrar trava'));
  await _escrever(tester, 'Motivo interno (o usuário não vê)', 'Chave trocada duas vezes');
  await _escrever(tester, 'Motivo que o usuário vai ler', 'Atividade fora do padrão na conta');
  await _escrever(tester, 'Cláusulas dos Termos', '20.6');
  return api;
}

void main() {
  testWidgets('risco: por fraude exige limite, envia centavos e dias, e avisa ao destravar', (tester) async {
    final api = await _abrirTravaNoRisco(tester);
    await _clicar(tester, _noModal('Por fraude'));
    expect(_contem('Pagamento manual ou no Stripe continua sem trava'), findsWidgets);
    await _clicar(tester, _noModal('Registrar trava'));
    expect(api.ultimaTrava, isNull); // falta o limite
    await _escrever(tester, 'Limite da retenção (prejuízo apurado)', '1.234,56');
    await _escrever(tester, 'Duração da trava em dias', '10');
    await _clicar(tester, _noModal('Registrar trava'));
    expect(api.ultimaTrava, {'fraude': true, 'limite': 123456, 'dias': 10});

    // Conta restrita: dá para registrar de novo (renovar) ou remover, com o aviso do que encerra.
    await rolarListaAte(tester, find.text('Remover trava'));
    expect(find.text('Registrar trava'), findsOneWidget);
    await _clicar(tester, find.text('Remover trava'));
    expect(find.descendant(of: find.byType(Dialog), matching: _contem(kFimDaTravaAoDestravar)), findsOneWidget);
  });

  testWidgets('risco: sem fraude não envia limite nem dias', (tester) async {
    final api = await _abrirTravaNoRisco(tester);
    expect(_contem(kTravaSemFraude), findsOneWidget);
    await _clicar(tester, _noModal('Registrar trava'));
    expect(api.ultimaTrava, {'fraude': false, 'limite': null, 'dias': null});
  });

  testWidgets('medidas: formulário pede o limite e avisa se o servidor não confirmar a fraude', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
    await tester.tap(find.text('Aplicar medida'));
    await tester.pumpAndSettle();
    await _escrever(tester, 'Código da conta', 'u-103');
    await _clicar(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('Trava de saques').last);
    await tester.pumpAndSettle();
    await _clicar(tester, _noModal('Por fraude'));
    await _escrever(tester, 'Motivo (o usuário lê)', 'Prejuízo apurado na conta');
    await _escrever(tester, 'Cláusulas dos Termos', '20.6');
    await _clicar(tester, _noModal('Revisar medida'));
    expect(_noModal('Confirmar e aplicar'), findsNothing);
    await _escrever(tester, 'Limite da retenção em R\$ (prejuízo apurado)', '50,00');
    await _clicar(tester, _noModal('Revisar medida'));
    expect(_noModal('Prazo máximo configurado no servidor'), findsOneWidget);
    expect(_noModal('R\$ 50,00'), findsOneWidget);
    await _clicar(tester, _noModal('Confirmar e aplicar'));
    final n = api.ultimaMedida!;
    expect((n.tipo, n.motivoFraude, n.limiteRetencaoCentavos, n.dias), ('trava_saque', true, 5000, null));
    // A API falsa devolve uma medida sem a marcação.
    expect(_contem('não confirmou a trava por fraude'), findsOneWidget);
  });

  testWidgets('medidas: detalhe mostra o limite e a reversão avisa que a retenção acaba', (tester) async {
    final api = ApiFake()..medidas = [_travaPorFraude()];
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
    await rolarListaAte(tester, find.text('Reverter medida'));
    await _clicar(tester, find.text('Reverter medida'));
    expect(find.descendant(of: find.byType(Dialog), matching: _contem(kFimDaTravaAoReverter)), findsOneWidget);
    expect(api.chamadasMedida, isEmpty);
  });

  for (final (nome, medida, avisa) in [
    ('trava por fraude avisa', _travaPorFraude(contestacao: _contestacaoAberta()), true),
    ('trava sem fraude não avisa', _travaPorFraude(fraude: false, contestacao: _contestacaoAberta()), false),
    ('suspensão não avisa', ApiFake.medidaDeExemplo(contestacao: _contestacaoAberta()), false),
  ]) {
    testWidgets('contestação, encurtar: $nome antes de confirmar', (tester) async {
      final api = ApiFake()..medidas = [medida];
      await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
      await rolarListaAte(tester, find.text('Encurtar'));
      await _clicar(tester, find.text('Encurtar'));
      final resposta = find.widgetWithText(TextField, 'Resposta que o usuário vai ler');
      await rolarListaAte(tester, resposta);
      await tester.enterText(resposta, 'Analisamos a sua versão e as provas');
      await tester.pumpAndSettle();
      final dias = find.widgetWithText(TextField, 'Novo prazo (dias a partir de hoje)');
      await tester.ensureVisible(dias);
      await tester.enterText(dias, '3');
      await tester.pumpAndSettle();
      await rolarListaAte(tester, find.text('Revisar decisão'));
      await _clicar(tester, find.text('Revisar decisão'));
      expect(
        find.descendant(of: find.byType(Dialog), matching: _contem(kFimDaTravaAoEncurtar)),
        avisa ? findsOneWidget : findsNothing,
      );
      expect(find.descendant(of: find.byType(Dialog), matching: _contem(kFimDaTravaAoReverter)), findsNothing);
      expect(api.chamadasMedida, isEmpty);
      await _clicar(tester, _noModal('Enviar decisão'));
      expect(api.chamadasMedida.single.$2['dias'], 3);
    });
  }

  testWidgets('busca: voltar uma conta restrita para ativo avisa que encerra a trava', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'busca');
    await tester.tap(find.text('Paulo Lima').first);
    await tester.pumpAndSettle();
    await rolarListaAte(tester, find.text('Alterar status'));
    await _clicar(tester, find.text('Alterar status').first);
    expect(_contem(kFimDaTravaAoAtivar), findsNothing);
    await _clicar(tester, find.descendant(of: find.byType(Dialog), matching: _contem('Restrito (atividades')).first);
    await tester.tap(_contem('Ativo (acesso normal)').last);
    await tester.pumpAndSettle();
    expect(_contem(kFimDaTravaAoAtivar), findsOneWidget);
  });

  test('API: o limite só vai com fraude; a medida lê os dois campos', () async {
    final pedidos = <http.Request>[];
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        final corpo = r.url.path.startsWith('/v1/admin/medidas')
            ? {
                'id': 'm1',
                'usuario_id': 'u1',
                'tipo': 'trava_saque',
                'motivo': 'm',
                'motivo_completo': 'm',
                'clausulas': ['20.6'],
                'inicio_em': '2026-11-25T10:00:00Z',
                'efeito_pedidos_valores': 'e',
                'como_contestar': 'c',
                'vigente': true,
                'motivo_fraude': true,
                'limite_retencao_centavos': 5000,
              }
            : {'mensagem': 'ok'};
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    Map<String, dynamic> enviado() => jsonDecode(pedidos.last.body) as Map<String, dynamic>;

    await api.travarSaque('u1', motivo: 'interno', limiteRetencaoCentavos: 5000);
    expect(enviado(), {'usuario_id': 'u1', 'motivo': 'interno'});
    await api.travarSaque('u1', motivo: 'interno', motivoFraude: true, limiteRetencaoCentavos: 5000, dias: 7);
    expect(enviado(), {
      'usuario_id': 'u1',
      'motivo': 'interno',
      'motivo_fraude': true,
      'limite_retencao_centavos': 5000,
      'dias': 7,
    });
    final r = await api.aplicarMedida(const NovaMedida(
        usuarioId: 'u1',
        tipo: 'trava_saque',
        motivo: 'motivo longo',
        clausulas: ['20.6'],
        motivoFraude: true,
        limiteRetencaoCentavos: 5000));
    expect((enviado()['motivo_fraude'], enviado()['limite_retencao_centavos']), (true, 5000));
    expect((r.medida.motivoFraude, r.medida.limiteRetencaoCentavos), (true, 5000));
  });
}
