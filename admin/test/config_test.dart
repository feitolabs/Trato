import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

Finder campo(String chave) => find.byKey(ValueKey('campo-$chave'));

Future<void> enviar(WidgetTester tester) async {
  final botao = find.widgetWithText(FilledButton, 'Enviar para aprovação');
  await rolarAte(tester, botao);
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

Future<void> rolarAte(WidgetTester tester, Finder alvo) => rolarListaAte(tester, alvo);

void main() {
  testWidgets('mostra a versão vigente e o histórico', (tester) async {
    await abrirPainel(tester, papel: 'juridico', secao: 'config');
    expect(find.text('Versão vigente: 2'), findsOneWidget);
    expect(find.text('7,50%'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.text('Aguardando aprovação'), findsOneWidget);
    // jurídico só lê
    expect(find.text('Propor mudança'), findsNothing);
    expect(find.text('Aprovar versão'), findsNothing);
  });

  testWidgets('validação de faixa vem da definição', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    await rolarAte(tester, campo('taxa_base_bps'));
    await tester.enterText(campo('taxa_base_bps'), '5000');
    await tester.pump();
    await enviar(tester);
    expect(find.text('Deve ficar entre 100 e 2000.'), findsOneWidget);
  });

  testWidgets('sem mudança não envia', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    await enviar(tester);
    expect(find.text('Nenhum valor mudou.'), findsOneWidget);
  });

  testWidgets('financeiro propõe e não tem botão de aprovar', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    await rolarAte(tester, campo('taxa_base_bps'));
    await tester.enterText(campo('taxa_base_bps'), '800');
    await tester.pump();
    await enviar(tester);
    await confirmarMotivo(tester, 'Enviar');
    await rolarAte(tester, find.text('Versão 4'));
    expect(find.text('Versão 4'), findsOneWidget);
    expect(find.text('Aprovar versão'), findsNothing);
  });

  testWidgets('administrador aprova proposta de outra pessoa', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'config');
    final botao = find.widgetWithText(FilledButton, 'Aprovar versão');
    await rolarAte(tester, botao);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    expect(find.text('Será registrado na auditoria.'), findsWidgets);
    await confirmarMotivo(tester, 'Aprovar');
    expect(find.text('Versão vigente: 3'), findsOneWidget);
  });

  testWidgets('quem propôs não aprova a própria mudança (aprovação dupla)', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'config');
    await rolarAte(tester, campo('prazo_confirmacao_horas'));
    await tester.enterText(campo('prazo_confirmacao_horas'), '60');
    await tester.pump();
    await enviar(tester);
    await confirmarMotivo(tester, 'Enviar');
    await rolarAte(tester, find.textContaining('Você propôs esta versão'));
    expect(find.textContaining('Você propôs esta versão'), findsOneWidget);
  });

  testWidgets('reverter cria nova versão para aprovação', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    final botao = find.text('Reverter para esta versão');
    await rolarAte(tester, botao);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Pedir reversão');
    await rolarAte(tester, find.text('Versão 4'));
    expect(find.text('Versão 4'), findsOneWidget);
    expect(find.textContaining('Reversão para a versão'), findsOneWidget);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', api: ApiFake(vazio: true), secao: 'config');
    expect(find.text('Nenhum parâmetro cadastrado.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', api: ApiFake(erro: true), secao: 'config');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
