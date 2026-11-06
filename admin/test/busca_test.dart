import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'apoio/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('busca de usuário mostra dados mascarados e filtra por nome', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', secao: 'busca');
    expect(find.text('Marina Souza'), findsWidgets);
    expect(find.text('m•••••@exemplo.com · (31) •••••-1190'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Buscar usuário por nome'), 'carlos');
    await tester.pumpAndSettle();
    expect(find.text('Marina Souza'), findsNothing);
    expect(find.text('Carlos Pereira'), findsWidgets);
  });

  testWidgets('profissional mostra categorias cadastradas e o diagnóstico do pedido (RN-01)', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'busca');
    await tester.tap(find.text('Carlos Pereira').first);
    await tester.pumpAndSettle();
    expect(find.text('Categorias cadastradas'), findsOneWidget);
    expect(find.text('Pintor · ativa'), findsOneWidget);
    expect(find.text('Eletricista · inativa no perfil'), findsOneWidget);
    await rolarListaAte(tester, find.text('Por que este pedido não aparece para ele?'));
    await tester.enterText(find.widgetWithText(TextField, 'Pedido'), 'PED-10482');
    await tester.tap(find.text('Diagnosticar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não tem a categoria ativa.'), findsOneWidget);
    expect(find.textContaining('Regra RN-01'), findsOneWidget);
  });

  testWidgets('revelar dado pessoal pede motivo', (tester) async {
    await abrirPainel(tester, papel: 'dpo', secao: 'busca');
    await tester.tap(find.text('Revelar dados pessoais').first);
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Revelar');
    expect(find.text('pessoa@exemplo.com'), findsOneWidget);
  });

  testWidgets('alterar status exige status novo e motivo', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'busca');
    await tester.tap(find.text('Alterar status').first);
    await tester.pumpAndSettle();
    final botao = find.widgetWithText(FilledButton, 'Alterar status');
    expect(tester.widget<FilledButton>(botao).onPressed, isNull);
  });

  testWidgets('atendente N1 não revela dados nem vê categorias', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n1', secao: 'busca');
    expect(find.text('Revelar dados pessoais'), findsNothing);
    expect(find.text('Categorias'), findsNothing);
    expect(find.text('Usuários'), findsOneWidget);
    expect(find.text('Suporte'), findsOneWidget);
  });

  testWidgets('aba de pedidos mostra código e título legíveis, nunca só o UUID', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n1', secao: 'busca');
    await tester.tap(find.text('Pedidos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PED-10482 · Troca de chuveiro'), findsOneWidget);
    expect(find.textContaining('Cliente Marina Souza · profissional Carlos Pereira'), findsOneWidget);
    expect(find.text('Eletricista · Belo Horizonte'), findsOneWidget);
  });

  testWidgets('aba de suporte mostra prioridade, responsável e prazo', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n1', secao: 'busca');
    await tester.tap(find.text('Suporte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CH-31'), findsOneWidget);
    expect(find.text('Prioridade alta'), findsOneWidget);
    expect(find.textContaining('Responsável Bruna Teixeira'), findsOneWidget);
  });

  testWidgets('moderador desativa categoria com motivo', (tester) async {
    await abrirPainel(tester, papel: 'moderador', secao: 'busca');
    await tester.tap(find.text('Categorias'));
    await tester.pumpAndSettle();
    expect(find.text('Elétrica'), findsOneWidget);
    await tester.tap(find.text('Desativar').first);
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Desativar categoria');
    expect(find.text('Inativa'), findsNWidgets(2));
  });

  testWidgets('categoria com nome igual (sem acento e caixa) é barrada', (tester) async {
    await abrirPainel(tester, papel: 'moderador', secao: 'busca');
    await tester.tap(find.text('Categorias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova categoria'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome da categoria'), 'ELETRICA');
    await tester.pump();
    expect(find.text('Já existe uma categoria com esse nome.'), findsOneWidget);
  });

  testWidgets('cidades: ativar e desativar com motivo', (tester) async {
    await abrirPainel(tester, papel: 'moderador', secao: 'busca');
    await tester.tap(find.text('Cidades'));
    await tester.pumpAndSettle();
    expect(find.text('Nova cidade'), findsOneWidget);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', api: ApiFake(vazio: true), secao: 'busca');
    expect(find.text('Nenhum usuário encontrado.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', api: ApiFake(erro: true), secao: 'busca');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
