import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('busca de usuário mostra dados mascarados e filtra por nome', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', secao: 'busca');
    expect(find.text('Marina Souza'), findsOneWidget);
    expect(find.text('m*****@exemplo.com'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Buscar usuário por nome'), 'carlos');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();
    expect(find.text('Marina Souza'), findsNothing);
    expect(find.text('Carlos Pereira'), findsOneWidget);
  });

  testWidgets('revelar dado pessoal pede motivo', (tester) async {
    await abrirPainel(tester, papel: 'dpo', secao: 'busca');
    await tester.tap(find.text('Revelar dados pessoais').first);
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Revelar');
    expect(find.text('pessoa@exemplo.com'), findsOneWidget);
  });

  testWidgets('atendente N1 não revela dados nem vê categorias', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n1', secao: 'busca');
    expect(find.text('Revelar dados pessoais'), findsNothing);
    expect(find.text('Categorias'), findsNothing);
    expect(find.text('Usuários'), findsOneWidget);
    expect(find.text('Suporte'), findsOneWidget);
  });

  testWidgets('aba de pedidos e de suporte', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n1', secao: 'busca');
    await tester.tap(find.text('Pedidos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PED-1042'), findsOneWidget);
    await tester.tap(find.text('Suporte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CH-31'), findsOneWidget);
  });

  testWidgets('moderador desativa categoria com motivo', (tester) async {
    await abrirPainel(tester, papel: 'moderador', secao: 'busca');
    await tester.tap(find.text('Categorias'));
    await tester.pumpAndSettle();
    expect(find.text('Elétrica'), findsOneWidget);
    await tester.tap(find.text('Desativar').first);
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Desativar');
    expect(find.text('Inativa'), findsNWidgets(2));
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
