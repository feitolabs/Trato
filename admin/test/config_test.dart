import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

Finder campo(String chave) => find.byKey(ValueKey('campo-$chave'));

Future<void> rolarAte(WidgetTester tester, Finder alvo) => rolarListaAte(tester, alvo);

void main() {
  testWidgets('parâmetros têm nome legível, valor em % e R\$, unidade e faixa', (tester) async {
    await abrirPainel(tester, papel: 'juridico', secao: 'config');
    expect(find.text('Taxa do Trato por serviço'), findsOneWidget);
    expect(find.text('Percentual retido sobre o valor do serviço concluído'), findsOneWidget);
    expect(find.text('0% a 20%'), findsOneWidget);
    expect(find.text('7,50%'), findsOneWidget);
    expect(find.text('Taxa mínima por pedido'), findsOneWidget);
    expect(find.text('R\$ 3,00'), findsOneWidget);
    expect(find.text('R\$ 0,00 a R\$ 50,00'), findsOneWidget);
    // nada de nome técnico, prefixo "teste_" nem unidade interna
    expect(find.textContaining('teste_'), findsNothing);
    expect(find.textContaining('bps'), findsNothing);
    expect(find.textContaining('centavos'), findsNothing);
  });

  testWidgets('temas separam os parâmetros', (tester) async {
    await abrirPainel(tester, papel: 'juridico', secao: 'config');
    await tester.tap(find.text('Disputas'));
    await tester.pumpAndSettle();
    expect(find.text('Prazo de resposta da disputa'), findsOneWidget);
    expect(find.text('48 horas'), findsOneWidget);
    expect(find.text('1 a 720 horas'), findsWidgets);
    expect(find.text('Prazo de decisão da disputa'), findsOneWidget);
    expect(find.text('5 dias úteis'), findsOneWidget);
    expect(find.text('Taxa do Trato por serviço'), findsNothing);
  });

  testWidgets('mostra a proposta pendente e o histórico de versões', (tester) async {
    await abrirPainel(tester, papel: 'juridico', secao: 'config');
    expect(find.textContaining('Aprovação pendente.'), findsOneWidget);
    expect(find.textContaining('João Vitor Cardoso propôs mudar'), findsOneWidget);
    expect(find.textContaining('volume alto de feriado'), findsWidgets);
    await rolarAte(tester, find.text('Histórico de versões'));
    expect(find.text('Versão 2 · atual'), findsOneWidget);
    // jurídico só lê
    expect(find.text('Propor'), findsNothing);
    expect(find.text('Aprovar mudança'), findsNothing);
  });

  testWidgets('validação de faixa mostra a faixa permitida', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    await tester.enterText(campo('taxa_bps'), '50');
    await tester.pump();
    expect(find.text('Fora da faixa: 0% a 20%'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Propor').first).onPressed, isNull);
  });

  testWidgets('prazo de resposta da disputa precisa ser menor que o de decisão', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    await tester.tap(find.text('Disputas'));
    await tester.pumpAndSettle();
    await tester.enterText(campo('prazo_resposta_disputa_horas'), '200');
    await tester.pump();
    expect(find.text('A resposta precisa ser menor que a decisão'), findsWidgets);
  });

  testWidgets('financeiro propõe, vê valor atual e proposto e não aprova', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    await tester.enterText(campo('taxa_bps'), '8');
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Propor').first);
    await tester.pumpAndSettle();
    expect(find.text('Valor atual'), findsWidgets);
    expect(find.text('Valor proposto'), findsWidgets);
    expect(find.text('8,00%'), findsOneWidget);
    await confirmarMotivo(tester, 'Enviar para aprovação');
    expect(find.text('Mudança enviada para aprovação.'), findsOneWidget);
    expect(find.text('Aprovar mudança'), findsNothing);
  });

  testWidgets('administrador aprova proposta de outra pessoa', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'config');
    await tester.tap(find.text('Aprovar mudança'));
    await tester.pumpAndSettle();
    expect(find.text('Esta ação fica registrada na auditoria com seu nome e o motivo.'), findsWidgets);
    await confirmarMotivo(tester, 'Aprovar mudança');
    await rolarAte(tester, find.text('Versão 3 · atual'));
    expect(find.text('Versão 3 · atual'), findsOneWidget);
  });

  testWidgets('administrador recusa a proposta', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'config');
    await tester.tap(find.text('Recusar proposta'));
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Recusar proposta');
    expect(find.textContaining('Aprovação pendente.'), findsNothing);
  });

  testWidgets('reverter cria nova versão para aprovação', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'config');
    final botao = find.text('Reverter');
    await rolarAte(tester, botao);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Pedir reversão');
    expect(find.text('Reversão enviada para aprovação.'), findsOneWidget);
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
