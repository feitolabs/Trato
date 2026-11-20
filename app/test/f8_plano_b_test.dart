import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/check_out_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_check_out_fake.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  group('F8 — Plano B Check-in, Check-out e Confirmação', () {
    testWidgets('CheckInTela sem código exige foto, GPS e justificativa e inicia serviço',
        (tester) async {
      final servico = ServicoCheckInFake();
      var iniciou = false;
      await _abrir(
        tester,
        CheckInTela(
          servico: servico,
          tituloBarra: 'Pedido #AB12',
          aoIniciar: () => iniciou = true,
        ),
      );

      await _tocar(tester, find.text('Cliente sem bateria ou sinal?'));
      expect(find.text('Iniciar sem código'), findsOneWidget);
      expect(find.text('Justificativa'), findsOneWidget);

      await _tocar(tester, find.text('Tirar foto'));
      await _tocar(tester, find.text('Localizar'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Justificativa'),
        'Cliente sem bateria ou sinal na porta',
      );
      await tester.pump();

      await _tocar(tester, find.text('Iniciar serviço'));
      expect(iniciou, isTrue);
      expect(servico.justificativasSemCodigo, ['Cliente sem bateria ou sinal na porta']);
      expect(servico.codigosEnviados, isEmpty);
    });

    testWidgets('CheckOutTela sem código exige foto final, GPS, justificativa e avisa liberação',
        (tester) async {
      final servico = ServicoCheckOutFake();
      var concluiu = false;
      await _abrir(
        tester,
        CheckOutTela(
          servico: servico,
          tituloBarra: 'Pedido #AB12',
          aoConcluir: () => concluiu = true,
        ),
      );

      await _tocar(tester, find.text('Cliente sem bateria ou sinal?'));
      expect(
        find.text('O pagamento só será liberado após o cliente confirmar no app.'),
        findsOneWidget,
      );

      await _tocar(tester, find.text('Tirar foto'));
      await _tocar(tester, find.text('Localizar'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Justificativa'),
        'Cliente sem sinal na saída',
      );
      await tester.pump();

      await _tocar(tester, find.text('Concluir serviço'));
      expect(concluiu, isTrue);
      expect(servico.localizou, isTrue);
      expect(servico.justificativasSemCodigo, ['Cliente sem sinal na saída']);
      expect(servico.codigosEnviados, isEmpty);
    });

    testWidgets('ConclusaoTela com checkOutSemCodigo destaca botão de liberar pagamento',
        (tester) async {
      var confirmou = false;
      var relatou = false;
      const resumo = ResumoConclusao(
        numeroPedido: '#AB12',
        nomeProfissional: 'Carlos M.',
        legendaFotoAntes: 'Antes',
        legendaFotoDepois: 'Depois',
        orcamentoCentavos: 25000,
        aditivoCentavos: 0,
        codigo: '',
        avisoLiberacao: 'Liberação automática após prazo.',
        fotosCarregadas: true,
        checkOutSemCodigo: true,
      );

      await _abrir(
        tester,
        ConclusaoTela(
          resumo: resumo,
          aoConfirmar: () => confirmou = true,
          aoRelatarProblema: () => relatou = true,
        ),
      );

      expect(
        find.text('Confirmar conclusão e liberar pagamento'),
        findsOneWidget,
      );
      expect(find.text('Relatar problema'), findsOneWidget);
      expect(find.textContaining('Encerramento sem código'), findsOneWidget);
      expect(find.text('Código de conclusão (libera o pagamento)'), findsNothing);

      await tester.tap(find.text('Confirmar conclusão e liberar pagamento'));
      await tester.pump();
      expect(confirmou, isTrue);
      expect(relatou, isFalse);
    });

    test('PedidoApi.deJson lê check_out_sem_codigo com padrão seguro false', () {
      final base = <String, dynamic>{
        'id': 'ped-1',
        'estado': 'em_confirmacao',
        'estado_nome': 'Em confirmação',
        'cliente_id': 'cli-1',
        'profissional_id': 'pro-1',
        'aberto_em': '2026-11-20T12:00:00Z',
        'concluido_em': null,
        'acoes_permitidas': ['confirmar_conclusao'],
        'codigo_inicio': '1234',
        'codigo_conclusao': '5678',
      };

      expect(PedidoApi.deJson(base).checkOutSemCodigo, isFalse);
      expect(
        PedidoApi.deJson({...base, 'check_out_sem_codigo': true}).checkOutSemCodigo,
        isTrue,
      );
    });
  });
}
