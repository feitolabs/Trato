import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/telas/onboarding/tour_perfil_tela.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';

Widget _envolver(Widget child, {ThemeData? tema, Key? key}) =>
    MaterialApp(key: key, theme: tema ?? TemaTrato.escuro, home: child);

void main() {
  group('F64 — Abas com SafeArea(bottom: false) e folga para BarraAbasFlutuante', () {
    testWidgets(
        'CarteiraTela, PerfilClienteTela e SeusPedidosTela usam SafeArea(bottom: false) e padding inferior >= alturaReservada',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          CarteiraTela(
            soExtrato: false,
            dados: DadosCarteira(
              resumo: resumoCarteiraDoSaldo(
                liberadoCentavos: 10000,
                retidoCentavos: 0,
                aLiberarCentavos: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final safeCarteira = tester.widget<SafeArea>(find.byType(SafeArea).first);
      expect(safeCarteira.bottom, isFalse);

      final scrollCarteira =
          tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first);
      final padCarteira = scrollCarteira.padding!.resolve(TextDirection.ltr);
      expect(padCarteira.bottom, greaterThanOrEqualTo(BarraAbasFlutuante.alturaReservada));

      await tester.pumpWidget(
        _envolver(
          const PerfilClienteTela(
            perfil: PerfilCliente(
              nome: 'João',
              iniciais: 'J',
              resumo: '1 serviço',
              grupos: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final safePerfil = tester.widget<SafeArea>(find.byType(SafeArea).first);
      expect(safePerfil.bottom, isFalse);

      await tester.pumpWidget(
        _envolver(
          const SeusPedidosTela(
            emAndamento: [],
            finalizados: [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final safePedidos = tester.widget<SafeArea>(find.byType(SafeArea).first);
      expect(safePedidos.bottom, isFalse);
    });
  });

  group('F64 — Tour do profissional ao trocar via "Usar como profissional"', () {
    testWidgets('exibe TourPerfilTela(profissional) na 1ª vez e pula direto quando já visto',
        (tester) async {
      ligarDemoNosTestes();
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        _envolver(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => RotasTrato.abrirModoProfissionalComTour(context),
                child: const Text('Usar como profissional'),
              ),
            ),
          ),
        ),
      );

      // 1ª vez: abre o tour de 4 páginas do profissional.
      await tester.tap(find.text('Usar como profissional'));
      await tester.pumpAndSettle();

      expect(find.byType(TourPerfilTela), findsOneWidget);
      final tour = tester.widget<TourPerfilTela>(find.byType(TourPerfilTela));
      expect(tour.perfil, PerfilUso.profissional);
      expect(find.text('Complete seu perfil'), findsOneWidget);

      // Tocar em "Pular" marca o tour como visto e segue para o modo profissional.
      await tester.tap(find.text('Pular'));
      await tester.pumpAndSettle();

      expect(await PreferenciaTourPerfil.visto(PerfilUso.profissional), isTrue);
      expect(find.byType(TourPerfilTela), findsNothing);
      expect(find.byType(CadastroProfissionalTela), findsOneWidget);

      // 2ª vez (já visto): vai direto sem abrir TourPerfilTela.
      await tester.pumpWidget(
        _envolver(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => RotasTrato.abrirModoProfissionalComTour(context),
                child: const Text('Usar como profissional 2'),
              ),
            ),
          ),
          key: const ValueKey('app-segunda-vez'),
        ),
      );

      await tester.tap(find.text('Usar como profissional 2'));
      await tester.pumpAndSettle();

      expect(find.byType(TourPerfilTela), findsNothing);
      expect(find.byType(CadastroProfissionalTela), findsOneWidget);
    });
  });
}
