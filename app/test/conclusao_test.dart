import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/conclusao/apoio_conclusao.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/dados_exemplo.dart';
import 'package:trato/telas/conclusao/garantia_tela.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 1800),
  double fonte = 1.0,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fonte)),
        child: EscalaFonteLimitada(child: filho!),
      ),
      home: tela,
    ),
  );
}

void main() {
  test('formatarReais e formatarData', () {
    expect(formatarReais(42500), 'R\$ 425,00');
    expect(formatarReais(5), 'R\$ 0,05');
    expect(formatarReais(123456789), 'R\$ 1.234.567,89');
    expect(formatarData(DateTime(2026, 1, 5)), '05/01/2026');
  });

  test('total retido soma orçamento e aditivo (só exibição)', () {
    expect(resumoConclusaoExemplo.totalRetidoCentavos, 42500);
  });

  testWidgets('Conclusão mostra total, código e dispara os botões', (tester) async {
    var confirmou = false;
    var relatou = false;
    await _abrir(
      tester,
      ConclusaoTela(aoConfirmar: () => confirmou = true, aoRelatarProblema: () => relatou = true),
    );
    expect(find.text('R\$ 425,00'), findsOneWidget);
    for (final d in '7305'.split('')) {
      expect(find.text(d), findsOneWidget);
    }
    expect(find.textContaining('Confirmação automática em 48 horas'), findsOneWidget);
    await tester.tap(find.text('Confirmar serviço'));
    await tester.tap(find.text('Relatar problema'));
    expect(confirmou && relatou, isTrue);
  });

  testWidgets('Conclusão usa o texto de prazo recebido, não um fixo', (tester) async {
    const resumo = ResumoConclusao(
      numeroPedido: '#1',
      nomeProfissional: 'Ana',
      legendaFotoAntes: 'a',
      legendaFotoDepois: 'b',
      orcamentoCentavos: 100,
      aditivoCentavos: 0,
      codigo: '1234',
      avisoLiberacao: 'Liberação em 7 dias.',
    );
    await _abrir(tester, const ConclusaoTela(resumo: resumo));
    expect(find.text('Liberação em 7 dias.'), findsOneWidget);
    expect(find.textContaining('48 horas'), findsNothing);
  });

  group('Avaliação', () {
    testWidgets('estrelas: tocar marca a nota e troca a nota', (tester) async {
      EnvioAvaliacao? envio;
      await _abrir(tester, AvaliacaoTela(aoEnviar: (e) => envio = e));
      await tester.tap(find.byKey(const Key('estrela_Limpeza_3')));
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      expect(envio!.notas, [0, 0, 3, 0, 0]);
      await tester.tap(find.byKey(const Key('estrela_Limpeza_5')));
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      expect(envio!.notas[2], 5);
    });

    testWidgets('notas iniciais aparecem com estrelas cheias', (tester) async {
      await _abrir(tester, const AvaliacaoTela(notasIniciais: [5, 5, 4, 5, 0]));
      expect(find.byIcon(Icons.star), findsNWidgets(19));
      expect(find.byIcon(Icons.star_border), findsNWidgets(6));
    });

    testWidgets('gorjeta: Não por padrão, R\$ 20, Outro com valor digitado', (tester) async {
      EnvioAvaliacao? envio;
      await _abrir(tester, AvaliacaoTela(aoEnviar: (e) => envio = e));
      expect(find.text('Vai inteira para o profissional, sem taxa.'), findsOneWidget);
      await tester.tap(find.text('Enviar avaliação'));
      expect(envio!.gorjetaCentavos, 0);

      await tester.tap(find.text('R\$ 20'));
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      expect(envio!.gorjetaCentavos, 2000);

      await tester.tap(find.text('Outro'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '35');
      await tester.tap(find.text('Enviar avaliação'));
      expect(envio!.gorjetaCentavos, 3500);

      await tester.tap(find.text('Não'));
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      expect(envio!.gorjetaCentavos, 0);
    });
  });

  group('Relatar problema', () {
    testWidgets('seleção única de motivo e envio só com descrição', (tester) async {
      EnvioRelato? envio;
      await _abrir(
        tester,
        RelatarProblemaTela(aoEnviar: (e) => envio = e),
        tamanho: const Size(390, 2400),
      );
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);

      // Botão desabilitado sem motivo e descrição.
      await tester.tap(find.text('Enviar relato'));
      expect(envio, isNull);

      await tester.tap(find.text('Dano no local'));
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.tap(find.text('Qualidade abaixo do combinado'));
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(4));

      await tester.enterText(find.byType(TextField), 'Ficou torto');
      await tester.pump();
      await tester.tap(find.text('Enviar relato'));
      expect(envio!.motivo, 'Qualidade abaixo do combinado');
      expect(envio!.descricao, 'Ficou torto');
      expect(envio!.solucao, 'Retrabalho sem custo');
    });

    testWidgets('mostra valor congelado e prazo recebidos', (tester) async {
      await _abrir(tester, const RelatarProblemaTela(), tamanho: const Size(390, 2400));
      expect(find.textContaining('R\$ 220,00'), findsOneWidget);
      expect(find.textContaining('48 horas para responder'), findsOneWidget);
    });
  });

  group('Garantia', () {
    testWidgets('mostra dias, data e prazo de atendimento recebidos', (tester) async {
      var pediu = false;
      await _abrir(
        tester,
        GarantiaTela(dados: dadosGarantiaExemplo, aoPedirRetrabalho: () => pediu = true),
      );
      expect(find.text('64 dias'), findsOneWidget);
      expect(find.text('até 31/12/2026'), findsOneWidget);
      expect(find.textContaining('7 dias para atender'), findsOneWidget);
      await tester.tap(find.text('Pedir retrabalho'));
      expect(pediu, isTrue);
    });

    testWidgets('garantia encerrada desabilita o pedido de retrabalho', (tester) async {
      var pediu = false;
      final dados = DadosGarantia(
        titulo: 't',
        diasTotal: 30,
        diasRestantes: 0,
        fimEm: DateTime(2026, 1, 1),
        cobre: 'c',
        naoCobre: 'n',
        prazoAtendimentoDias: 7,
      );
      await _abrir(tester, GarantiaTela(dados: dados, aoPedirRetrabalho: () => pediu = true));
      expect(find.text('Garantia encerrada'), findsOneWidget);
      await tester.tap(find.text('Pedir retrabalho'));
      expect(pediu, isFalse);
    });
  });

  // Sem estouro de layout em 320/390/768, fonte 1,0 e 1,3 (estouro vira exceção no teste).
  const tamanhos = {
    'pequeno 320x568': Size(320, 568),
    'protótipo 390x844': Size(390, 844),
    'tablet 768x1024': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'conclusão': const ConclusaoTela(),
    'avaliação': const AvaliacaoTela(notasIniciais: [5, 5, 4, 5, 0]),
    'relatar problema': const RelatarProblemaTela(motivoInicial: 'Dano no local'),
    'garantia': GarantiaTela(dados: dadosGarantiaExemplo),
  };
  for (final MapEntry(key: nomeTela, value: tela) in telas.entries) {
    for (final MapEntry(key: nomeTam, value: tam) in tamanhos.entries) {
      for (final fonte in [1.0, 1.3]) {
        testWidgets('sem estouro — $nomeTela, $nomeTam, fonte x$fonte', (tester) async {
          await _abrir(tester, tela, tamanho: tam, fonte: fonte);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
