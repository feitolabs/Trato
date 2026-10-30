import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/aditivo/criar_aditivo_tela.dart';
import 'package:trato/telas/aditivo/responder_aditivo_tela.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/disputa_profissional/atender_retrabalho_tela.dart';
import 'package:trato/telas/disputa_profissional/responder_disputa_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/nota_material/enviar_nota_tela.dart';
import 'package:trato/telas/nota_material/ver_nota_tela.dart';
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
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/telas/verificacao/verificacao_tela.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/telas/profissional_inicio/casca_profissional_tela.dart';
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

  testWidgets('pedido sem tela própria mostra aviso, sem quebrar', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Pedidos');

    await _tocar(tester, 'Vazamento na pia');

    expect(find.textContaining('Avisamos aqui quando houver novidade'), findsOneWidget);
  });

  group('cadastro', () {
    testWidgets('cliente confirma o código e cai na casca do cliente', (tester) async {
      await _abrir(tester, const ConfirmarCelularTela(celular: '(31) 98888-4417'));
      await tester.enterText(find.byType(TextField), '123456');

      await _tocar(tester, 'Confirmar código');

      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('profissional passa por cadastro e verificação e cai na casca do profissional', (tester) async {
      await _abrir(
        tester,
        const ConfirmarCelularTela(celular: '(31) 98888-4417', perfil: PerfilUso.profissional),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await _tocar(tester, 'Confirmar código');
      expect(find.byType(CadastroProfissionalTela), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Carlos Almeida');
      await tester.enterText(find.byType(TextField).at(2), 'Belo Horizonte');
      await _tocar(tester, 'Eletricista');
      await _tocar(tester, 'Seg');
      await _tocar(tester, 'Manhã');
      await _tocar(tester, 'Salvar e continuar');
      expect(find.byType(VerificacaoTela), findsOneWidget);

      await _tocar(tester, 'Foto do documento');
      await _tocar(tester, 'Selfie segurando o rosto');
      await tester.tap(find.byKey(const Key('ciente_lgpd')));
      await tester.pumpAndSettle();
      await _tocar(tester, 'Enviar para análise');
      expect(find.byType(CascaProfissionalTela), findsOneWidget);
    });
  });

  testWidgets('pedido com orçamentos: detalhe do Carlos até o pagamento', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Pedidos');
    await _tocar(tester, 'Instalar ventilador de teto');
    expect(find.byType(OrcamentosRecebidosTela), findsOneWidget);

    await tester.tap(find.text('Ver orçamento').at(1));
    await tester.pumpAndSettle();
    expect(find.byType(DetalheOrcamentoTela), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Aceitar orçamento'));
    await tester.pumpAndSettle();
    expect(find.byType(PagamentoTela), findsOneWidget);
  });

  testWidgets('aba Perfil do cliente abre o perfil', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Perfil');
    expect(find.byType(PerfilClienteTela), findsOneWidget);
  });

  testWidgets('aba Mensagens abre a lista e o chat do pedido', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Mensagens');
    expect(find.byType(MensagensTela), findsOneWidget);
  });

  testWidgets('Perfil: dados e privacidade e ajuda abrem as telas', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Perfil');
    await _tocar(tester, 'Central de ajuda');
    expect(find.byType(AjudaTela), findsOneWidget);
  });

  testWidgets('pedido em execução: abre a nota de materiais e o aditivo', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Pedidos');
    await _tocar(tester, 'Troca de tomadas e chuveiro');

    await _tocar(tester, 'Ver nota de materiais');
    expect(find.byType(VerNotaTela), findsOneWidget);
    expect(find.text('Materiais do serviço'), findsOneWidget);
    await _voltar(tester);

    await _tocar(tester, 'Ver aditivo do serviço');
    expect(find.byType(ResponderAditivoTela), findsOneWidget);
  });

  testWidgets('notificação de disputa e de retrabalho abrem as telas do profissional',
      (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Perfil');
    await _tocar(tester, 'Notificações');

    await _tocar(tester, 'Disputa aberta no seu serviço');
    expect(find.byType(ResponderDisputaTela), findsOneWidget);
    await _voltar(tester);

    await _tocar(tester, 'Retrabalho pedido');
    expect(find.byType(AtenderRetrabalhoTela), findsOneWidget);
  });

  testWidgets('aba Buscar: busca por serviço e abre o perfil do profissional', (tester) async {
    await _abrir(tester, const CascaClienteTela());
    await _tocar(tester, 'Buscar');
    expect(find.byType(BuscaProfissionaisTela), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Carlos');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await _tocar(tester, 'Carlos Mendes');

    expect(find.byType(PerfilProfissionalTela), findsOneWidget);
  });

  testWidgets('profissional: pedido de hoje oferece nota de materiais e aditivo', (tester) async {
    await _abrir(tester, RotasTrato.cascaProfissionalParaTeste());
    await _tocar(tester, 'Fazer check-in');
    expect(find.text('Enviar nota de materiais'), findsOneWidget);
    expect(find.text('Criar aditivo'), findsOneWidget);

    await _tocar(tester, 'Enviar nota de materiais');
    expect(find.byType(EnviarNotaTela), findsOneWidget);
    await _voltar(tester);

    await _tocar(tester, 'Fazer check-in');
    await _tocar(tester, 'Criar aditivo');
    expect(find.byType(CriarAditivoTela), findsOneWidget);
  });
}
