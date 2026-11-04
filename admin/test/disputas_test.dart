import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'apoio/api_fake.dart';

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
    await rolar(tester, find.text('Liberar ao profissional'));
    expect(find.text('Liberar ao profissional'), findsOneWidget);
    expect(find.text('Reembolso total ao cliente'), findsOneWidget);
    expect(find.text('Reembolso parcial'), findsOneWidget);
    expect(find.text('Nova visita do profissional'), findsOneWidget);
  });

  testWidgets('justificativa é obrigatória', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    await escolher(tester, 'Nova visita do profissional');
    await rolar(tester, find.text('Pedir nova visita'));
    await tester.tap(find.text('Pedir nova visita'));
    await tester.pumpAndSettle();
    expect(find.text('Escreva ao menos 10 caracteres'), findsOneWidget);
    expect(find.text('Esta ação fica registrada na auditoria com seu nome e o motivo.'), findsWidgets);
  });

  testWidgets('decisão dentro da alçada é registrada', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    await escolher(tester, 'Reembolso parcial');
    await tester.enterText(find.widgetWithText(TextField, 'Valor do reembolso (R\$)'), '300,00');
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      'Parte da pintura precisa de retoque',
    );
    await tester.pump();
    expect(find.text('E-mail da segunda pessoa'), findsNothing);
    await rolar(tester, find.text('Reembolsar em parte'));
    await tester.tap(find.text('Reembolsar em parte'));
    await tester.pumpAndSettle();
    expect(find.text('Decididas 1'), findsOneWidget);
  });

  testWidgets('valor acima da alçada fica aguardando outra pessoa', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas'); // alçada de exemplo: R\$ 500,00
    await escolher(tester, 'Reembolso total ao cliente');
    expect(find.textContaining('aguardando outra pessoa'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
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
      find.widgetWithText(TextField, 'Motivo'),
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
    await rolar(tester, find.text('Seu papel acompanha a disputa, mas não decide.'));
    expect(find.text('Seu papel acompanha a disputa, mas não decide.'), findsOneWidget);
    expect(find.text('Registrar decisão'), findsNothing);
    expect(find.text('Reembolsar cliente'), findsNothing);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(vazio: true), secao: 'disputas');
    expect(find.text('Nenhuma disputa aberta.'), findsOneWidget);
    expect(find.textContaining('prazo de resposta'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(erro: true), secao: 'disputas');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
