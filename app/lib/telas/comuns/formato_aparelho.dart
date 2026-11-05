import 'dart:ui' show PlatformDispatcher;

/// Hora no formato que o CELULAR usa: 24 h ("14:05") ou 12 h ("2:05 PM"), conforme a
/// configuração do aparelho. Antes o app escrevia "14h05" ou "0h41" mesmo com o relógio em 12 h.
/// [relogio24h] só existe para os testes.
String horaDoAparelho(DateTime momento, {bool? relogio24h}) {
  final t = momento.toLocal();
  final minutos = t.minute.toString().padLeft(2, '0');
  if (relogio24h ?? PlatformDispatcher.instance.alwaysUse24HourFormat) {
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
