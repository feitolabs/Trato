import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/servico_orcamento.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/carteira/dados_exemplo.dart';
import 'apoio/orcamento.dart';

class _ServicoOrcamentoMemoria implements ServicoOrcamento {
  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async =>
      ResumoOrcamento(totalCentavos: totalCentavos);

  @override
  Future<void> enviar(OrcamentoPronto pronto) async {}
}

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: tela,
    ),
  );
}

void main() {
  group('F5 — Calculadora modo Valor fechado / diária', () {
    testWidgets('alterna para valor fechado, oculta horas e envia OrcamentoPronto', (tester) async {
      OrcamentoPronto? enviado;
      await _abrir(
        tester,
        CalculadoraOrcamentoTela(
          servico: _ServicoOrcamentoMemoria(),
          tituloPedido: 'Instalar chuveiro',
          garantiaInicialDias: 90,
          prazoExecucaoInicialDias: 3,
          itensIniciais: const [ItemMaterial(nome: 'Disjuntor', centavos: 5000)],
          aoEnviar: (p) => enviado = p,
        ),
      );

      expect(find.text('Valor fechado / diária'), findsOneWidget);
      expect(find.text('Por hora + deslocamento'), findsOneWidget);
      expect(find.text('Horas de deslocamento'), findsOneWidget);

      await tester.tap(find.text('Valor fechado / diária'));
      await tester.pumpAndSettle();

      expect(find.text('Horas de deslocamento'), findsNothing);
      expect(find.text('Horas trabalhadas'), findsNothing);
      expect(find.text('Valor da hora'), findsNothing);
      expect(find.text('Valor do serviço (ou diária)'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        '250,00',
      );
      await tester.pumpAndSettle();

      await completarOrcamento(tester);
      await tester.tap(find.text('Enviar orçamento'));
      await tester.pumpAndSettle();

      expect(enviado, isNotNull);
      expect(enviado!.decimosDeslocamento, 0);
      expect(enviado!.decimosDeHora, 0);
      expect(enviado!.valorHoraCentavos, 0);
      expect(enviado!.valorFechadoCentavos, 25000);
      expect(enviado!.totalCentavos, 30000);
    });

    testWidgets('valida valor do serviço vazio no modo fechado', (tester) async {
      OrcamentoPronto? enviado;
      await _abrir(
        tester,
        CalculadoraOrcamentoTela(
          servico: _ServicoOrcamentoMemoria(),
          tituloPedido: 'Instalar chuveiro',
          modoInicial: ModoOrcamento.valorFechado,
          aoEnviar: (p) => enviado = p,
        ),
      );

      await tester.tap(find.text('Enviar orçamento'));
      await tester.pumpAndSettle();

      expect(enviado, isNull);
      expect(
        find.text('Informe o valor do serviço ou da diária (ex.: 250,00).'),
        findsOneWidget,
      );
    });
  });

  group('F5 — Carteira com repasse automático', () {
    testWidgets('padrão não exibe saque manual e explica repasse automático', (tester) async {
      await _abrir(tester, const CarteiraTela(dados: DadosExemploCarteira.completo));

      expect(find.text('Disponível para saque'), findsNothing);
      expect(find.text('Sacar via Pix'), findsNothing);
      expect(
        find.text(
          'Repasse automático: após a liberação, o valor cai automaticamente na sua conta cadastrada.',
        ),
        findsOneWidget,
      );
    });
  });
}
