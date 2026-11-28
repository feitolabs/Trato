import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Trava de saques: a tela não promete reter dinheiro e mostra a mensagem do backend.
Finder _noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));

Future<void> _escrever(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pump();
}

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

final _promessa = find.textContaining(RegExp('retid|reter|reteve|repasses liberados', caseSensitive: false),
    findRichText: true);

Future<ApiFake> _abrirNaTrava(WidgetTester tester, {String? mensagem}) async {
  final api = ApiFake()..mensagemRisco = mensagem;
  await abrirPainel(tester, papel: 'administrador', api: api, secao: 'risco');
  await tester.tap(find.textContaining(RegExp(r'^Todos \d+$')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Troca de chave PIX').first);
  await tester.pumpAndSettle();
  await rolarListaAte(tester, find.text('Registrar trava'));
  await _clicar(tester, find.text('Registrar trava'));
  return api;
}

Future<void> _confirmarTrava(WidgetTester tester) async {
  await _escrever(tester, 'Motivo interno (o usuário não vê)', 'Chave trocada duas vezes');
  await _escrever(tester, 'Motivo que o usuário vai ler', 'Atividade fora do padrão na conta');
  await _escrever(tester, 'Cláusulas dos Termos', '20.3');
  await _clicar(tester, _noModal('Registrar trava'));
}

void main() {
  testWidgets('registrar e remover a trava: textos sem promessa e aviso com a mensagem do backend', (tester) async {
    const daTrava = 'A conta está restrita e a trava foi registrada (mensagem de exemplo).';
    final api = await _abrirNaTrava(tester, mensagem: daTrava);
    expect(find.textContaining('não bloqueia a liberação', findRichText: true), findsOneWidget);
    expect(_promessa, findsNothing);
    await _confirmarTrava(tester);
    expect(api.acoesDeConta.single.acao, 'travarSaque');
    expect(find.text(daTrava), findsOneWidget);

    const daRemocao = 'Conta reativada, sem trava (mensagem de exemplo).';
    api.mensagemRisco = daRemocao;
    // O banner fica no topo do detalhe; o botão, no fim.
    final banner = find.textContaining('Conta restrita.', findRichText: true);
    final lista = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(banner, -300, scrollable: lista);
    expect(banner, findsOneWidget);
    await rolarListaAte(tester, find.text('Remover trava'));
    expect(_promessa, findsNothing);
    await _clicar(tester, find.text('Remover trava'));
    expect(_promessa, findsNothing);
    await _escrever(tester, 'Motivo', 'Trava aplicada por engano');
    await _clicar(tester, _noModal('Remover trava'));
    expect(find.text(daRemocao), findsOneWidget);
  });

  testWidgets('sem mensagem do backend, o aviso pede conferência à mão', (tester) async {
    await _abrirNaTrava(tester);
    await _confirmarTrava(tester);
    expect(find.text('Trava de saques enviada. Confira a medida em Medidas.'), findsOneWidget);
  });

  test('auditoria descreve a trava sem dizer que reteve ou liberou dinheiro', () {
    String frase(String acao) => descreverAcao(EntradaAuditoria(
          id: 1,
          ocorridaEm: DateTime(2026, 11, 26),
          ator: 'sistema',
          acao: acao,
          entidade: 'usuarios',
          entidadeNome: 'Carla M.',
          motivo: 'exemplo',
        ));
    expect(frase('risco.saque_travado'), 'registrou trava de saques na conta de Carla M.');
    expect(frase('risco.saque_destravado'), 'removeu a trava de saques da conta de Carla M.');
  });
}
