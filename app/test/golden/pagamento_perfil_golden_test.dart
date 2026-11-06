import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';
import '../apoio/exemplos/telas/pagamento/dados_exemplo.dart' as expag;
import '../apoio/exemplos/telas/perfil_cliente/dados_exemplo.dart' as expcl;

/// Telas 14 (pagamento) e 22 (perfil do cliente) em 3 tamanhos.
/// Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'pagamento': const PagamentoTela(dados: expag.DadosExemplo.pagamento, ),
    'perfil_cliente': const PerfilClienteTela(perfil: expcl.DadosExemplo.perfil, ),
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

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('${tela}_$nome.png'));
      });
    }
  }
}
