import 'dart:async';
import 'package:flutter/material.dart';

import '../tema/tema.dart';
import 'botoes.dart';

/// Componente para esperas longas (> 10s):
/// Mostra barra de progresso visual, tempo decorrido, tempo estimado restante e mensagem clara.
class ProgressoEsperaLonga extends StatefulWidget {
  const ProgressoEsperaLonga({
    super.key,
    this.titulo = 'Carregando...',
    this.mensagem = 'A sincronização está demorando um pouco mais devido à conexão.',
    this.segundosEstimadosTotal = 25,
    this.segundosIniciaisDecorridos = 10,
    this.aoTentarNovamente,
    this.aoCancelar,
  });

  final String titulo;
  final String mensagem;
  final int segundosEstimadosTotal;
  final int segundosIniciaisDecorridos;
  final VoidCallback? aoTentarNovamente;
  final VoidCallback? aoCancelar;

  @override
  State<ProgressoEsperaLonga> createState() => _ProgressoEsperaLongaState();
}

class _ProgressoEsperaLongaState extends State<ProgressoEsperaLonga> {
  late int _decorridos = widget.segundosIniciaisDecorridos;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _iniciarContador();
  }

  void _iniciarContador() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _decorridos++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _segundosRestantes {
    final restante = widget.segundosEstimadosTotal - _decorridos;
    return restante > 0 ? restante : 3; // Mantém contagem regressiva positiva e amigável
  }

  double get _fracaoProgresso {
    final f = _decorridos / widget.segundosEstimadosTotal;
    return f.clamp(0.10, 0.95); // Não chega a 100% até a resposta real chegar
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EspacosTrato.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hourglass_top_rounded,
              size: 48,
              color: CoresTrato.petroleo,
            ),
            const SizedBox(height: EspacosTrato.x4),
            Text(
              widget.titulo,
              textAlign: TextAlign.center,
              style: TipografiaTrato.titulo,
            ),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              widget.mensagem,
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x6),
            ClipRRect(
              borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
              child: SizedBox(
                height: 8,
                child: LinearProgressIndicator(
                  value: _fracaoProgresso,
                  backgroundColor: CoresTrato.borda,
                  valueColor: const AlwaysStoppedAnimation<Color>(CoresTrato.petroleo),
                ),
              ),
            ),
            const SizedBox(height: EspacosTrato.x3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Decorrido: ${_decorridos}s',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
                Text(
                  'Tempo restante: ~${_segundosRestantes}s',
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: CoresTrato.petroleo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (widget.aoTentarNovamente != null || widget.aoCancelar != null) ...[
              const SizedBox(height: EspacosTrato.x6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.aoCancelar != null)
                    BotaoLink(texto: 'Cancelar', aoTocar: widget.aoCancelar!),
                  if (widget.aoCancelar != null && widget.aoTentarNovamente != null)
                    const SizedBox(width: EspacosTrato.x4),
                  if (widget.aoTentarNovamente != null)
                    BotaoSecundario(
                      texto: 'Tentar de novo',
                      aoTocar: widget.aoTentarNovamente,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

