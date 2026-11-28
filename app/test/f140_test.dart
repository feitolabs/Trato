// APP-SUSPENSA: compensação aberta com a decisão em revisão (campo `suspensa`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/compensacoes/compensacoes_tela.dart';
import 'package:trato/telas/compensacoes/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/fontes.dart';

const _aviso = 'Em revisão: desconto suspenso';

class _Servico implements ServicoCompensacoes {
  _Servico(this.json);
  final Map<String, dynamic> json;

  @override
  Future<List<Compensacao>?> listar() async => [Compensacao.deJson(json)];
}

void main() {
  setUpAll(carregarFontesTrato);

  for (final (status, suspensa, esperado) in [
    ('aberta', true, _aviso),
    ('aberta', false, 'Aberta'),
    ('aberta', null, 'Aberta'),
    ('quitada', true, 'Quitada'),
    ('cancelada', true, 'Cancelada'),
  ]) {
    testWidgets('$status, suspensa=$suspensa', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: CompensacoesTela(
          servico: _Servico({
            'id': 'c1',
            'status': status,
            'restante_centavos': 2900,
            if (suspensa != null) 'suspensa': suspensa,
          }),
          aoFalarComOTrato: (_, __) {},
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text(esperado), findsOneWidget);
      if (esperado != _aviso) expect(find.text(_aviso), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
