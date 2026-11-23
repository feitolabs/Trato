import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/tema/tema.dart';

void main() {
  for (final tam in const [Size(320, 568), Size(390, 844), Size(768, 1024)]) {
    testWidgets('FAB acima da barra flutuante em ${tam.width.toInt()}x${tam.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: Scaffold(
          extendBody: true,
          body: Scaffold(
            body: const SizedBox.expand(),
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(bottom: BarraAbasFlutuante.alturaReservada),
              child: FloatingActionButton.extended(
                key: const ValueKey('fab'),
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Novo pedido'),
              ),
            ),
          ),
          bottomNavigationBar: BarraAbasFlutuante(
            abas: const [
              AbaTrato(rotulo: 'Início', icone: Icons.home_outlined),
              AbaTrato(rotulo: 'Pedidos', icone: Icons.list_alt),
            ],
            indiceAtual: 0,
            aoSelecionar: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final fab = tester.getRect(find.byKey(const ValueKey('fab')));
      final barra = tester.getRect(find.byType(BarraAbasFlutuante));
      expect(fab.bottom, lessThanOrEqualTo(barra.top));
    });
  }
}
