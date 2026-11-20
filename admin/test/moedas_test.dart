import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

void main() {
  group('Menu', () {
    testWidgets('quem gerencia cupons vê Tratinhos', (tester) async {
      await abrirPainel(tester, papel: 'financeiro');
      expect(find.byKey(const ValueKey('menu-moedas')), findsOneWidget);
    });

    testWidgets('quem não gerencia cupons não vê Tratinhos', (tester) async {
      await abrirPainel(tester, papel: 'cadastro');
      expect(find.byKey(const ValueKey('menu-moedas')), findsNothing);
    });
  });

  group('Tela Moedas', () {
    testWidgets('mostra o uso do orçamento em reais e em porcentagem', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      expect(find.text('R\$ 42.000,00 de R\$ 50.000,00'), findsOneWidget);
      expect(find.text('84%'), findsOneWidget);
      expect(find.text('Desconto fechado'), findsNothing);
      expect(find.text('Perto do limite'), findsOneWidget);
    });

    testWidgets('mostra o selo "Desconto fechado" quando o orçamento acabou', (tester) async {
      await abrirPainel(tester, api: ApiFake(moedasUsadoCentavos: 5000000), secao: 'moedas');
      expect(find.text('Desconto fechado'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('mostra a barra "Hoje" abaixo da barra do mês', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      expect(find.text('Hoje (20/11/2026): R\$ 1.000,00 de R\$ 2.000,00'), findsOneWidget);
      expect(find.byKey(const ValueKey('moedas-barra-hoje')), findsOneWidget);
      expect(find.text('Limite de hoje atingido'), findsNothing);
      final mes = tester.getTopLeft(find.byKey(const ValueKey('moedas-barra'))).dy;
      final hoje = tester.getTopLeft(find.byKey(const ValueKey('moedas-barra-hoje'))).dy;
      expect(hoje, greaterThan(mes));
    });

    testWidgets('selo "Limite de hoje atingido" quando o dia chegou ao teto', (tester) async {
      await abrirPainel(tester, api: ApiFake(moedasUsadoDiaCentavos: 200000), secao: 'moedas');
      expect(find.text('Limite de hoje atingido'), findsOneWidget);
      expect(find.text('O desconto com Tratinhos volta amanhã.'), findsOneWidget);
      // O mês não está fechado: os dois selos são independentes.
      expect(find.text('Desconto fechado'), findsNothing);
    });

    testWidgets('formulário mostra os 2 campos novos', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      final dia = find.byKey(const ValueKey('moedas-campo-teto_diario_desconto_centavos'));
      expect(tester.widget<TextField>(dia).controller!.text, '2000,00');
      final dias = find.byKey(const ValueKey('moedas-campo-dias_liberacao_bonus'));
      expect(tester.widget<TextField>(dias).controller!.text, '7');
    });

    testWidgets('textos visíveis usam o nome Tratinhos', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      expect(find.text('Tratinhos'), findsWidgets);
      expect(find.text('Programa de Tratinhos ativo'), findsOneWidget);
      expect(find.text('Valor de cada Tratinho'), findsOneWidget);
      expect(find.textContaining('moeda'), findsNothing);
    });

    testWidgets('formulário mostra dinheiro em reais', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      final valorMoeda = find.byKey(const ValueKey('moedas-campo-valor_moeda_centavos'));
      expect(tester.widget<TextField>(valorMoeda).controller!.text, '0,10');
      final orcamento = find.byKey(const ValueKey('moedas-campo-orcamento_mensal_desconto_centavos'));
      expect(tester.widget<TextField>(orcamento).controller!.text, '50000,00');
    });

    testWidgets('salva exigindo motivo e envia centavos inteiros', (tester) async {
      final api = ApiFake();
      await abrirPainel(tester, api: api, secao: 'moedas');

      await tester.enterText(find.byKey(const ValueKey('moedas-campo-valor_moeda_centavos')), '0,25');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-orcamento_mensal_desconto_centavos')), '60000,00');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-validade_dias')), '120');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-teto_diario_desconto_centavos')), '3000,50');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-dias_liberacao_bonus')), '14');
      await tester.pump();

      final salvar = find.widgetWithText(FilledButton, 'Salvar configuração');
      await tester.ensureVisible(salvar);
      await tester.tap(salvar);
      await tester.pumpAndSettle();

      // Sem motivo o botão do modal fica desligado.
      final confirmar = find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(FilledButton, 'Salvar configuração'));
      expect(tester.widget<FilledButton>(confirmar).onPressed, isNull);

      await confirmarMotivo(tester, 'Salvar configuração', motivo: 'Ajuste do orçamento de novembro');

      final c = api.moedasConfigAtual;
      expect(c.valorMoedaCentavos, 25);
      expect(c.orcamentoMensalDescontoCentavos, 6000000);
      expect(c.validadeDias, 120);
      expect(c.tetoDiarioDescontoCentavos, 300050);
      expect(c.diasLiberacaoBonus, 14);
      expect(c.ativo, isTrue);
      expect(find.text('Configuração dos Tratinhos salva.'), findsOneWidget);
      // A tela recarrega: o orçamento agora é R$ 60.000,00.
      expect(find.text('R\$ 42.000,00 de R\$ 60.000,00'), findsOneWidget);
    });

    testWidgets('valor inválido bloqueia o salvamento', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-teto_mensal_moedas')), '12abc');
      await tester.pump();
      expect(find.text('Informe um número inteiro'), findsOneWidget);
      final salvar = find.widgetWithText(FilledButton, 'Salvar configuração');
      expect(tester.widget<FilledButton>(salvar).onPressed, isNull);
    });

    testWidgets('erro de carga mostra "tentar de novo"', (tester) async {
      await abrirPainel(tester, api: ApiFake(erro: true), secao: 'moedas');
      expect(find.text('Tentar de novo'), findsWidgets);
    });

    testWidgets('orçamento ainda não definido mostra estado vazio', (tester) async {
      await abrirPainel(tester, api: ApiFake(vazio: true), secao: 'moedas');
      expect(find.text('Orçamento do mês ainda não definido'), findsOneWidget);
    });

    testWidgets('no celular não estoura o layout', (tester) async {
      await abrirPainel(tester, largura: 390, altura: 800, api: ApiFake(moedasUsadoCentavos: 5000000));
      await tester.tap(find.byKey(const ValueKey('menu-mais')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-moedas')));
      await tester.pumpAndSettle();
      expect(find.text('Desconto fechado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Alerta no painel', () {
    testWidgets('aparece quando o uso chegou ao percentual de aviso', (tester) async {
      await abrirPainel(tester, secao: 'dashboard');
      expect(find.byKey(const ValueKey('alerta-moedas')), findsOneWidget);
      expect(find.text('Orçamento de Tratinhos quase no fim'), findsOneWidget);
      expect(find.textContaining('R\$ 42.000,00 de R\$ 50.000,00 (84%)'), findsOneWidget);
    });

    testWidgets('não aparece abaixo do aviso', (tester) async {
      await abrirPainel(tester, api: ApiFake(moedasUsadoCentavos: 1000000), secao: 'dashboard');
      expect(find.byKey(const ValueKey('alerta-moedas')), findsNothing);
    });

    testWidgets('"Ver Tratinhos" abre a tela', (tester) async {
      await abrirPainel(tester, secao: 'dashboard');
      await tester.tap(find.text('Ver Tratinhos'));
      await tester.pumpAndSettle();
      expect(find.text('Configuração do programa'), findsOneWidget);
    });

    testWidgets('se a consulta falhar, o painel segue sem o alerta', (tester) async {
      await abrirPainel(tester, api: ApiFake(erro: true), secao: 'dashboard');
      expect(find.byKey(const ValueKey('alerta-moedas')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
