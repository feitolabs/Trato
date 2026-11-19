import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tema/tema.dart';

/// Recompensa depois de avaliar: moeda que salta, número que sobe e confete.
/// Só mostra o que o backend já creditou (`moedas`); nenhuma conta roda aqui.
/// Respeita "reduzir animações": nesse caso já abre no estado final.
class MoedasGanhasTela extends StatefulWidget {
  const MoedasGanhasTela({
    super.key,
    required this.moedas,
    required this.aoContinuar,
  });

  final int moedas;
  final VoidCallback aoContinuar;

  @override
  State<MoedasGanhasTela> createState() => _MoedasGanhasTelaState();
}

class _MoedasGanhasTelaState extends State<MoedasGanhasTela>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _iniciou = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    if (MediaQuery.of(context).disableAnimations) {
      _ctl.value = 1;
    } else {
      HapticFeedback.mediumImpact();
      _ctl.forward().whenComplete(HapticFeedback.lightImpact);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.aoContinuar();
      },
      child: Scaffold(
        backgroundColor: CoresTrato.petroleo,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _ctl,
                  builder: (context, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _Confete(_ctl.value)),
                      ),
                      _Conteudo(progresso: _ctl.value, moedas: widget.moedas),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(EspacosTrato.x4),
                child: ConteudoResponsivo(
                  // Botão claro: o primário do tema é petróleo e sumiria neste fundo.
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.aoContinuar,
                      style: FilledButton.styleFrom(
                        backgroundColor: CoresTrato.creme,
                        foregroundColor: CoresTrato.petroleo,
                        minimumSize: const Size.fromHeight(52),
                        textStyle: TipografiaTrato.corpoForte,
                      ),
                      child: const Text('Continuar'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  const _Conteudo({required this.progresso, required this.moedas});

  final double progresso;
  final int moedas;

  @override
  Widget build(BuildContext context) {
    // 0–35%: a moeda salta; 20–65%: o número sobe; 55–100%: textos aparecem.
    final moeda = Curves.elasticOut.transform((progresso / 0.35).clamp(0.0, 1.0));
    final contagem = Curves.easeOutCubic.transform(
      ((progresso - 0.2) / 0.45).clamp(0.0, 1.0),
    );
    final textos = Curves.easeOut.transform(((progresso - 0.55) / 0.3).clamp(0.0, 1.0));
    final brilho = 0.5 + 0.5 * math.sin(progresso * math.pi * 6);
    final valor = (moedas * contagem).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: moeda,
          child: Transform.rotate(
            angle: (1 - moeda) * -0.6,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CoresTrato.ambarSuave,
                border: Border.all(color: CoresTrato.laranja, width: 7),
                boxShadow: [
                  BoxShadow(
                    color: CoresTrato.laranja.withValues(alpha: 0.25 + 0.3 * brilho),
                    blurRadius: 28 + 22 * brilho,
                    spreadRadius: 4 + 6 * brilho,
                  ),
                ],
              ),
              child: const Icon(Icons.star_rounded, size: 72, color: CoresTrato.laranja),
            ),
          ),
        ),
        const SizedBox(height: EspacosTrato.x6),
        Text(
          '+$valor',
          style: TipografiaTrato.marca.copyWith(color: CoresTrato.creme, fontSize: 80),
        ),
        Opacity(
          opacity: textos,
          child: Transform.translate(
            offset: Offset(0, (1 - textos) * 12),
            child: Column(
              children: [
                Text(
                  moedas == 1 ? 'moeda do Trato' : 'moedas do Trato',
                  style: TipografiaTrato.titulo.copyWith(color: CoresTrato.azulClaro),
                ),
                const SizedBox(height: EspacosTrato.x4),
                Text(
                  'Obrigado por avaliar!',
                  style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.creme),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x5),
                  child: Text(
                    'Sua avaliação ajuda outras pessoas a escolher bem. As moedas já estão na sua conta.',
                    style: TipografiaTrato.corpo.copyWith(color: CoresTrato.creme),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Confete: pontos que saem do centro, abrem em leque e caem, sumindo no fim.
class _Confete extends CustomPainter {
  _Confete(this.t);

  final double t;

  static const _cores = [
    CoresTrato.laranja,
    CoresTrato.azulClaro,
    CoresTrato.ambarSuave,
    CoresTrato.creme,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final aleatorio = math.Random(7);
    final centro = Offset(size.width / 2, size.height * 0.40);
    final fase = ((t - 0.05) / 0.9).clamp(0.0, 1.0);
    if (fase <= 0) return;
    for (var i = 0; i < 36; i++) {
      final angulo = aleatorio.nextDouble() * math.pi * 2;
      final alcance = 90 + aleatorio.nextDouble() * (size.width * 0.55);
      final tamanho = 4 + aleatorio.nextDouble() * 6;
      final cor = _cores[i % _cores.length];
      final sobe = Curves.easeOutCubic.transform(fase);
      final cai = fase * fase * 90;
      final pos = centro +
          Offset(math.cos(angulo) * alcance * sobe, math.sin(angulo) * alcance * sobe + cai);
      final alfa = (1 - ((fase - 0.6) / 0.4).clamp(0.0, 1.0));
      final pincel = Paint()..color = cor.withValues(alpha: alfa);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angulo + fase * 6);
      if (i.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: tamanho * 1.8, height: tamanho),
            const Radius.circular(2),
          ),
          pincel,
        );
      } else {
        canvas.drawCircle(Offset.zero, tamanho / 2, pincel);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confete antigo) => antigo.t != t;
}
