import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/nucleo/formato.dart';

void main() {
  test('formatarReais usa centavos inteiros', () {
    expect(formatarReais(0), 'R\$ 0,00');
    expect(formatarReais(123456), 'R\$ 1.234,56');
    expect(formatarReais(-12000), '-R\$ 120,00');
  });

  test('lerReaisEmCentavos', () {
    expect(lerReaisEmCentavos('12,50'), 1250);
    expect(lerReaisEmCentavos('1.000'), 100000);
    expect(lerReaisEmCentavos('3,5'), 350);
    expect(lerReaisEmCentavos('abc'), isNull);
    expect(lerReaisEmCentavos(''), isNull);
  });

  test('formatarConfig', () {
    expect(formatarConfig(750, 'bps'), '7,50%');
    expect(formatarConfig(48, 'horas'), '48 horas');
  });
}
