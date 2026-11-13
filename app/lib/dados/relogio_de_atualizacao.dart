import 'dart:async';

import 'package:flutter/widgets.dart';

/// Atualização automática de uma tela: chama [aoAtualizar] a cada [intervalo] enquanto o app está
/// aberto, e na hora em que ele volta do segundo plano. Fica quieto com o app em segundo plano e
/// nunca dispara uma atualização em cima da outra (o chamador devolve um Future).
///
/// Uso: criar no `initState`, chamar [parar] no `dispose`.
class RelogioDeAtualizacao with WidgetsBindingObserver {
  RelogioDeAtualizacao({
    required this.intervalo,
    required this.aoAtualizar,
    this.deveAtualizar,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(intervalo, (_) => _tentar());
  }

  /// Intervalo padrão das listas: curto o bastante para parecer "ao vivo", longo o bastante para
  /// não pesar na bateria nem na API.
  static const intervaloPadrao = Duration(seconds: 12);

  final Duration intervalo;
  final Future<void> Function() aoAtualizar;

  /// Dá para pular um ciclo (ex.: a tela está escondida atrás de outra). Nulo = sempre atualiza.
  final bool Function()? deveAtualizar;

  Timer? _timer;
  var _emSegundoPlano = false;
  var _atualizando = false;

  Future<void> _tentar() async {
    if (_emSegundoPlano || _atualizando) return;
    if (deveAtualizar != null && !deveAtualizar!()) return;
    _atualizando = true;
    try {
      await aoAtualizar();
    } on Object {
      // Em segundo plano, falha de rede é silenciosa: o próximo ciclo tenta de novo.
    } finally {
      _atualizando = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final voltou = state == AppLifecycleState.resumed;
    _emSegundoPlano = !voltou;
    if (voltou) _tentar();
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
