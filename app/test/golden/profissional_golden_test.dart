import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_in_fake.dart';
import 'package:trato/telas/profissional/servico_orcamento_fake.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas 25 e 26 do protótipo em celular pequeno, protótipo e tablet.
/// Atualizar: flutter test --update-goldens
/// A taxa dos goldens vem do fake (500 bps) só para reproduzir o protótipo.
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'calculadora': CalculadoraOrcamentoTela(
      servico: ServicoOrcamentoFake(taxaBps: 500),
      tituloPedido: 'Troca de tomadas e chuveiro',
      deslocamentoInicial: '30',
      horasInicial: '3',
      valorHoraInicial: '80',
      itensIniciais: const [
        ItemMaterial(nome: '2 tomadas 20 A', centavos: 4600),
        ItemMaterial(nome: 'Resistência 220 V', centavos: 6400),
      ],
      faixaRegiaoCentavos: (30000, 45000),
    ),
    'check_in': CheckInTela(
      servico: ServicoCheckInFake(),
      tituloBarra: 'Mariana · hoje, 14h',
      fotoInicial: const FotoChegada(hora: '14h06'),
      distanciaInicialMetros: 20,
    ),
  };

  for (final MapEntry(key: tela, value: widget) in telas.entries) {
    for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
      testWidgets('$tela — $nome', (tester) async {
        tester.view.physicalSize = tamanho;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            debugShowCheckedModeBanner: false,
            builder: (context, filho) => EscalaFonteLimitada(child: filho!),
            home: widget,
          ),
        );
        await tester.pump();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('profissional_${tela}_$nome.png'),
        );
      });
    }
  }
}
