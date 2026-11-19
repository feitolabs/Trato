import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// A moeda do Trato: ouro com borda serrilhada, o "T" em relevo e um brilho que passa.
/// `brilho` vai de 0 a 1 e move a faixa de luz; use 0.5 para uma moeda parada.
class MoedaTrato extends StatelessWidget {
  const MoedaTrato({super.key, this.tamanho = 120, this.brilho = 0.5});

  final double tamanho;
  final double brilho;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: tamanho,
        child: CustomPaint(painter: _PinturaMoeda(brilho)),
      );
}

class _PinturaMoeda extends CustomPainter {
  _PinturaMoeda(this.brilho);

  final double brilho;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final borda = Rect.fromCircle(center: c, radius: r);

    // Aro: ouro com degradê diagonal.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CoresTrato.moedaOuroClaro, CoresTrato.moedaOuro, CoresTrato.moedaOuroEscuro],
          stops: [0, 0.45, 1],
        ).createShader(borda),
    );

    // Serrilha: marcas curtas no aro.
    final serrilha = Paint()
      ..color = CoresTrato.moedaOuroEscuro.withValues(alpha: 0.55)
      ..strokeWidth = r * 0.028
      ..strokeCap = StrokeCap.round;
    const marcas = 56;
    for (var i = 0; i < marcas; i++) {
      final a = i * 2 * math.pi / marcas;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.93),
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.985),
        serrilha,
      );
    }

    // Sulco entre o aro e a face.
    canvas.drawCircle(
      c,
      r * 0.84,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = CoresTrato.moedaOuroProfundo.withValues(alpha: 0.5),
    );

    // Face: degradê radial, mais clara no canto de cima.
    final face = Rect.fromCircle(center: c, radius: r * 0.8);
    canvas.drawCircle(
      c,
      r * 0.8,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [CoresTrato.moedaOuroClaro, CoresTrato.moedaOuro, CoresTrato.moedaOuroEscuro],
          stops: [0, 0.55, 1],
        ).createShader(face),
    );

    // "T" em relevo: sombra embaixo, luz em cima, ouro escuro no meio.
    void letra(Offset desloc, Color cor) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'T',
          style: TextStyle(
            fontFamily: TipografiaTrato.fonteTitulos,
            fontWeight: FontWeight.w900,
            fontSize: r * 1.15,
            height: 1,
            color: cor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2) + desloc);
    }

    letra(Offset(0, r * 0.035), CoresTrato.moedaOuroClaro.withValues(alpha: 0.9));
    letra(Offset(0, -r * 0.02), CoresTrato.moedaOuroProfundo);
    letra(Offset.zero, CoresTrato.moedaOuroEscuro);

    // Brilho: faixa diagonal de luz que atravessa a moeda.
    canvas.save();
    canvas.clipPath(Path()..addOval(borda));
    final x = -r * 1.6 + brilho * size.width * 2.4;
    canvas.translate(x, 0);
    canvas.rotate(0.5);
    canvas.drawRect(
      Rect.fromLTWH(-r * 0.12, -size.height, r * 0.34, size.height * 3),
      Paint()
        ..shader = LinearGradient(
          colors: [
            CoresTrato.textoSobreFoto.withValues(alpha: 0),
            CoresTrato.textoSobreFoto.withValues(alpha: 0.55),
            CoresTrato.textoSobreFoto.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(-r * 0.12, 0, r * 0.34, 1)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PinturaMoeda antigo) => antigo.brilho != brilho;
}
