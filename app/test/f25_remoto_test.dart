import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

PedidoEmExecucao _pedido({bool remoto = false, String? visita, String? prazo, String? conclusao}) =>
    PedidoEmExecucao(
      numero: '#AB12',
      titulo: 'Pagamento confirmado',
      etapas: const [],
      fotos: const [],
      codigoInicio: '1234',
      codigoConclusao: conclusao,
      remoto: remoto,
      visita: visita,
      prazoConfirmacao: prazo,
    );

ResumoConclusao _resumo({String? prazo, String? garantia}) => ResumoConclusao(
      numeroPedido: '#AB12',
      nomeProfissional: 'Carlos',
      legendaFotoAntes: 'Antes',
      legendaFotoDepois: 'Depois',
      orcamentoCentavos: 10000,
      aditivoCentavos: 0,
      codigo: '4321',
      avisoLiberacao: 'Aviso.',
      prazoConfirmacao: prazo,
      garantiaTexto: garantia,
    );

void main() {
  group('COD-1 e REM-2: tela do pedido do cliente', () {
    testWidgets('presencial: rótulo único, frase "quando ele chegar" e aviso de chat',
        (tester) async {
      await _abrir(tester, PedidoExecucaoTela(pedido: _pedido(visita: '22/11 · 9:00 às 11:00')));
      expect(find.text('Código de início'), findsOneWidget);
      expect(find.textContaining('Código de chegada'), findsNothing);
      expect(find.textContaining('quando ele chegar'), findsOneWidget);
      expect(find.textContaining('Não envie o código por mensagem.'), findsOneWidget);
      expect(find.text('Visita: 22/11 · 9:00 às 11:00'), findsOneWidget);
    });

    testWidgets('remoto: frase do atendimento, "Início combinado" e sem itens presenciais',
        (tester) async {
      await _abrir(
        tester,
        PedidoExecucaoTela(
          pedido: _pedido(remoto: true, visita: '22/11 · 9:00 às 11:00'),
          aoVerNota: () {},
          aoRemarcarVisita: () {},
        ),
      );
      expect(find.textContaining('quando o atendimento começar'), findsOneWidget);
      expect(find.textContaining('quando ele chegar'), findsNothing);
      expect(find.text('Início combinado: 22/11 · 9:00 às 11:00'), findsOneWidget);
      expect(find.text('Ver nota de materiais'), findsNothing);
      expect(find.text('Combinar início'), findsOneWidget);
      expect(find.text('Remarcar visita'), findsNothing);
    });

    testWidgets('código de conclusão com rótulo único e aviso', (tester) async {
      await _abrir(tester, PedidoExecucaoTela(pedido: _pedido(conclusao: '9876')));
      expect(find.text('Código de conclusão'), findsOneWidget);
      expect(find.textContaining('libera o pagamento'), findsNothing);
    });

    testWidgets('sem visita nem prazo (backend antigo): as linhas não aparecem', (tester) async {
      await _abrir(tester, PedidoExecucaoTela(pedido: _pedido()));
      expect(find.byKey(const ValueKey('visita-marcada')), findsNothing);
      expect(find.byKey(const ValueKey('prazo-confirmacao')), findsNothing);
    });
  });

  group('TL-3 e IDEM-1: Confirme o serviço', () {
    testWidgets('mostra prazo e garantia antes do botão; sem os campos, a linha some',
        (tester) async {
      await _abrir(
        tester,
        ConclusaoTela(
          resumo: _resumo(
            prazo: 'Você tem 48 horas para confirmar, até 23/11 · 14:30.',
            garantia: 'Garantia de 90 dias a partir da sua confirmação.',
          ),
        ),
      );
      expect(find.textContaining('Você tem 48 horas para confirmar, até 23/11'), findsOneWidget);
      expect(find.textContaining('Garantia de 90 dias'), findsOneWidget);
      expect(find.text('Código de conclusão'), findsOneWidget);
      await _abrir(tester, ConclusaoTela(resumo: _resumo()));
      expect(find.byKey(const ValueKey('prazo-e-garantia')), findsNothing);
    });

    testWidgets('Confirmar serviço: 2 toques seguidos = 1 chamada', (tester) async {
      final saida = Completer<void>();
      var chamadas = 0;
      await _abrir(
        tester,
        ConclusaoTela(
          resumo: _resumo(),
          aoConfirmar: () {
            chamadas++;
            return saida.future;
          },
        ),
      );
      await tester.tap(find.text('Confirmar serviço'));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario), warnIfMissed: false);
      await tester.pump();
      expect(chamadas, 1);
      saida.complete();
      await tester.pumpAndSettle();
    });
  });

  group('REM-2 e CHK-1: check-in', () {
    testWidgets('remoto: botão "Iniciar atendimento", sem mensagens rápidas nem ausência',
        (tester) async {
      await _abrir(
        tester,
        CheckInTela(servico: ServicoCheckInFake(), tituloBarra: 'Mariana', remoto: true),
      );
      expect(find.widgetWithText(FilledButton, 'Iniciar atendimento'), findsOneWidget);
      expect(find.text('Cheguei'), findsNothing);
      expect(find.text('Estou na portaria'), findsNothing);
      expect(find.text('Cliente não está no local'), findsNothing);
    });

    testWidgets('presencial: ausência é secundária e pede confirmação', (tester) async {
      await _abrir(tester, CheckInTela(servico: ServicoCheckInFake(), tituloBarra: 'Mariana'));
      expect(find.text('Cheguei'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('cliente-ausente')));
      await tester.tap(find.byKey(const Key('cliente-ausente')));
      await tester.pumpAndSettle();
      expect(find.text('Registrar cliente ausente?'), findsOneWidget);
    });
  });
}
