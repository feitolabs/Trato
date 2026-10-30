import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/em_breve_tela.dart';
import 'package:trato/telas/orcamentos/dados_exemplo.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 2400),
  double escala = 1.0,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: tela,
    ),
  );
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

/// Nomes dos profissionais na ordem em que aparecem na lista.
List<String> _ordemNaTela(WidgetTester tester) {
  final nomes = orcamentosExemplo.map((o) => o.profissional).toList();
  final posicoes = {for (final n in nomes) n: tester.getTopLeft(find.text(n)).dy};
  return (posicoes.keys.toList()..sort((a, b) => posicoes[a]!.compareTo(posicoes[b]!)));
}

void main() {
  group('novo pedido', () {
    testWidgets('mostra os textos do protótipo', (tester) async {
      await _abrir(tester, const NovoPedidoTela());

      expect(find.text('Passo 2 de 3'), findsOneWidget);
      expect(find.text('Conte o que precisa'), findsOneWidget);
      expect(find.text('Elétrica · Tomadas e chuveiro'), findsOneWidget);
      expect(find.text('O que precisa ser feito?'), findsOneWidget);
      expect(find.text('Trocar tomada'), findsOneWidget);
      expect(find.text('Quantas tomadas?'), findsOneWidget);
      expect(find.text('Voltagem do chuveiro'), findsOneWidget);
      expect(find.text('[Foto 1]'), findsOneWidget);
      expect(find.text('Adicionar'), findsOneWidget);
      expect(find.text('Até sexta, 30/10'), findsOneWidget);
      expect(find.text('R\$ 200 a R\$ 500'), findsOneWidget);
      expect(
          find.textContaining('até 5 orçamentos em 48 horas', findRichText: true), findsOneWidget);
    });

    testWidgets('contador respeita o mínimo de 1', (tester) async {
      await _abrir(tester, const NovoPedidoTela());

      await tester.tap(find.byTooltip('Diminuir'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('Aumentar'));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('sem serviço escolhido mostra erro e não envia', (tester) async {
      RascunhoPedido? recebido;
      await _abrir(tester, NovoPedidoTela(aoEnviar: (r) => recebido = r));

      await tester.tap(find.text('Trocar tomada'));
      await tester.tap(find.text('Trocar chuveiro'));
      await tester.pump();
      await _tocar(tester, find.text('Próximo'));

      expect(find.text('Escolha pelo menos um serviço.'), findsOneWidget);
      expect(recebido, isNull);
    });

    testWidgets('descrição vazia mostra erro', (tester) async {
      await _abrir(tester, const NovoPedidoTela());

      await tester.enterText(find.byType(TextField), '   ');
      await _tocar(tester, find.text('Próximo'));

      expect(find.text('Conte o que está acontecendo.'), findsOneWidget);
    });

    testWidgets('Próximo devolve o que foi preenchido', (tester) async {
      RascunhoPedido? recebido;
      await _abrir(tester, NovoPedidoTela(aoEnviar: (r) => recebido = r));

      await tester.tap(find.text('127 V'));
      await tester.tap(find.byTooltip('Aumentar'));
      await tester.pump();
      await _tocar(tester, find.text('Próximo'));

      expect(recebido, isNotNull);
      expect(recebido!.servicos, ['Trocar tomada', 'Trocar chuveiro']);
      expect(recebido!.quantidade, 3);
      expect(recebido!.voltagem, '127 V');
      expect(recebido!.faixa.minimoCentavos, 20000);
      expect(recebido!.faixa.maximoCentavos, 50000);
    });

    for (final texto in ['Trocar', 'Mudar', 'Adicionar', 'Próximo']) {
      testWidgets('sem callback, $texto abre "em breve"', (tester) async {
        await _abrir(tester, const NovoPedidoTela());
        await _tocar(tester, find.text(texto));
        expect(find.byType(EmBreveTela), findsOneWidget);
      });
    }
  });

  group('orçamentos recebidos', () {
    testWidgets('mostra o cabeçalho e os 3 orçamentos do protótipo', (tester) async {
      await _abrir(tester, OrcamentosRecebidosTela());

      expect(find.text('Pedido #4821'), findsOneWidget);
      expect(find.text('Orçamentos recebidos'), findsOneWidget);
      expect(find.text('Troca de tomadas e chuveiro'), findsOneWidget);
      expect(find.textContaining('3 de 5', findRichText: true), findsOneWidget);
      expect(find.text('R\$ 340,00'), findsOneWidget);
      expect(find.text('R\$ 380,00'), findsOneWidget);
      expect(find.text('R\$ 455,00'), findsOneWidget);
      expect(find.text('Ver orçamento'), findsNWidgets(3));
    });

    testWidgets('ordenação: menor valor, maior nota e mais cedo', (tester) async {
      await _abrir(tester, OrcamentosRecebidosTela());
      expect(_ordemNaTela(tester), ['Joana Ribeiro', 'Carlos Mendes', 'André Lopes']);

      await tester.tap(find.text('Maior nota'));
      await tester.pumpAndSettle();
      expect(_ordemNaTela(tester), ['Carlos Mendes', 'André Lopes', 'Joana Ribeiro']);

      await tester.tap(find.text('Mais cedo'));
      await tester.pumpAndSettle();
      expect(_ordemNaTela(tester).first, 'Carlos Mendes');

      await tester.tap(find.text('Menor valor'));
      await tester.pumpAndSettle();
      expect(_ordemNaTela(tester).first, 'Joana Ribeiro');
    });

    testWidgets('Ver orçamento do Carlos abre o detalhe', (tester) async {
      await _abrir(tester, OrcamentosRecebidosTela());

      await _tocar(tester, find.text('Ver orçamento').at(1));

      expect(find.byType(DetalheOrcamentoTela), findsOneWidget);
    });

    testWidgets('orçamento sem detalhe abre "em breve"', (tester) async {
      await _abrir(tester, OrcamentosRecebidosTela());

      await _tocar(tester, find.text('Ver orçamento').first);

      expect(find.byType(EmBreveTela), findsOneWidget);
    });

    testWidgets('aoVerOrcamento recebe o orçamento tocado', (tester) async {
      Orcamento? visto;
      await _abrir(tester, OrcamentosRecebidosTela(aoVerOrcamento: (o) => visto = o));

      await _tocar(tester, find.text('Ver orçamento').last);

      expect(visto?.id, 'andre');
    });
  });

  group('detalhe do orçamento', () {
    final carlos = orcamentosExemplo.firstWhere((o) => o.id == 'carlos');

    testWidgets('mostra itens, total e regras do protótipo', (tester) async {
      await _abrir(tester, DetalheOrcamentoTela(orcamento: carlos));

      expect(find.text('Válido até 31/10'), findsOneWidget);
      expect(find.text('Carlos Mendes'), findsOneWidget);
      expect(find.text('O que está incluso'), findsOneWidget);
      expect(find.text('R\$ 30,00'), findsOneWidget);
      expect(find.text('R\$ 240,00'), findsOneWidget);
      expect(find.text('R\$ 380,00'), findsOneWidget);
      expect(find.text('Garantia de 90 dias'), findsOneWidget);
      expect(find.text('Fora do escopo'), findsOneWidget);
      expect(find.text('Cancelamento'), findsOneWidget);
      expect(find.text('Aceitar orçamento · R\$ 380,00'), findsOneWidget);
      expect(find.text('Fazer contraproposta'), findsOneWidget);
    });

    testWidgets('aceitar sem marcar a leitura mostra aviso e não chama o callback', (tester) async {
      Orcamento? aceito;
      await _abrir(tester, DetalheOrcamentoTela(orcamento: carlos, aoAceitar: (o) => aceito = o));

      await _tocar(tester, find.textContaining('Aceitar orçamento'));

      expect(find.text('Marque que leu para aceitar o orçamento.'), findsOneWidget);
      expect(aceito, isNull);
    });

    testWidgets('com a leitura marcada, aceitar chama o callback', (tester) async {
      Orcamento? aceito;
      await _abrir(tester, DetalheOrcamentoTela(orcamento: carlos, aoAceitar: (o) => aceito = o));

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await _tocar(tester, find.textContaining('Aceitar orçamento'));

      expect(aceito?.id, 'carlos');
    });

    testWidgets('contraproposta e conversar chamam seus callbacks', (tester) async {
      var contra = 0;
      var conversar = 0;
      await _abrir(
        tester,
        DetalheOrcamentoTela(
          orcamento: carlos,
          aoFazerContraproposta: (_) => contra++,
          aoConversar: (_) => conversar++,
        ),
      );

      await _tocar(tester, find.text('Fazer contraproposta'));
      await _tocar(tester, find.text('Conversar'));

      expect(contra, 1);
      expect(conversar, 1);
    });

    testWidgets('sem callbacks, aceitar e contraproposta abrem "em breve"', (tester) async {
      await _abrir(tester, DetalheOrcamentoTela(orcamento: carlos));
      await _tocar(tester, find.text('Fazer contraproposta'));
      expect(find.byType(EmBreveTela), findsOneWidget);
    });
  });

  // Qualquer estouro de layout faz o teste falhar.
  final telas = <String, Widget Function()>{
    'novo pedido': () => const NovoPedidoTela(),
    'orçamentos': () => OrcamentosRecebidosTela(),
    'detalhe': () => DetalheOrcamentoTela(orcamento: orcamentosExemplo[1]),
  };
  const tamanhos = [Size(320, 568), Size(390, 844), Size(768, 1024)];
  for (final MapEntry(key: nome, value: criar) in telas.entries) {
    for (final tamanho in tamanhos) {
      for (final escala in [1.0, Responsivo.escalaFonteMaxima]) {
        testWidgets('sem estouro — $nome ${tamanho.width.toInt()} fonte x$escala', (tester) async {
          await _abrir(tester, criar(), tamanho: tamanho, escala: escala);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.fling(
              find.byType(SingleChildScrollView).first, const Offset(0, -4000), 3000);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
