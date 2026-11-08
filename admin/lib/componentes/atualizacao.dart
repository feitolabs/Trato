import 'dart:async';

import 'package:flutter/widgets.dart';

/// De quanto em quanto tempo as filas da Operação se atualizam sozinhas. Vem de
/// `ADMIN_ATUALIZAR_SEGUNDOS` (ver `ConfigPainel.intervaloAtualizacao`); `Duration.zero` desliga o
/// relógio, mas a fila continua se atualizando quando a pessoa volta para a aba do navegador.
Duration intervaloAtualizacao = const Duration(seconds: 60);

/// Atualiza a tela sozinha: no intervalo configurado e quando a aba volta a ficar visível.
///
/// Com a aba escondida o relógio não chama o backend. Uma atualização nunca começa enquanto a
/// anterior não terminou. Quem usa implementa [atualizarEmSilencio], que deve trocar os dados sem
/// mostrar esqueleto nem perder filtro, seleção ou o que a pessoa está digitando.
mixin AtualizaSozinho<W extends StatefulWidget> on State<W> {
  Timer? _relogio;
  AppLifecycleListener? _ciclo;
  bool _visivel = true;
  bool _atualizando = false;

  /// Desligue para telas que não precisam (o padrão é ligado).
  bool get atualizacaoLigada => true;

  Future<void> atualizarEmSilencio();

  @override
  void initState() {
    super.initState();
    if (!atualizacaoLigada) return;
    _ciclo = AppLifecycleListener(
      onShow: () {
        _visivel = true;
        _disparar();
      },
      onHide: () => _visivel = false,
    );
    if (intervaloAtualizacao > Duration.zero) {
      _relogio = Timer.periodic(intervaloAtualizacao, (_) {
        if (_visivel) _disparar();
      });
    }
  }

  Future<void> _disparar() async {
    if (_atualizando || !mounted) return;
    _atualizando = true;
    try {
      await atualizarEmSilencio();
    } catch (_) {
      // Atualização de fundo que falhou não incomoda: a tela segue com o que tinha.
    } finally {
      _atualizando = false;
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _ciclo?.dispose();
    super.dispose();
  }
}
