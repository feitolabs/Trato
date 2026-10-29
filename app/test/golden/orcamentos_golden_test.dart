import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/orcamentos/dados_exemplo.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas 11 (Novo pedido), 12 (Orçamentos recebidos) e 13 (Detalhe do orçamento) do PDF
/// em celular pequeno, protótipo e tablet. Altura grande para a tela inteira caber.
/// Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 1900),
    'celular': Size(390, 1700),
    'tablet': Size(768, 1700),
  };
  final telas = <String, Widget>{
    'novo_pedido': const NovoPedidoTela(),
    'orcamentos': OrcamentosRecebidosTela(),
    'detalhe_orcamento': DetalheOrcamentoTela(orcamento: orcamentosExemplo[1]),
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

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('pedido_${tela}_$nome.png'));
      });
    }
  }
}
