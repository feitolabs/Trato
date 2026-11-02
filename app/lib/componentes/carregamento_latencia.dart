import 'dart:async';
import 'package:flutter/material.dart';

import 'espera_longa.dart';
import 'esqueleto.dart';

/// Orquestrador de carregamento baseado nos 4 princípios de latência UI/UX:
/// - Abaixo de 1s (< 1s): Não mostra nada (evita flicker/flash em redes rápidas ou cache).
/// - De 1s a 10s (1s a 10s): Mostra o esqueleto da página (Skeleton loading).
/// - Acima de 10s (> 10s): Mostra barra de progresso com tempo decorrido e tempo restante.
class CarregamentoLatencia extends StatefulWidget {
  const CarregamentoLatencia({
    super.key,
    this.esqueleto,
    this.progressoLongo,
    this.limiarInicio = const Duration(seconds: 1),
    this.limiarEsperaLonga = const Duration(seconds: 10),
    this.duracaoInicial = Duration.zero,
    this.aoCancelar,
    this.aoTentarNovamente,
  });

  /// Widget de esqueleto a ser exibido entre 1s e 10s.
  /// Se nulo, usa o [EsqueletoPagina] padrão.
  final Widget? esqueleto;

  /// Widget customizado para esperas acima de 10s.
  /// Se nulo, usa o [ProgressoEsperaLonga].
  final Widget? progressoLongo;

  /// Tempo de espera antes de exibir o esqueleto (padrão: 1s).
  final Duration limiarInicio;

  /// Tempo de espera antes de exibir o progresso com tempo restante (padrão: 10s).
  final Duration limiarEsperaLonga;

  /// Duração inicial simulada (útil para testes ou transições).
  final Duration duracaoInicial;

  final VoidCallback? aoCancelar;
  final VoidCallback? aoTentarNovamente;

  @override
  State<CarregamentoLatencia> createState() => _CarregamentoLatenciaState();
}

enum _FaseLatencia { nada, esqueleto, progressoLongo }

class _CarregamentoLatenciaState extends State<CarregamentoLatencia> {
  late _FaseLatencia _fase;
  Timer? _timerInicio;
  Timer? _timerLongo;

  @override
  void initState() {
    super.initState();
    _definirFaseInicial();
    _agendarTransicoes();
  }

  void _definirFaseInicial() {
    final inicialMs = widget.duracaoInicial.inMilliseconds;
    if (inicialMs >= widget.limiarEsperaLonga.inMilliseconds) {
      _fase = _FaseLatencia.progressoLongo;
    } else if (inicialMs >= widget.limiarInicio.inMilliseconds) {
      _fase = _FaseLatencia.esqueleto;
    } else {
      _fase = _FaseLatencia.nada;
    }
  }

  void _agendarTransicoes() {
    final inicialMs = widget.duracaoInicial.inMilliseconds;
    final inicioMs = widget.limiarInicio.inMilliseconds;
    final longoMs = widget.limiarEsperaLonga.inMilliseconds;

    if (inicialMs < inicioMs) {
      _timerInicio = Timer(Duration(milliseconds: inicioMs - inicialMs), () {
        if (!mounted) return;
        setState(() => _fase = _FaseLatencia.esqueleto);
      });
    }

    if (inicialMs < longoMs) {
      _timerLongo = Timer(Duration(milliseconds: longoMs - inicialMs), () {
        if (!mounted) return;
        setState(() => _fase = _FaseLatencia.progressoLongo);
      });
    }
  }

  @override
  void dispose() {
    _timerInicio?.cancel();
    _timerLongo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_fase) {
      _FaseLatencia.nada => const SizedBox.shrink(),
      _FaseLatencia.esqueleto => widget.esqueleto ?? const EsqueletoPagina(),
      _FaseLatencia.progressoLongo => widget.progressoLongo ??
          ProgressoEsperaLonga(
            aoCancelar: widget.aoCancelar,
            aoTentarNovamente: widget.aoTentarNovamente,
            segundosIniciaisDecorridos: widget.limiarEsperaLonga.inSeconds,
          ),
    };
  }
}

