import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/app.dart';
import 'package:trato_admin/telas/verificacao_tela.dart';
import 'apoio/api_fake.dart';

import 'ajuda.dart';

/// PNG 1x1 transparente: nos testes não há rede, então o "link" vira esta imagem.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  setUp(() => imagemDoLink = (_) => MemoryImage(_png));
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
    // o documento abre num modal no próprio painel, sem nova aba
    expect(find.byType(VisualizadorDocumento), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(VisualizadorDocumento), findsNothing);
    expect(find.textContaining('Liberado até'), findsOneWidget);
    expect(find.text('Ver de novo'), findsOneWidget);
  });

  testWidgets('ver de novo em até 10 minutos não pede motivo; depois pede', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    await tester.tap(find.text('Carlos Pereira').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revelar').first);
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Revelar');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Fechar'));
    await tester.pumpAndSettle();

    // dentro do prazo: abre direto, sem o campo Motivo
    await tester.tap(find.text('Ver de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(VisualizadorDocumento), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Motivo'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Fechar'));
    await tester.pumpAndSettle();

    // passou o prazo: volta a pedir motivo
    await tester.pump(kDocumentoLiberadoPor + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Aberto nesta sessão'), findsOneWidget);
    await tester.tap(find.text('Ver de novo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Motivo'), findsOneWidget);
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
