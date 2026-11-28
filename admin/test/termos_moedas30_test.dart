import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/aviso_tratinhos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 13.11 e I.12: recusa da configuração e aviso prévio dos Tratinhos.
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);
Finder _noDialogo(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _escrever(WidgetTester tester, Finder campo, String texto) async {
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Finder _campo(String rotulo) => _noDialogo(find.widgetWithText(TextField, rotulo));

Future<ApiFake> _preencherAviso(WidgetTester tester, {ApiFake? api}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: 'moderador', api: fake, secao: 'moedas');
  await _clicar(tester, find.text('Emitir aviso'));
  await _escrever(tester, _campo('Referência do aviso'), 'tratinhos-2027.1');
  await _clicar(tester, _noDialogo(find.text('Passa a valer em')));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await _escrever(tester, _campo('Resumo que o usuário vai ler'), 'O bônus por avaliação vai mudar.');
  await _escrever(tester, _campo('Motivo (auditoria)'), 'Ajuste do programa');
  return fake;
}

void main() {
  testWidgets('aviso: envia mudanças em inteiros só depois de confirmar', (tester) async {
    final api = await _preencherAviso(tester);
    expect(_contem('o servidor recusa, mesmo com aviso'), findsOneWidget);
    await _clicar(tester, _noDialogo(find.byType(DropdownButtonFormField<String>)));
    await tester.tap(find.text('Serviço mínimo para ganhar').last);
    await tester.pumpAndSettle();
    await _clicar(tester, _noDialogo(find.text('Revisar aviso')));
    expect(_noDialogo(find.text('Enviar aos usuários')), findsNothing); // falta o valor
    await _escrever(tester, find.byKey(const ValueKey('aviso-valor-min_servico_centavos')), '75,50');
    await _clicar(tester, _noDialogo(find.text('Revisar aviso')));
    expect(_contem('O aviso vai para os usuários'), findsOneWidget);
    expect(api.avisosTratinhos, isEmpty);
    await _clicar(tester, _noDialogo(find.text('Enviar aos usuários')));
    expect(api.avisosTratinhos.single['mudancas'], {'min_servico_centavos': 7550});
    expect(_contem('Aviso enviado.'), findsOneWidget);
    expect(_noDialogo(find.text('Repetir envio')), findsNothing);
  });

  testWidgets('aviso com falhas não vale e oferece repetir; sem mudanças é dito', (tester) async {
    final api = await _preencherAviso(tester, api: ApiFake()..falhasDoAviso = [3]);
    await _clicar(tester, _noDialogo(find.text('Revisar aviso')));
    expect(_contem('não libera piora'), findsOneWidget);
    await _clicar(tester, _noDialogo(find.text('Enviar aos usuários')));
    expect(_contem('O aviso não vale.'), findsOneWidget);
    expect(_contem('3 pessoa(s) não foram avisadas'), findsOneWidget);
    await _clicar(tester, _noDialogo(find.text('Repetir envio')));
    expect(api.avisosTratinhos.length, 2);
    expect(api.avisosTratinhos[1], api.avisosTratinhos[0]);
    expect(_contem('Aviso enviado.'), findsOneWidget);
  });

  testWidgets('sem permissão de envio não há aviso', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'moedas');
    expect(find.text('Salvar configuração'), findsOneWidget);
    expect(find.text('Emitir aviso'), findsNothing);
  });

  testWidgets('409 mostra mensagem, campos e data em Brasília; a referência vai no salvar', (tester) async {
    final api = ApiFake()
      ..falhaMoedas = const ErroApi('O aviso ainda está no prazo (exemplo).',
          status: 409,
          codigo: 'aviso_no_prazo',
          campos: ['min_servico_centavos', 'ativo'],
          podeValerEm: '2026-12-28T02:30:00+00:00');
    await abrirPainel(tester, papel: 'financeiro', api: api, secao: 'moedas');
    await _escrever(tester, find.byKey(const ValueKey('moedas-aviso-referencia')), 'ref-1');
    await _clicar(tester, find.text('Salvar configuração'));
    await confirmarMotivo(tester, 'Salvar configuração');
    expect(api.ultimaReferenciaDeAviso, 'ref-1');
    final banner = find.byType(RecusaDaConfigTratinhos);
    for (final trecho in [
      'O aviso ainda está no prazo (exemplo).',
      'Serviço mínimo para ganhar, Programa ativo',
      '27/12/2026 23:30 (horário de Brasília)',
    ]) {
      expect(find.descendant(of: banner, matching: _contem(trecho)), findsOneWidget);
    }
  });

  test('data em Brasília', () {
    expect(dataEmBrasilia('2026-12-27T00:00:00-03:00'), contains('27/12/2026 00:00'));
    expect(dataEmBrasilia('2026-12-27'), '27/12/2026 (horário de Brasília)');
  });

  test('API: corpo do aviso, aviso_referencia e campos do 409', () async {
    final pedidos = <http.Request>[];
    var status = 200;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
        pedidos.add(r);
        final Object corpo = status == 409
            ? {'codigo': 'creditos_vigentes', 'detail': 'Há Tratinhos válidos.', 'campos': ['valor_moeda_centavos']}
            : {'antecedencia_minima_dias': 30, 'destinatarios': 5, 'avisos_novos': 9, 'falhas': 1};
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    Map<String, dynamic> enviado() => jsonDecode(pedidos.last.body) as Map<String, dynamic>;
    Future<ResultadoAvisoPrevio> avisar(Map<String, Object> m) => api.enviarAvisoTratinhos(
        referencia: 'r1', vigencia: DateTime(2027, 1, 5), resumo: 'resumo longo', motivo: 'motivo longo', mudancas: m);

    expect((await avisar({'ativo': false})).falhas, 1);
    expect(pedidos.last.url.path, '/v1/admin/avisos-previos');
    expect(enviado(), {
      'tipo': 'tratinhos',
      'referencia': 'r1',
      'vigencia': '2027-01-05',
      'resumo': 'resumo longo',
      'motivo': 'motivo longo',
      'mudancas': {'ativo': false},
    });
    await avisar(const {});
    expect(enviado().containsKey('mudancas'), isFalse);

    status = 409;
    const config = MoedasConfig(
        ativo: true,
        bonusAvaliacaoMoedas: 1,
        valorMoedaCentavos: 1,
        tetoMensalMoedas: 1,
        minServicoCentavos: 1,
        maxBonusPorProfissionalMes: 1,
        maxDescontoPercentual: 1,
        validadeDias: null,
        orcamentoMensalDescontoCentavos: 1,
        avisoPercentual: 1,
        tetoDescontoClienteMesCentavos: 1,
        tetoDiarioDescontoCentavos: 1,
        diasLiberacaoBonus: 1);
    await expectLater(
      api.salvarMoedasConfig(config, motivo: 'motivo longo', avisoReferencia: 'r1'),
      throwsA(isA<ErroApi>()
          .having((e) => e.codigo, 'codigo', 'creditos_vigentes')
          .having((e) => e.campos, 'campos', ['valor_moeda_centavos'])
          .having((e) => e.podeValerEm, 'data', isNull)),
    );
    expect(enviado()['aviso_referencia'], 'r1');
  });
}
