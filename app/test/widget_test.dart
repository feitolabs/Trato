import 'package:flutter_test/flutter_test.dart';
import 'package:trato/main.dart';

void main() {
  testWidgets('mostra o nome e o lema do Trato', (tester) async {
    await tester.pumpWidget(const TratoApp());

    expect(find.text('Trato'), findsOneWidget);
    expect(find.text('Serviço feito, dinheiro liberado.'), findsOneWidget);
  });
}
