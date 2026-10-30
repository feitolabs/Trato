import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

Future<void> rolar(WidgetTester tester, Finder alvo) => rolarListaAte(tester, alvo);

Future<void> escolher(WidgetTester tester, String decisao) async {
  await rolar(tester, find.text(decisao));
  await tester.tap(find.text(decisao));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('detalhe mostra evidências, nota interna e linha do tempo', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    expect(find.text('Evidências'), findsOneWidget);
    expect(find.textContaining('nota interna (só equipe)'), findsOneWidget);
    expect(find.text('Linha do tempo'), findsOneWidget);
    expect(find.textContaining('Problema relatado'), findsWidgets);
    expect(find.text('Liberar tudo ao profissional'), findsOneWidget);
    expect(find.text('Reembolso total ao cliente'), findsOneWidget);
    expect(find.text('Reembolso parcial'), findsOneWidget);
    expect(find.text('Nova visita do profissional'), findsOneWidget);
  });

  testWidgets('justificativa é obrigatória', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    await escolher(tester, 'Nova visita do profissional');
    await rolar(tester, find.text('Registrar decisão'));
    await tester.tap(find.text('Registrar decisão'));
    await tester.pumpAndSettle();
    expect(find.text('Explique a decisão.'), findsOneWidget);
    expect(find.text('Será registrado na auditoria.'), findsWidgets);
  });

  testWidgets('decisão dentro da alçada é registrada', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    await escolher(tester, 'Reembolso parcial');
    await tester.enterText(find.widgetWithText(TextField, 'Valor do reembolso (R\$)'), '300,00');
    await tester.enterText(
      find.widgetWithText(TextField, 'Justificativa (obrigatória)'),
      'Parte da pintura precisa de retoque',
    );
    await tester.pump();
    expect(find.text('E-mail da segunda pessoa'), findsNothing);
    await rolar(tester, find.text('Registrar decisão'));
    await tester.tap(find.text('Registrar decisão'));
    await tester.pumpAndSettle();
    expect(find.text('Decidida'), findsWidgets);
  });

  testWidgets('valor acima da alçada fica aguardando outra pessoa', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas'); // alçada de exemplo: R\$ 500,00
    await escolher(tester, 'Reembolso total ao cliente');
    expect(find.textContaining('aguardando outra pessoa'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Justificativa (obrigatória)'),
      'Serviço não entregue como combinado',
    );
    await rolar(tester, find.text('Enviar para aprovação'));
    await tester.tap(find.text('Enviar para aprovação'));
    await tester.pumpAndSettle();
    expect(find.text('Aguardando segunda pessoa'), findsWidgets);
    // o mediador não tem a permissão de aprovar
    expect(find.text('Aprovar decisão'), findsNothing);
  });

  testWidgets('reembolso parcial maior que o valor em análise é recusado na tela', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'disputas');
    await escolher(tester, 'Reembolso parcial');
    await tester.enterText(find.widgetWithText(TextField, 'Valor do reembolso (R\$)'), '99999,00');
    await tester.enterText(
      find.widgetWithText(TextField, 'Justificativa (obrigatória)'),
      'Teste de valor alto demais',
    );
    await rolar(tester, find.widgetWithText(FilledButton, 'Enviar para aprovação'));
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar para aprovação'));
    await tester.pumpAndSettle();
    expect(find.text('O valor passa do que está em análise.'), findsOneWidget);
  });

  testWidgets('atendente N2 acompanha mas não decide', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2', secao: 'disputas');
    await irPara(tester, 'disputas');
    expect(find.text('Seu papel acompanha a disputa, mas não decide.'), findsOneWidget);
    expect(find.text('Registrar decisão'), findsNothing);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(vazio: true), secao: 'disputas');
    expect(find.text('Nenhuma disputa aberta.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(erro: true), secao: 'disputas');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
