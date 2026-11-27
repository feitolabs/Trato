import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/nucleo/formato.dart';

void main() {
  test('formatarReais usa centavos inteiros', () {
    expect(formatarReais(0), 'R\$ 0,00');
    expect(formatarReais(123456), 'R\$ 1.234,56');
    expect(formatarReais(-12000), '-R\$ 120,00');
  });

  test('lerReaisEmCentavos: aceita o padrão brasileiro, em centavos inteiros', () {
    for (final (texto, centavos) in [
      ('12,50', 1250),
      ('3,5', 350),
      ('12', 1200),
      ('0', 0),
      ('0,01', 1),
      ('0,29', 29), // em double daria 28,999...
      ('1.000', 100000),
      ('1.234,56', 123456),
      ('1234,56', 123456),
      ('1.234.567,89', 123456789),
      ('  45,00 ', 4500),
      ('9999999999,99', 999999999999),
    ]) {
      expect(lerReaisEmCentavos(texto), centavos, reason: texto);
    }
  });

  test('lerReaisEmCentavos: recusa ambíguo e inválido, sem virar zero', () {
    for (final ruim in [
      '12.50', '12.5', '1.23', '1.2345', '1,234.56', '12,345', '1.000,5000', '1..000', '.50', ',50', '12,',
      '1.000.00', '-5', '+5', 'abc', '12a', '1 000', r'R$ 12,50', '1e3', '', '   ', '99999999999',
    ]) {
      expect(lerReaisEmCentavos(ruim), isNull, reason: '"$ruim"');
    }
  });

  test('centavosParaCampo volta pela mesma leitura', () {
    for (final c in [0, 1, 29, 1250, 123456, 100000000]) {
      expect(lerReaisEmCentavos(centavosParaCampo(c)), c);
    }
  });

  test('lerPercentualEmBps: só vírgula, até 2 casas, em inteiro', () {
    for (final (texto, bps) in [
      ('7,50', 750),
      ('7,5', 750),
      ('7', 700),
      ('0', 0),
      ('0,01', 1),
      ('0,29', 29), // em double daria 28,999...
      ('100', 10000),
      ('100,00', 10000),
      (' 12,34 ', 1234),
    ]) {
      expect(lerPercentualEmBps(texto), bps, reason: texto);
    }
    for (final ruim in ['7.50', '7.5', '1.000', '1.000,00', '7,505', '7,', ',5', '-1', '+1', '7%', 'abc', '', '  ', '1 0', '1e2', '1234567']) {
      expect(lerPercentualEmBps(ruim), isNull, reason: '"$ruim"');
    }
  });

  test('formatarConfig', () {
    expect(formatarConfig(750, 'bps'), '7,50%');
    expect(formatarConfig(48, 'horas'), '48 horas');
  });
}
