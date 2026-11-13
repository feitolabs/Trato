import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Marca da Feito Labs: grade 3x3 de peças (o "F" com o ponto laranja), desenhada em código
/// a partir da splash do protótipo. Cada peça tem [_peca] de lado e [_vao] de espaço entre elas.
class LogoFeitoLabs extends StatelessWidget {
  const LogoFeitoLabs({super.key, this.tamanho = 72, this.sobreFundoClaro = false});

  final double tamanho;

  /// As peças são cor creme, feitas para o fundo escuro da splash. Sobre fundo claro (creme ou
  /// branco) elas somem e a marca parece cortada: com `true` viram petróleo.
  final bool sobreFundoClaro;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Feito Labs',
      child: CustomPaint(size: Size.square(tamanho), painter: _PintorLogo(sobreFundoClaro)),
    );
  }
}

class _PintorLogo extends CustomPainter {
  const _PintorLogo(this.sobreFundoClaro);

  final bool sobreFundoClaro;

  static const _peca = 113.0;
  static const _vao = 18.0;
  static const _total = 3 * _peca + 2 * _vao;

  @override
  void paint(Canvas canvas, Size size) {
    final escala = size.width / _total;
    canvas.scale(escala);

    void peca(int linha, int coluna, Color cor, {double? tl, double? tr, double? bl, double? br}) {
      final retangulo = Rect.fromLTWH(
        coluna * (_peca + _vao),
        linha * (_peca + _vao),
        _peca,
        _peca,
      );
      Radius raio(double? r) => Radius.circular(r ?? 0);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          retangulo,
          topLeft: raio(tl),
          topRight: raio(tr),
          bottomLeft: raio(bl),
          bottomRight: raio(br),
        ),
        Paint()..color = cor,
      );
    }

    const metade = _peca / 2;
    final base = sobreFundoClaro ? CoresTrato.petroleo : CoresTrato.creme;
    peca(0, 0, base, tl: _peca);
    peca(0, 1, CoresTrato.logoAzul);
    peca(0, 2, CoresTrato.logoAzul, tr: _peca);
    peca(1, 0, base);
    peca(1, 1, CoresTrato.logoAzulClaro, tr: metade, br: metade);
    peca(2, 0, base, bl: _peca);
    canvas.drawCircle(
      const Offset(2 * (_peca + _vao) + metade, 2 * (_peca + _vao) + metade),
      metade,
      Paint()..color = CoresTrato.laranja,
    );
  }

  @override
  bool shouldRepaint(covariant _PintorLogo antigo) => antigo.sobreFundoClaro != sobreFundoClaro;
}
