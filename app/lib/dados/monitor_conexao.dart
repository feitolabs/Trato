import 'dart:async';

import 'package:flutter/foundation.dart';

import 'estado_conexao.dart';

/// Enquanto o app está sem internet, testa a rede de tempos em tempos (uma chamada leve) e, quando
/// uma resposta chega, o próprio `ClienteApi` volta [EstadoConexao.online] para `true`; aí o
/// monitor avisa [aoReconectar] (ex.: recarregar as telas com dados novos e reenviar a fila).
/// Sem plugin nativo: vale em qualquer plataforma.
class MonitorConexao {
  MonitorConexao({
    required this.sonda,
    this.aoReconectar,
    this.intervalo = const Duration(seconds: 8),
    this.sinal,
  }) {
    _sinal.addListener(_mudou);
    _mudou();
  }

  /// Uma chamada leve à API. O resultado não importa: quem muda o estado é o `ClienteApi`.
  final Future<void> Function() sonda;
  final void Function()? aoReconectar;
  final Duration intervalo;

  /// Para teste; o padrão é o sinal global.
  final ValueNotifier<bool>? sinal;

  ValueNotifier<bool> get _sinal => sinal ?? EstadoConexao.online;

  Timer? _timer;
  var _estavaOffline = false;
  var _testando = false;

  void _mudou() {
    if (!_sinal.value) {
      _estavaOffline = true;
      _timer ??= Timer.periodic(intervalo, (_) => _testar());
    } else {
      _timer?.cancel();
      _timer = null;
      if (_estavaOffline) {
        _estavaOffline = false;
        aoReconectar?.call();
      }
    }
  }

  Future<void> _testar() async {
    if (_testando) return;
    _testando = true;
    try {
      await sonda();
    } on Object {
      // continua offline; tenta de novo no próximo intervalo
    } finally {
      _testando = false;
    }
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
    _sinal.removeListener(_mudou);
  }
}
