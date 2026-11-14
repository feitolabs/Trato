import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/conta/dados_pessoais_tela.dart';
import 'package:trato/telas/conta/enderecos_tela.dart';
import 'package:trato/telas/conta/favoritos_contatos_telas.dart';
import 'package:trato/telas/conta/modelos.dart';
import 'package:trato/telas/conta/servico_fake.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  test('formata telefone e CEP', () {
    expect(formatarTelefone('11988887777'), '(11) 98888-7777');
    expect(formatarTelefone('1133334444'), '(11) 3333-4444');
    expect(formatarCep('01310100'), '01310-100');
  });

  testWidgets('dados pessoais: mostra CPF mascarado e salva o telefone', (tester) async {
    final servico = ServicoContaFake();
    await _abrir(tester, DadosPessoaisTela(servico: servico));
    expect(find.text('Mariana Alves'), findsOneWidget);
    expect(find.text('•••.•••.•••-09'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '11988887777');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Dados salvos.'), findsOneWidget);
    expect((await servico.dados()).telefone, '11988887777');
  });

  testWidgets('dados pessoais: conta sem CPF pede o CPF e grava junto com o telefone', (tester) async {
    final servico = ServicoContaFake(
      dados: const DadosPessoaisConta(nome: 'Gabriel', email: 'g@exemplo.com'),
    );
    await _abrir(tester, DadosPessoaisTela(servico: servico));
    expect(find.text('CPF'), findsOneWidget);
    // CPF inválido não grava nada
    await tester.enterText(find.byType(TextField).first, '11111111111');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect((await servico.dados()).cpfFinal, isNull);
    // CPF válido + telefone
    await tester.enterText(find.byType(TextField).first, '52998224725');
    await tester.enterText(find.byType(TextField).at(1), '37988199991');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Dados salvos.'), findsOneWidget);
    final d = await servico.dados();
    expect(d.cpfFinal, '25');
    expect(d.telefone, '37988199991');
  });

  testWidgets('dados pessoais: telefone curto mostra erro e não salva', (tester) async {
    final servico = ServicoContaFake();
    await _abrir(tester, DadosPessoaisTela(servico: servico));
    await tester.enterText(find.byType(TextField).first, '123');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o telefone com DDD.'), findsOneWidget);
    expect((await servico.dados()).telefone, isNull);
  });

  testWidgets('endereços: vazio, adiciona e aparece como principal', (tester) async {
    final servico = ServicoContaFake();
    await _abrir(tester, EnderecosTela(servico: servico));
    expect(find.text('Nenhum endereço salvo'), findsOneWidget);
    await tester.tap(find.text('Adicionar endereço'));
    await tester.pumpAndSettle();
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), 'Casa');
    await tester.enterText(campos.at(1), '01310-100');
    await tester.enterText(campos.at(2), 'Av. Paulista');
    await tester.enterText(campos.at(3), '1000');
    await tester.enterText(campos.at(5), 'Bela Vista');
    await tester.enterText(campos.at(6), 'São Paulo');
    await tester.enterText(campos.at(7), 'sp');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('Principal'), findsOneWidget);
    expect((await servico.enderecos()).single.uf, 'SP');
  });

  testWidgets('endereços: campo faltando não envia', (tester) async {
    final servico = ServicoContaFake();
    await _abrir(tester, EnderecosTela(servico: servico));
    await tester.tap(find.text('Adicionar endereço'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Preencha apelido'), findsOneWidget);
    expect(await servico.enderecos(), isEmpty);
  });

  testWidgets('favoritos: lista e tira da lista', (tester) async {
    final servico = ServicoContaFake(
      favoritos: [const FavoritoConta(profissionalId: 'p1', nome: 'Carlos Pintor', nota: 4.8, servicos: 12)],
    );
    await _abrir(tester, FavoritosTela(servico: servico));
    expect(find.text('Carlos Pintor'), findsOneWidget);
    expect(find.text('Nota 4,8 · 12 serviços'), findsOneWidget);
    await tester.tap(find.byTooltip('Tirar dos favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum favorito ainda'), findsOneWidget);
  });

  testWidgets('contatos: adiciona e remove com confirmação', (tester) async {
    final servico = ServicoContaFake();
    await _abrir(tester, ContatosConfiancaTela(servico: servico));
    await tester.tap(find.text('Adicionar contato'));
    await tester.pumpAndSettle();
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), 'Maria');
    await tester.enterText(campos.at(1), '11977776666');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Maria'), findsOneWidget);
    expect(find.text('(11) 97777-6666'), findsOneWidget);
    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover').last);
    await tester.pumpAndSettle();
    expect(await servico.contatos(), isEmpty);
  });

  testWidgets('falha de rede mostra erro com "Tentar de novo"', (tester) async {
    await _abrir(tester, EnderecosTela(servico: ServicoContaFake(falhar: true)));
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
