import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart' show TipoStatus;
import 'package:trato/dados/carregador.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/busca/servico_fake.dart';
import 'apoio/exemplos/telas/orcamentos/dados_exemplo.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  final carlos = orcamentosExemplo.firstWhere((o) => o.id == 'carlos');

  group('Orçamento de pedido que já tem aceito: só leitura', () {
    for (final (nome, tela) in <(String, bool)>[('somenteLeitura', true), ('contrato', false)]) {
      testWidgets('$nome: sem aceitar, contraproposta, recusar nem a caixa de leitura',
          (tester) async {
        await _abrir(
          tester,
          DetalheOrcamentoTela(
            orcamento: carlos,
            somenteLeitura: tela,
            contrato: !tela,
            aoAceitar: (_) {},
            aoRecusar: (_) {},
            aoFazerContraproposta: (_) {},
          ),
        );
        expect(find.textContaining('Aceitar e ir para o pagamento'), findsNothing);
        expect(find.text('Fazer contraproposta'), findsNothing);
        expect(find.text('Recusar orçamento'), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        if (tela) expect(find.byKey(const ValueKey('aviso-somente-leitura')), findsOneWidget);
      });
    }

    testWidgets('sem a trava os 3 botões continuam aparecendo', (tester) async {
      await _abrir(
        tester,
        DetalheOrcamentoTela(
          orcamento: carlos,
          aoAceitar: (_) {},
          aoRecusar: (_) {},
          aoFazerContraproposta: (_) {},
        ),
      );
      expect(find.textContaining('Aceitar e ir para o pagamento'), findsOneWidget);
      expect(find.text('Fazer contraproposta'), findsOneWidget);
      expect(find.text('Recusar orçamento'), findsOneWidget);
    });
  });

  group('Estados vazios com ação clara', () {
    testWidgets('Seus pedidos: busca sem resultado e sem filtro oferece "Limpar busca"',
        (tester) async {
      await _abrir(
        tester,
        const SeusPedidosTela(
          emAndamento: [
            PedidoResumo(
              titulo: 'Pintura',
              subtitulo: 'Pedido #1',
              statusTexto: 'Agendado',
              statusTipo: TipoStatus.info,
            ),
          ],
          finalizados: [],
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'zzzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nenhum pedido encontrado'), findsOneWidget);

      await tester.tap(find.text('Limpar busca'));
      await tester.pumpAndSettle();
      expect(find.text('Pintura'), findsOneWidget);
      expect(find.text('Nenhum pedido encontrado'), findsNothing);
    });

    testWidgets('Busca de profissionais: "Nada encontrado" oferece "Limpar busca"', (tester) async {
      await _abrir(
        tester,
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(), termoInicial: 'zzzz'),
      );
      expect(find.text('Nada encontrado'), findsOneWidget);
      await tester.tap(find.text('Limpar busca'));
      await tester.pumpAndSettle();
      expect(find.text('Nada encontrado'), findsNothing);
    });

    testWidgets('Ainda sem orçamentos: "Atualizar" recarrega', (tester) async {
      var cargas = 0;
      await _abrir(
        tester,
        Carregador<List<int>>(
          carregar: () async {
            cargas++;
            return const <int>[];
          },
          vazio: (l) => l.isEmpty,
          tituloVazio: 'Ainda sem orçamentos',
          textoVazio: 'Avisamos quando os profissionais responderem.',
          textoAcaoVazio: 'Atualizar',
          construir: (_, __) => const SizedBox(),
        ),
      );
      expect(find.text('Ainda sem orçamentos'), findsOneWidget);
      expect(cargas, 1);
      await tester.tap(find.text('Atualizar'));
      await tester.pumpAndSettle();
      expect(cargas, 2);
    });
  });
}
