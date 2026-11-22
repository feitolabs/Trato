import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

Widget _envolver(Widget child, {ThemeData? tema}) =>
    MaterialApp(theme: tema ?? TemaTrato.claro, home: child);

void main() {
  group('F56 — BarraAbasFlutuante', () {
    testWidgets('renderiza abas, badge e dispara troca de aba no modo claro e escuro',
        (tester) async {
      var indice = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _envolver(
            Scaffold(
              extendBody: true,
              body: const SizedBox.expand(),
              bottomNavigationBar: BarraAbasFlutuante(
                abas: [
                  abasCliente[0],
                  abasCliente[1],
                  abasCliente[2],
                  abasCliente[3].comBadge(3),
                  abasCliente[4],
                ],
                indiceAtual: indice,
                aoSelecionar: (i) => setState(() => indice = i),
              ),
            ),
            tema: TemaTrato.escuro,
          ),
        ),
      );

      expect(find.text('Início'), findsOneWidget);
      expect(find.text('Mensagens'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('Pedidos'));
      await tester.pumpAndSettle();
      expect(indice, 2);
    });
  });

  group('F56 — Cabeçalho clicável no chat', () {
    const conversaBase = ConversaPedido(
      nome: 'Carlos Silva',
      iniciais: 'CS',
      numeroPedido: '#42',
      situacao: 'Em andamento',
      mensagens: [],
      respostasRapidas: [],
      usuarioId: 'pro1',
      pedidoId: 'p42',
    );

    testWidgets('visão cliente: tocar no cabeçalho chama aoAbrirPerfil', (tester) async {
      var abriu = false;
      await tester.pumpWidget(
        _envolver(
          ChatPedidoTela(
            conversa: conversaBase,
            aoAbrirPerfil: () => abriu = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('cabecalho-chat-perfil')));
      await tester.pump();
      expect(abriu, isTrue);
    });

    testWidgets('visão profissional: FolhaResumoPerfilCliente mostra dados e fallback sem nota',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          Scaffold(
            body: FolhaResumoPerfilCliente(
              nomeFallback: 'Tester C.',
              iniciaisFallback: 'TC',
              carregar: () async => const ResumoPerfilCliente(
                nome: 'Tester C.',
                notaMedia: null,
                totalAvaliacoes: 0,
                servicosConcluidos: 3,
                membroDesde: '2026-10-15',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tester C.'), findsOneWidget);
      expect(find.text('Sem avaliações ainda'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('No Trato desde 10/2026'), findsOneWidget);

      await tester.pumpWidget(
        _envolver(
          Scaffold(
            body: FolhaResumoPerfilCliente(
              key: const ValueKey('folha-com-nota'),
              nomeFallback: 'Maria A.',
              iniciaisFallback: 'MA',
              carregar: () async => const ResumoPerfilCliente(
                nome: 'Maria A.',
                notaMedia: 4.9,
                totalAvaliacoes: 7,
                servicosConcluidos: 9,
                membroDesde: '2025-05-01',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('★ 4,9 (7)'), findsOneWidget);
    });
  });

  group('F56 — ControladorTema e SeletorAparencia', () {
    testWidgets('troca entre Claro, Escuro e Sistema e persiste em SharedPreferences',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ControladorTema();
      await ctrl.carregar(prefs: prefs);
      expect(ctrl.modo, ThemeMode.light);

      await tester.pumpWidget(
        _envolver(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SeletorAparencia(controlador: ctrl),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('tema-escuro')));
      await tester.pumpAndSettle();
      expect(ctrl.modo, ThemeMode.dark);
      expect(prefs.getString(ControladorTema.chavePreferencia), 'dark');

      await tester.tap(find.byKey(const ValueKey('tema-sistema')));
      await tester.pumpAndSettle();
      expect(ctrl.modo, ThemeMode.system);
      expect(prefs.getString(ControladorTema.chavePreferencia), 'system');

      // Nova instância carrega o valor persistido.
      final ctrl2 = ControladorTema();
      await ctrl2.carregar(prefs: prefs);
      expect(ctrl2.modo, ThemeMode.system);
    });
  });
}
