import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/comuns/formato_aparelho.dart';

// A hora segue o relógio do celular. O emulador estava em 12 h e o app escrevia "0h41" ao lado
// de um relógio que mostrava "12:41 AM".

void main() {
  final meiaNoite = DateTime(2026, 11, 5, 0, 41);
  final tarde = DateTime(2026, 11, 5, 14, 5);
  final meioDia = DateTime(2026, 11, 5, 12, 0);

  test('relógio de 12 horas: meia-noite é 12 AM, tarde ganha PM', () {
    expect(horaDoAparelho(meiaNoite, relogio24h: false), '12:41 AM');
    expect(horaDoAparelho(tarde, relogio24h: false), '2:05 PM');
    expect(horaDoAparelho(meioDia, relogio24h: false), '12:00 PM');
  });

  test('relógio de 24 horas: sempre dois dígitos', () {
    expect(horaDoAparelho(meiaNoite, relogio24h: true), '00:41');
    expect(horaDoAparelho(tarde, relogio24h: true), '14:05');
  });

  test('dia e mês na ordem do Brasil', () {
    expect(diaMesDoAparelho(DateTime(2026, 11, 5)), '05/11');
  });
}
