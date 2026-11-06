import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/app.dart';
import 'apoio/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('lista a fila e mostra o detalhe com CPF e arquivos mascarados', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    await tester.tap(find.text('Carlos Pereira').first);
    await tester.pumpAndSettle();
    expect(find.text('Carlos Pereira'), findsWidgets);
    expect(find.text('***.***.***-45'), findsOneWidget);
    expect(find.text('Escondido'), findsNWidgets(3));
    // nível de verificação e categorias de serviço são coisas separadas
    expect(find.text('Nível de verificação'), findsOneWidget);
    expect(find.text('Categorias de serviço solicitadas'), findsOneWidget);
    expect(find.text('Eletricista'), findsWidgets);
    expect(find.text('Envios anteriores'), findsOneWidget);
    expect(find.textContaining('Recusado: Selfie não confere'), findsOneWidget);
  });

  testWidgets('fila ordenada pelo envio mais antigo e com contadores por status', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    expect(find.text('Pendentes 2'), findsOneWidget);
    expect(find.text('Aprovada 1'), findsOneWidget);
    final nomes = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
    expect(nomes.indexOf('Ana Ribeiro') < nomes.indexOf('Carlos Pereira'), isTrue);
    await tester.tap(find.text('Aprovada 1'));
    await tester.pumpAndSettle();
    expect(find.text('José Roberto Alves'), findsWidgets);
    expect(find.text('Carlos Pereira'), findsNothing);
  });

  testWidgets('revelar documento exige motivo e avisa da auditoria', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    await tester.tap(find.text('Carlos Pereira').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revelar').first);
    await tester.pumpAndSettle();
    expect(find.text('Esta ação fica registrada na auditoria com seu nome e o motivo.'), findsWidgets);
    // com motivo curto o botão fica desabilitado
    await tester.enterText(find.widgetWithText(TextField, 'Motivo'), 'curto');
    await tester.pump();
    final botao = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Revelar'));
    expect(botao.onPressed, isNull);
    await confirmarMotivo(tester, 'Revelar');
    expect(find.text('Aberto nesta sessão'), findsOneWidget);
  });

  testWidgets('recusar usa motivo da lista padronizada e atualiza o status', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Recusar cadastro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Motivo da lista'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selfie não confere com o documento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(OutlinedButton), matching: find.text('Recusar cadastro')).last);
    await tester.pumpAndSettle();
    expect(find.text('Recusada 1'), findsOneWidget);
    expect(find.text('Pendentes 1'), findsOneWidget);
  });

  testWidgets('profissional sem CPF mostra "Não informado" com alerta', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    // a fila começa pelo envio mais antigo: Ana Ribeiro já vem aberta
    expect(find.text('Não informado'), findsOneWidget);
    expect(find.textContaining('Cadastro sem CPF'), findsOneWidget);
  });

  testWidgets('segurança vê a fila mas não aprova nem abre documentos', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    expect(find.text('Carlos Pereira'), findsWidgets);
    expect(find.text('Aprovar profissional'), findsNothing);
    expect(find.text('Revelar'), findsNothing);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', api: ApiFake(vazio: true));
    expect(find.text('Nenhum cadastro esperando análise.'), findsOneWidget);
  });

  testWidgets('estado de erro com tentar de novo', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', api: ApiFake(erro: true));
    expect(find.text('Não foi possível falar com o servidor.'), findsOneWidget);
    expect(find.textContaining('Código ERR-'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('estado carregando', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PainelApp(api: ApiFake(atraso: const Duration(seconds: 1))));
    await entrar(tester, 'cadastro', esperar: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.bySemanticsLabel('Carregando'), findsWidgets);
    // O esqueleto não anima: o tempo precisa avançar à mão até os dados chegarem.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Carlos Pereira'), findsWidgets);
  });
}
