import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/tema/tema.dart';

/// F65: a folga inferior acompanha o inset do sistema (gestos = pouco; 3 botões = mais).
void main() {
  const tamanhos = [Size(320, 568), Size(390, 844), Size(768, 1024)];
  const insets = {'gestos (0)': 0.0, 'gestos (24)': 24.0, '3 botões (48)': 48.0};

  for (final tam in tamanhos) {
    for (final e in insets.entries) {
      testWidgets(
          'FAB e fim da lista acima da barra em ${tam.width.toInt()}x${tam.height.toInt()}, inset ${e.key}',
          (tester) async {
        tester.view.physicalSize = tam;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(bottom: e.value);
        tester.view.viewPadding = FakeViewPadding(bottom: e.value);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: TemaTrato.claro,
          home: Scaffold(
            extendBody: true,
            body: Builder(
              builder: (context) => Scaffold(
                body: ListView(
                  padding: EdgeInsets.only(bottom: BarraAbasFlutuante.folgaInferior(context)),
                  children: [
                    for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('item $i')),
                    const SizedBox(key: ValueKey('ultimo'), height: 60, child: Text('fim')),
                  ],
                ),
                floatingActionButton: Padding(
                  padding: EdgeInsets.only(bottom: BarraAbasFlutuante.folgaInferior(context)),
                  child: FloatingActionButton.extended(
                    key: const ValueKey('fab'),
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                    label: const Text('Novo pedido'),
                  ),
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
        final barra = tester.getRect(find.byType(BarraAbasFlutuante));
        final fab = tester.getRect(find.byKey(const ValueKey('fab')));
        expect(fab.bottom, lessThanOrEqualTo(barra.top), reason: 'FAB cobre a barra');

        await tester.drag(find.byType(ListView), const Offset(0, -5000));
        await tester.pumpAndSettle();
        final ultimo = tester.getRect(find.byKey(const ValueKey('ultimo')));
        expect(ultimo.bottom, lessThanOrEqualTo(barra.top), reason: 'último item atrás da barra');
      });
    }
  }
}
