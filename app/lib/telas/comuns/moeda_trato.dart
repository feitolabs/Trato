import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// A moeda do Trato, no estilo de ilustração: cores chapadas, "espessura" em bloco, traços de
/// brilho à mão e o "T" carimbado, um pouco fora do registro. Nada de degradê de vidro.
/// `brilho` (0 a 1) só faz as faíscas pulsarem; a moeda parada usa 0.5.
class MoedaTrato extends StatelessWidget {
  const MoedaTrato({super.key, this.tamanho = 120, this.brilho = 0.5});

  final double tamanho;
  final double brilho;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: tamanho,
        child: Transform.rotate(
          angle: -0.14, // levemente torta, como desenhada
          child: CustomPaint(painter: _PinturaMoeda(brilho)),
        ),
      );
}

class _PinturaMoeda extends CustomPainter {
  _PinturaMoeda(this.brilho);

  final double brilho;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.44; // sobra espaço para a espessura e as faíscas
    final c = Offset(size.width / 2 - r * 0.04, size.height / 2 - r * 0.05);
    final espessura = Offset(r * 0.09, r * 0.12);

    // Espessura da moeda: o mesmo círculo, deslocado, em ouro escuro.
    canvas.drawCircle(c + espessura, r, Paint()..color = CoresTrato.moedaOuroEscuro);
    // Contorno grosso, que dá o ar de desenho.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = CoresTrato.moedaOuroProfundo,
    );
    // Face chapada.
    canvas.drawCircle(c, r * 0.97, Paint()..color = CoresTrato.moedaOuro);

    // Anel interno pontilhado, com falhas irregulares (a mão não é perfeita).
    final ponto = Paint()
      ..color = CoresTrato.moedaOuroEscuro
      ..style = PaintingStyle.fill;
    const pontos = 22;
    for (var i = 0; i < pontos; i++) {
      if (i == 5 || i == 13) continue; // falhas
      final a = i * 2 * math.pi / pontos + 0.1;
      final raio = r * (0.76 + (i.isEven ? 0.008 : -0.008));
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * raio,
        r * (i % 3 == 0 ? 0.045 : 0.035),
        ponto,
      );
    }

    // "T" carimbado: a tinta clara vem levemente deslocada da escura.
    void letra(Offset desloc, Color cor) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'T',
          style: TextStyle(
            fontFamily: TipografiaTrato.fonteTitulos,
            fontWeight: FontWeight.w900,
            fontSize: r * 1.12,
            height: 1,
            color: cor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2) + desloc);
    }

    letra(Offset(-r * 0.045, -r * 0.04), CoresTrato.moedaOuroClaro);
    letra(Offset(r * 0.012, r * 0.02), CoresTrato.moedaOuroProfundo);

    // Dois riscos de brilho no canto de cima: curtos, grossos, pontas redondas.
    final risco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = CoresTrato.moedaOuroClaro;
    final arco = Rect.fromCircle(center: c, radius: r * 0.86);
    canvas.drawArc(arco, math.pi * 1.12, 0.62, false, risco..strokeWidth = r * 0.085);
    canvas.drawArc(arco, math.pi * 1.12 + 0.82, 0.14, false, risco..strokeWidth = r * 0.085);

    // Faíscas de quatro pontas, em tamanhos e posições diferentes.
    final t = 0.75 + 0.25 * math.sin(brilho * math.pi * 2);
    _faisca(canvas, c + Offset(r * 1.08, -r * 0.82), r * 0.2 * t, CoresTrato.moedaOuroClaro);
    _faisca(canvas, c + Offset(-r * 1.02, r * 0.58), r * 0.12 * (1.9 - t), CoresTrato.moedaOuroClaro);
    _faisca(canvas, c + Offset(r * 0.88, r * 0.98), r * 0.09 * t, CoresTrato.moedaOuro);
  }

  void _faisca(Canvas canvas, Offset p, double tam, Color cor) {
    final caminho = Path()
      ..moveTo(p.dx, p.dy - tam)
      ..quadraticBezierTo(p.dx, p.dy, p.dx + tam, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + tam)
      ..quadraticBezierTo(p.dx, p.dy, p.dx - tam, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - tam)
      ..close();
    canvas.drawPath(caminho, Paint()..color = cor);
  }

  @override
  bool shouldRepaint(_PinturaMoeda antigo) => antigo.brilho != brilho;
}
