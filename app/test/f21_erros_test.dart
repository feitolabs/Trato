import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_orcamento.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';

class _OrcamentoFalha extends ServicoOrcamentoFake {
  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async => throw TimeoutException('rede');
}

class _CheckInFalha extends ServicoCheckInFake {
  @override
  Future<FotoChegada?> tirarFoto() async => throw TimeoutException('camera');

  @override
  Future<int?> localizar() async => throw TimeoutException('gps');

  @override
  Future<void> avisarClienteAusente() async => throw TimeoutException('rede');

  @override
  Future<ResultadoInicio> iniciarServico(String codigo,
          {bool semCodigo = false, String? justificativa}) async =>
      throw TimeoutException('rede');
}

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('calculadora: erro ao resumir mostra aviso discreto e não quebra', (tester) async {
    await _abrir(
      tester,
      CalculadoraOrcamentoTela(
        servico: _OrcamentoFalha(),
        tituloPedido: 'Trocar tomada',
        modoInicial: ModoOrcamento.valorFechado,
      ),
    );
    await tester.enterText(find.byType(TextField).first, '150,00');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Não deu para calcular o resumo agora.'), findsOneWidget);
  });

  group('check-in: erro que não é ErroTrato vira mensagem amigável', () {
    testWidgets('tirar foto e localizar', (tester) async {
      await _abrir(tester, CheckInTela(servico: _CheckInFalha(), tituloBarra: 'Mariana'));
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      expect(find.text('Não deu para tirar a foto agora. Tente de novo.'), findsOneWidget);
      await tester.tap(find.text('Localizar'));
      await tester.pumpAndSettle();
      expect(find.text('Não deu para pegar sua localização agora. Tente de novo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iniciar serviço destrava o botão e mostra a mensagem', (tester) async {
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInFalha(),
          tituloBarra: 'Mariana',
          fotoInicial: const FotoChegada(hora: '14h00'),
          distanciaInicialMetros: 20,
        ),
      );
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.text('Não deu para iniciar agora. Tente de novo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
