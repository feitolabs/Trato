import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/tema/tema.dart';

Widget _envolver(Widget child, {ThemeData? tema}) =>
    MaterialApp(theme: tema ?? TemaTrato.claro, home: child);

void main() {
  group('F59 — Avaliação já feita e ressalva F55', () {
    testWidgets('jaAvaliou: true mostra confirmação e oculta formulário e Enviar avaliação',
        (tester) async {
      var voltou = false;
      await tester.pumpWidget(
        _envolver(
          AvaliacaoTela(
            dados: const DadosAvaliacao(
              nomeProfissional: 'Carlos Silva',
              valorLiberadoCentavos: 18000,
              criterios: ['Pontualidade', 'Qualidade'],
              gorjetasCentavos: [1000],
              jaAvaliou: true,
            ),
            aoAvaliarDepois: () => voltou = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Você já avaliou este serviço'), findsOneWidget);
      expect(find.text('Enviar avaliação'), findsNothing);
      expect(find.text('Pontualidade'), findsNothing);

      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(voltou, isTrue);
    });

    testWidgets('bonusDisponivel com valorMoedaCentavos null não mostra R\$ 0,50 hardcoded',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          const AvaliacaoTela(
            dados: DadosAvaliacao(
              nomeProfissional: 'Carlos Silva',
              valorLiberadoCentavos: 18000,
              criterios: ['Pontualidade'],
              gorjetasCentavos: [],
              gorjetaDisponivel: false,
              bonusDisponivel: true,
              bonusMoedas: 50,
              valorMoedaCentavos: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('legenda-bonus-tratinhos')), findsOneWidget);
      expect(find.textContaining('+50 Tratinhos'), findsOneWidget);
      expect(find.textContaining('R\$ 0,50'), findsNothing);
    });
  });

  group('F59 — Filtros inteligentes em SeusPedidosTela', () {
    final hoje = DateTime(2026, 11, 22, 14, 0);
    final pedidosEmAndamento = [
      PedidoResumo(
        id: 'p1',
        titulo: 'Troca de chuveiro',
        subtitulo: 'Pedido #01',
        statusTexto: 'Em execução',
        statusTipo: TipoStatus.info,
        categoria: 'Elétrica',
        abertoEm: DateTime(2026, 11, 22, 10, 0),
        urgente: true,
      ),
      PedidoResumo(
        id: 'p2',
        titulo: 'Pintura de sala',
        subtitulo: 'Pedido #02',
        statusTexto: 'Agendado',
        statusTipo: TipoStatus.sucesso,
        categoria: 'Pintura',
        abertoEm: DateTime(2026, 11, 10, 9, 0),
      ),
    ];

    testWidgets('exibe apenas categorias presentes, filtra por categoria/período/ordenação e limpa',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _envolver(
          SeusPedidosTela(
            emAndamento: pedidosEmAndamento,
            finalizados: const [],
            agora: () => hoje,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abre folha de filtros.
      await tester.tap(find.byKey(const ValueKey('botao-filtros-pedidos')));
      await tester.pumpAndSettle();

      // Apenas categorias presentes nos pedidos aparecem (nunca Encanador/Diarista).
      expect(find.text('Elétrica'), findsOneWidget);
      expect(find.text('Pintura'), findsOneWidget);
      expect(find.text('Encanador'), findsNothing);
      expect(find.text('Urgente'), findsOneWidget);
      expect(find.text('Remoto'), findsNothing);

      // Seleciona categoria Elétrica + período Hoje + Aplicar.
      await tester.tap(find.text('Elétrica'));
      await tester.tap(find.text('Hoje'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.text('Troca de chuveiro'), findsOneWidget);
      expect(find.text('Pintura de sala'), findsNothing);
      expect(find.byKey(const ValueKey('badge-filtros-pedidos')), findsOneWidget);
      expect(find.byKey(const ValueKey('limpar-filtros-chips')), findsOneWidget);

      // Limpar restaura todos os pedidos.
      await tester.tap(find.byKey(const ValueKey('limpar-filtros-chips')));
      await tester.pumpAndSettle();
      expect(find.text('Troca de chuveiro'), findsOneWidget);
      expect(find.text('Pintura de sala'), findsOneWidget);

      // Ordenação Mais antigos coloca Pintura de sala antes de Troca de chuveiro.
      await tester.tap(find.byKey(const ValueKey('botao-filtros-pedidos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mais antigos'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      final yPintura = tester.getTopLeft(find.text('Pintura de sala')).dy;
      final yChuveiro = tester.getTopLeft(find.text('Troca de chuveiro')).dy;
      expect(yPintura, lessThan(yChuveiro));
    });
  });

  group('F59 — SnackBarTheme (claro e escuro)', () {
    test('TemaTrato.claro e TemaTrato.escuro usam floating e insetPadding inferior >= 88', () {
      for (final tema in [TemaTrato.claro, TemaTrato.escuro]) {
        final sb = tema.snackBarTheme;
        expect(sb.behavior, SnackBarBehavior.floating);
        expect(sb.insetPadding, isNotNull);
        final resolved = sb.insetPadding!.resolve(TextDirection.ltr);
        expect(resolved.bottom, greaterThanOrEqualTo(88));
        expect(sb.elevation, greaterThanOrEqualTo(4));
      }
    });
  });
}
