import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/notificacoes_tela.dart';

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

Future<void> _preencher(WidgetTester tester) async {
  for (final (rotulo, texto) in [
    ('Título', 'Aviso de teste'),
    ('Mensagem', 'Mensagem de teste do envio'),
    ('Motivo do disparo', 'Teste do envio de campanha'),
  ]) {
    final campo = find.widgetWithText(TextField, rotulo);
    await tester.ensureVisible(campo);
    await tester.enterText(campo, texto);
    await tester.pump();
  }
}

Future<int> _enviadas(WidgetTester tester, ApiFake api) async {
  final lista = api.listarCampanhasNotificacao();
  await tester.pump(const Duration(seconds: 1));
  return (await lista).length;
}

void main() {
  testWidgets('marketing diz o público e não pede a confirmação do operacional', (tester) async {
    await abrirPainel(tester, api: ApiFake(), secao: 'notificacoes');
    expect(_contem('Campanhas e novidades: $kPublicoDoMarketing'), findsOneWidget);
    expect(_contem('Marketing vai $kPublicoDoMarketing'), findsOneWidget);
    expect(_contem(kOperacionalSemPropaganda), findsNothing);
    await _preencher(tester);
    await _clicar(tester, find.text('Revisar e enviar'));
    expect(_noModal(_contem(kPublicoDoMarketing)), findsOneWidget);
    expect(find.text(kConfirmaSemPropaganda), findsNothing);
  });

  testWidgets('quem fica de fora tem o rótulo novo', (tester) async {
    await abrirPainel(tester, api: ApiFake(), secao: 'notificacoes');
    expect(_contem('Ficam de fora: 412 (sem consentimento, com ele revogado ou com o push desligado)'),
        findsOneWidget);
    expect(_contem('desativaram'), findsNothing);
  });

  testWidgets('503 sem ler o consentimento aparece na estimativa e no envio, sem perder o texto', (tester) async {
    const erro = 'Não foi possível conferir o consentimento de marketing. Nada foi enviado.';
    final api = ApiFake()..falhaCampanha = const ErroApi(erro, status: 503);
    await abrirPainel(tester, api: api, secao: 'notificacoes');
    expect(_contem(erro), findsOneWidget);
    final antes = await _enviadas(tester, api);
    await _preencher(tester);
    await _clicar(tester, find.text('Revisar e enviar'));
    await _clicar(tester, _noModal(find.text('Enviar campanha')));
    expect(_contem('A campanha não foi confirmada.'), findsOneWidget);
    expect(find.text('Mensagem de teste do envio'), findsWidgets);
    expect(await _enviadas(tester, api), antes);
  });

  testWidgets('operacional avisa e só envia depois de confirmar que não há propaganda', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, api: api, secao: 'notificacoes');
    final antes = await _enviadas(tester, api);
    await _clicar(tester, find.text('Operacional').first);
    expect(_contem(kOperacionalSemPropaganda), findsOneWidget);
    await _preencher(tester);
    await _clicar(tester, find.text('Revisar e enviar'));
    expect(_noModal(_contem(kOperacionalSemPropaganda)), findsOneWidget);
    await _clicar(tester, _noModal(find.text('Enviar campanha')));
    expect(_noModal(find.text(kConfirmaSemPropaganda)), findsOneWidget);
    expect(await _enviadas(tester, api), antes);
    await _clicar(tester, _noModal(find.text(kConfirmaSemPropaganda)));
    await _clicar(tester, _noModal(find.text('Enviar campanha')));
    expect(find.text(kConfirmaSemPropaganda), findsNothing);
    expect(await _enviadas(tester, api), antes + 1);

    // A confirmação não fica marcada para o envio seguinte.
    await _preencher(tester);
    await _clicar(tester, find.text('Revisar e enviar'));
    await _clicar(tester, _noModal(find.text('Enviar campanha')));
    expect(await _enviadas(tester, api), antes + 1);
  });
}
