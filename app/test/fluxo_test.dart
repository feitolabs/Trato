import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/auth/confirmar_celular_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/garantia_tela.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional/area_profissional_provisoria.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/tema/tema.dart';

/// Percursos completos entre as telas, com os dados de exemplo.
Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, String texto) async {
  await tester.tap(find.text(texto).last);
  await tester.pumpAndSettle();
}

/// Volta uma tela, como o botão voltar do sistema (algumas telas têm cabeçalho próprio).
Future<void> _voltar(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('login leva à casca do cliente e some do histórico', (tester) async {
    await _abrir(tester, const LoginTela());
    await tester.enterText(find.byType(TextField).at(0), 'mariana@email.com');
    await tester.enterText(find.byType(TextField).at(1), 'segredo123');

    await _tocar(tester, 'Entrar');

    expect(find.byType(CascaClienteTela), findsOneWidget);
    expect(find.byType(LoginTela), findsNothing);
  });

  testWidgets('pedido em execução: chat, conclusão e avaliação', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Pedidos');

    await _tocar(tester, 'Troca de tomadas e chuveiro');
    expect(find.byType(PedidoExecucaoTela), findsOneWidget);

    await _tocar(tester, 'Conversar');
    expect(find.byType(ChatPedidoTela), findsOneWidget);
    await _voltar(tester);

    await _tocar(tester, 'Ver conclusão');
    expect(find.byType(ConclusaoTela), findsOneWidget);

    await _tocar(tester, 'Confirmar serviço');
    expect(find.byType(AvaliacaoTela), findsOneWidget);

    await _tocar(tester, 'Avaliar depois');
    expect(find.byType(CascaClienteTela), findsOneWidget);
    expect(find.byType(AvaliacaoTela), findsNothing);
  });

  testWidgets('conclusão: Relatar problema abre o relato', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Pedidos');
    await _tocar(tester, 'Troca de tomadas e chuveiro');
    await _tocar(tester, 'Ver conclusão');

    await _tocar(tester, 'Relatar problema');

    expect(find.byType(RelatarProblemaTela), findsOneWidget);
  });

  testWidgets('pedido finalizado abre a garantia', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Pedidos');
    await _tocar(tester, 'Finalizados');

    await _tocar(tester, 'Pintura da sala (exemplo)');

    expect(find.byType(GarantiaTela), findsOneWidget);
  });

  testWidgets('pedido sem tela própria abre "em breve", sem quebrar', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Pedidos');

    await _tocar(tester, 'Vazamento na pia');

    expect(find.text('Esta tela chega nas próximas etapas.'), findsOneWidget);
  });

  group('cadastro', () {
    testWidgets('cliente confirma o código e cai na casca do cliente', (tester) async {
      await _abrir(tester, const ConfirmarCelularTela(celular: '(31) 98888-4417'));
      await tester.enterText(find.byType(TextField), '123456');

      await _tocar(tester, 'Confirmar código');

      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('profissional cai na área provisória e abre orçamento e check-in', (tester) async {
      await _abrir(
        tester,
        const ConfirmarCelularTela(celular: '(31) 98888-4417', perfil: PerfilUso.profissional),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await _tocar(tester, 'Confirmar código');
      expect(find.byType(AreaProfissionalProvisoria), findsOneWidget);

      await _tocar(tester, 'Fazer orçamento');
      expect(find.byType(CalculadoraOrcamentoTela), findsOneWidget);
      await _voltar(tester);

      await _tocar(tester, 'Fazer check-in');
      expect(find.byType(CheckInTela), findsOneWidget);
    });
  });
}
