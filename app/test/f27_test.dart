import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

const _etapas = [
  EtapaLinhaDoTempo(titulo: 'Contratado', detalhe: '', estado: EstadoEtapa.feita),
  EtapaLinhaDoTempo(titulo: 'Visita marcada', detalhe: '', estado: EstadoEtapa.atual),
  EtapaLinhaDoTempo(titulo: 'Em execução', detalhe: '', estado: EstadoEtapa.futura),
];

PedidoEmExecucao _pedido(
  String estado, {
  String? codigoInicio,
  String? codigoConclusao,
  String? visita,
  String? prazo,
  bool jaAvaliou = false,
  bool remoto = false,
  String? categoria,
  String? descricao,
}) =>
    PedidoEmExecucao(
      numero: '#AB12',
      titulo: 'Título do estado',
      etapas: _etapas,
      fotos: const [],
      estadoApi: estado,
      codigoInicio: codigoInicio,
      codigoConclusao: codigoConclusao,
      visita: visita,
      prazoConfirmacao: prazo,
      jaAvaliou: jaAvaliou,
      remoto: remoto,
      categoriaNome: categoria,
      descricao: descricao,
      podeVerConclusao: estado == 'em_confirmacao' || estado == 'concluido',
    );

void main() {
  group('Tela única do pedido (cliente): uma ação principal por estado', () {
    testWidgets('orçamento aceito: Pagar', (tester) async {
      var pagou = false;
      await _abrir(
        tester,
        PedidoExecucaoTela(pedido: _pedido('orcamento_aceito'), aoPagar: () => pagou = true),
      );
      expect(find.text('Linha do tempo'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Pagar'));
      expect(pagou, isTrue);
      expect(find.text('Confirmar serviço'), findsNothing);
    });

    testWidgets('agendado: visita e código de início, sem ação de pagar', (tester) async {
      await _abrir(
        tester,
        PedidoExecucaoTela(
          pedido: _pedido('agendado', codigoInicio: '1234', visita: '22/11 · 9:00 às 11:00'),
          aoPagar: () {},
        ),
      );
      expect(find.text('Visita: 22/11 · 9:00 às 11:00'), findsOneWidget);
      expect(find.text('Código de início'), findsOneWidget);
      expect(find.text('Pagar'), findsNothing);
    });

    testWidgets('em execução: código de conclusão', (tester) async {
      await _abrir(
        tester,
        PedidoExecucaoTela(pedido: _pedido('em_andamento', codigoConclusao: '9876')),
      );
      expect(find.text('Código de conclusão'), findsOneWidget);
      expect(find.text('Código de início'), findsNothing);
    });

    testWidgets('aguardando confirmação: Confirmar serviço e o prazo de 48 h', (tester) async {
      var abriu = false;
      await _abrir(
        tester,
        PedidoExecucaoTela(
          pedido: _pedido(
            'em_confirmacao',
            prazo: 'Você tem 48 horas para confirmar, até 23/11 · 14:30.',
          ),
          aoVerConclusao: () => abriu = true,
        ),
      );
      expect(find.textContaining('Você tem 48 horas para confirmar'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar serviço'));
      expect(abriu, isTrue);
      // "Ver conclusão" não repete a mesma ação no rodapé.
      expect(find.text('Ver conclusão'), findsNothing);
    });

    testWidgets('finalizado: Avaliar quando falta; depois, Ver garantia', (tester) async {
      var avaliou = false;
      await _abrir(
        tester,
        PedidoExecucaoTela(
          pedido: _pedido('concluido'),
          aoAvaliar: () => avaliou = true,
          aoVerGarantia: () {},
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Avaliar'));
      expect(avaliou, isTrue);
      expect(find.byKey(const ValueKey('ver-garantia')), findsOneWidget);

      await _abrir(
        tester,
        PedidoExecucaoTela(
          pedido: _pedido('concluido', jaAvaliou: true),
          aoAvaliar: () {},
          aoVerGarantia: () {},
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Avaliar'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Ver garantia'), findsOneWidget);
    });

    testWidgets('cabeçalho: categoria como título, descrição, selo Remoto; sem campo, título atual',
        (tester) async {
      await _abrir(
        tester,
        PedidoExecucaoTela(
          pedido:
              _pedido('agendado', categoria: 'Aulas', descricao: 'Aula de violão', remoto: true),
        ),
      );
      expect(find.text('Aulas'), findsOneWidget);
      expect(find.byKey(const ValueKey('descricao-pedido')), findsOneWidget);
      expect(find.byKey(const ValueKey('selo-remoto')), findsOneWidget);
      expect(find.byKey(const ValueKey('situacao-pedido')), findsOneWidget);

      await _abrir(tester, PedidoExecucaoTela(pedido: _pedido('agendado')));
      expect(find.text('Título do estado'), findsOneWidget);
      expect(find.byKey(const ValueKey('selo-remoto')), findsNothing);
    });

    testWidgets('a linha do tempo fica acima do código', (tester) async {
      await _abrir(
        tester,
        PedidoExecucaoTela(pedido: _pedido('agendado', codigoInicio: '1234')),
      );
      final tempo = tester.getTopLeft(find.text('Linha do tempo')).dy;
      final codigo = tester.getTopLeft(find.text('Código de início')).dy;
      expect(tempo, lessThan(codigo));
    });
  });

  group('Profissional: mesmo menu no Início e em Pedidos, por estado', () {
    Future<void> menu(WidgetTester tester, String estado, {bool remoto = false}) async {
      await _abrir(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => RotasTrato.acoesPedidoProfissionalParaTeste(
                context,
                estadoApi: estado,
                remoto: remoto,
              ),
              child: const Text('menu'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
    }

    testWidgets('pago: marcar data da visita (remoto: combinar início)', (tester) async {
      await menu(tester, 'pago_e_retido');
      expect(find.text('Marcar data da visita'), findsOneWidget);
      expect(find.text('Fazer check-in'), findsNothing);
      await tester.tapAt(const Offset(5, 5)); // fecha o menu
      await tester.pumpAndSettle();
      await menu(tester, 'pago_e_retido', remoto: true);
      expect(find.text('Combinar início'), findsOneWidget);
    });

    testWidgets('agendado: check-in, remarcar e ver valores', (tester) async {
      await menu(tester, 'agendado');
      expect(find.text('Fazer check-in'), findsOneWidget);
      expect(find.text('Remarcar data da visita'), findsOneWidget);
      expect(find.text('Ver valores do pedido'), findsOneWidget);
    });

    testWidgets('em andamento: concluir e ver valores', (tester) async {
      await menu(tester, 'em_andamento');
      expect(find.text('Concluir serviço (check-out)'), findsOneWidget);
      expect(find.text('Ver valores do pedido'), findsOneWidget);
      expect(find.text('Fazer check-in'), findsNothing);
    });

    testWidgets('concluído: ver valores e avaliar cliente', (tester) async {
      await menu(tester, 'concluido');
      expect(find.text('Avaliar cliente'), findsOneWidget);
      expect(find.text('Ver valores do pedido'), findsOneWidget);
      expect(find.text('Fazer check-in'), findsNothing);
    });

    testWidgets('retrabalho: atender retrabalho e ver valores', (tester) async {
      await menu(tester, 'retrabalho');
      expect(find.text('Atender retrabalho'), findsOneWidget);
      expect(find.text('Ver valores do pedido'), findsOneWidget);
    });
  });

  group('"O que fazer agora" do profissional', () {
    test('uma linha por estado', () {
      expect(oQueFazerAgora('pago_e_retido'), 'Marcar a data da visita');
      expect(oQueFazerAgora('pago_e_retido', remoto: true), 'Combinar início');
      expect(oQueFazerAgora('agendado'), 'Fazer check-in');
      expect(oQueFazerAgora('agendado', remoto: true), 'Iniciar atendimento');
      expect(oQueFazerAgora('em_andamento'), 'Pedir o código de conclusão ao cliente');
      expect(oQueFazerAgora('em_confirmacao'), 'Aguardar confirmação do cliente');
      expect(oQueFazerAgora('retrabalho'), 'Atender retrabalho');
      expect(oQueFazerAgora('concluido'), 'Avaliar cliente');
      expect(oQueFazerAgora('cancelado'), isNull);
      expect(oQueFazerAgora(null), isNull);
    });
  });
}
