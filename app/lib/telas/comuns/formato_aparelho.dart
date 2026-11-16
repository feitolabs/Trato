/// Hora no padrão brasileiro de 24 h ("14:05").
/// [relogio24h] só existe para os testes.
String horaDoAparelho(DateTime momento, {bool? relogio24h}) {
  final t = momento.toLocal();
  final minutos = t.minute.toString().padLeft(2, '0');
  if (relogio24h ?? true) {
    return '${t.hour.toString().padLeft(2, '0')}:$minutos';
  }
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:$minutos ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "05/11": dia e mês na ordem do português do Brasil.
String diaMesDoAparelho(DateTime momento) {
  final t = momento.toLocal();
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
}
