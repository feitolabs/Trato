import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Ilustrações vetoriais do onboarding do profissional (4 páginas, desenhadas em código).
/// Sem imagens, sem texto interno e usando somente a paleta [CoresTrato].
class IlustracaoOnboardingProfissional extends StatelessWidget {
  const IlustracaoOnboardingProfissional({
    super.key,
    required this.pagina,
    this.tamanho = 220,
  });

  final int pagina;
  final double tamanho;

  static const _rotulos = <String>[
    'Ilustração: complete seu perfil profissional',
    'Ilustração: receba pedidos no celular',
    'Ilustração: receba na carteira sem taxa',
    'Ilustração: ganhe Tratinhos com prazo de 48 horas',
  ];

  @override
  Widget build(BuildContext context) {
    if (pagina < 0 || pagina >= _rotulos.length) {
      return const SizedBox.shrink();
    }
    return Semantics(
      image: true,
      label: _rotulos[pagina],
      child: SizedBox.square(
        dimension: tamanho,
        child: CustomPaint(
          painter: _PintorIlustracaoProfissional(pagina),
        ),
      ),
    );
  }
}

class _PintorIlustracaoProfissional extends CustomPainter {
  const _PintorIlustracaoProfissional(this.pagina);

  final int pagina;

  static const _base = 220.0;

  Paint _preencher(Color cor) => Paint()
    ..color = cor
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  Paint _traco(Color cor, double largura) => Paint()
    ..color = cor
    ..style = PaintingStyle.stroke
    ..strokeWidth = largura
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    final lado = math.min(size.width, size.height);
    if (lado <= 0) return;
    canvas.save();
    canvas.translate((size.width - lado) / 2, (size.height - lado) / 2);
    canvas.scale(lado / _base);

    switch (pagina) {
      case 0:
        _desenharPerfil(canvas);
      case 1:
        _desenharPedidos(canvas);
      case 2:
        _desenharCarteira(canvas);
      case 3:
        _desenharTratinhos(canvas);
    }

    canvas.restore();
  }

  /// Página 0: cartão de perfil com avatar circular, duas linhas e selo de verificado.
  void _desenharPerfil(Canvas canvas) {
    // Fundo suave circular e detalhe geométrico.
    canvas.drawCircle(const Offset(110, 114), 86, _preencher(CoresTrato.azulSuave));
    canvas.drawCircle(const Offset(42, 60), 10, _preencher(CoresTrato.creme));
    canvas.drawCircle(const Offset(180, 174), 8, _preencher(CoresTrato.ambarSuave));

    // Sombra plana do cartão.
    final sombra = RRect.fromRectAndRadius(
      const Rect.fromLTWH(34, 58, 152, 118),
      const Radius.circular(20),
    );
    canvas.drawRRect(sombra, _preencher(CoresTrato.logoAzulClaro));

    // Cartão principal de perfil.
    final cartao = RRect.fromRectAndRadius(
      const Rect.fromLTWH(30, 52, 152, 118),
      const Radius.circular(20),
    );
    canvas.drawRRect(cartao, _preencher(CoresTrato.superficie));
    canvas.drawRRect(cartao, _traco(CoresTrato.petroleo, 3));

    // Avatar circular à esquerda.
    const centroAvatar = Offset(72, 102);
    const raioAvatar = 24.0;
    canvas.drawCircle(centroAvatar, raioAvatar, _preencher(CoresTrato.azulSuave));
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: centroAvatar, radius: raioAvatar)),
    );
    canvas.drawCircle(const Offset(72, 95), 8.5, _preencher(CoresTrato.petroleo));
    canvas.drawOval(
      const Rect.fromLTWH(52, 108, 40, 26),
      _preencher(CoresTrato.petroleo),
    );
    canvas.restore();
    canvas.drawCircle(centroAvatar, raioAvatar, _traco(CoresTrato.petroleo, 2.5));

    // Duas linhas de texto do perfil (formas planas arredondadas).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(108, 88, 56, 11),
        const Radius.circular(6),
      ),
      _preencher(CoresTrato.petroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(108, 107, 42, 9),
        const Radius.circular(5),
      ),
      _preencher(CoresTrato.bordaControle),
    );

    // Pílulas discretas de habilidades no rodapé do cartão.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(48, 140, 42, 12),
        const Radius.circular(6),
      ),
      _preencher(CoresTrato.creme),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(98, 140, 34, 12),
        const Radius.circular(6),
      ),
      _preencher(CoresTrato.ambarSuave),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(140, 140, 24, 12),
        const Radius.circular(6),
      ),
      _preencher(CoresTrato.verdeSuave),
    );

    // Selo de verificado no canto superior direito.
    const centroSelo = Offset(174, 58);
    canvas.drawCircle(centroSelo, 25, _preencher(CoresTrato.superficie));
    canvas.drawCircle(centroSelo, 21, _preencher(CoresTrato.verdeTexto));
    final check = Path()
      ..moveTo(164, 58)
      ..lineTo(171, 65)
      ..lineTo(185, 51);
    canvas.drawPath(check, _traco(CoresTrato.superficie, 4.5));
  }

  /// Página 1: celular com 2 cards de pedido e ferramenta (chave de boca) ao lado.
  void _desenharPedidos(Canvas canvas) {
    canvas.drawCircle(const Offset(106, 114), 84, _preencher(CoresTrato.azulSuave));
    canvas.drawCircle(const Offset(178, 54), 9, _preencher(CoresTrato.ambarSuave));

    // Corpo do celular.
    final celular = RRect.fromRectAndRadius(
      const Rect.fromLTWH(38, 28, 108, 166),
      const Radius.circular(22),
    );
    canvas.drawRRect(celular, _preencher(CoresTrato.petroleo));

    // Tela interna.
    final tela = RRect.fromRectAndRadius(
      const Rect.fromLTWH(46, 44, 92, 134),
      const Radius.circular(14),
    );
    canvas.drawRRect(tela, _preencher(CoresTrato.creme));

    // Alto-falante superior e indicador inferior.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 34, 28, 4),
        const Radius.circular(2),
      ),
      _preencher(CoresTrato.pontoSobrePetroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(76, 184, 32, 4),
        const Radius.circular(2),
      ),
      _preencher(CoresTrato.pontoSobrePetroleo),
    );

    // Card de pedido 1.
    _desenharCardPedido(
      canvas,
      topo: 56,
      destaque: CoresTrato.laranja,
      etiquetaFundo: CoresTrato.verdeSuave,
      etiquetaCor: CoresTrato.verdeTexto,
    );
    // Card de pedido 2.
    _desenharCardPedido(
      canvas,
      topo: 116,
      destaque: CoresTrato.logoAzul,
      etiquetaFundo: CoresTrato.ambarSuave,
      etiquetaCor: CoresTrato.ambarTexto,
    );

    // Ponto de novidade no canto do celular.
    canvas.drawCircle(const Offset(142, 34), 10, _preencher(CoresTrato.superficie));
    canvas.drawCircle(const Offset(142, 34), 7, _preencher(CoresTrato.laranja));

    // Chave de boca inclinada à direita.
    canvas.save();
    canvas.translate(168, 126);
    canvas.rotate(-0.42);

    // Cabo da chave.
    final cabo = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-11, -18, 22, 68),
      const Radius.circular(11),
    );
    canvas.drawRRect(cabo, _preencher(CoresTrato.laranja));
    canvas.drawRRect(cabo, _traco(CoresTrato.petroleo, 3));
    canvas.drawCircle(const Offset(0, 38), 4.5, _preencher(CoresTrato.superficie));

    // Cabeça da chave com boca em U.
    final cabeca = Path()
      ..addOval(Rect.fromCircle(center: const Offset(0, -28), radius: 21));
    final recorte = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-8, -54, 16, 26),
          const Radius.circular(6),
        ),
      );
    final boca = Path.combine(PathOperation.difference, cabeca, recorte);
    canvas.drawPath(boca, _preencher(CoresTrato.superficie));
    canvas.drawPath(boca, _traco(CoresTrato.petroleo, 3));

    canvas.restore();
  }

  void _desenharCardPedido(
    Canvas canvas, {
    required double topo,
    required Color destaque,
    required Color etiquetaFundo,
    required Color etiquetaCor,
  }) {
    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(54, topo, 76, 50),
      const Radius.circular(10),
    );
    canvas.drawRRect(card, _preencher(CoresTrato.superficie));
    canvas.drawRRect(card, _traco(CoresTrato.borda, 1.5));

    canvas.drawCircle(Offset(66, topo + 16), 6, _preencher(destaque));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(78, topo + 11, 42, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.petroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(78, topo + 21, 30, 5),
        const Radius.circular(2.5),
      ),
      _preencher(CoresTrato.bordaControle),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(60, topo + 33, 32, 9),
        const Radius.circular(4.5),
      ),
      _preencher(etiquetaFundo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(66, topo + 36, 20, 3),
        const Radius.circular(1.5),
      ),
      _preencher(etiquetaCor),
    );
  }

  /// Página 2: carteira com moeda/cifrão vetorial e seta entrando (sem texto de taxa).
  void _desenharCarteira(Canvas canvas) {
    canvas.drawCircle(const Offset(110, 118), 84, _preencher(CoresTrato.azulSuave));

    // Aba traseira da carteira (abertura superior).
    final abaTraseira = RRect.fromRectAndRadius(
      const Rect.fromLTWH(44, 92, 132, 34),
      const Radius.circular(14),
    );
    canvas.drawRRect(abaTraseira, _preencher(CoresTrato.azulTexto));
    canvas.drawRRect(abaTraseira, _traco(CoresTrato.petroleo, 3));

    // Moeda com cifrão geométrico (sem TextPainter) acima da carteira.
    const centroMoeda = Offset(94, 62);
    canvas.drawCircle(centroMoeda, 28, _preencher(CoresTrato.moedaOuro));
    canvas.drawCircle(centroMoeda, 28, _traco(CoresTrato.moedaOuroEscuro, 3));
    canvas.drawCircle(centroMoeda, 21, _preencher(CoresTrato.moedaOuroClaro));
    _desenharCifraoVetorial(canvas, centroMoeda);

    // Seta verde entrando na carteira à direita da moeda.
    canvas.drawCircle(const Offset(152, 68), 20, _preencher(CoresTrato.verdeSuave));
    final hasteSeta = Path()
      ..moveTo(152, 54)
      ..lineTo(152, 84);
    final pontaSeta = Path()
      ..moveTo(143, 75)
      ..lineTo(152, 85)
      ..lineTo(161, 75);
    canvas.drawPath(hasteSeta, _traco(CoresTrato.verdeTexto, 4.5));
    canvas.drawPath(pontaSeta, _traco(CoresTrato.verdeTexto, 4.5));

    // Corpo frontal da carteira.
    final carteira = RRect.fromRectAndRadius(
      const Rect.fromLTWH(36, 106, 146, 80),
      const Radius.circular(18),
    );
    canvas.drawRRect(carteira, _preencher(CoresTrato.petroleo));

    // Linha decorativa interna da costura.
    final costura = RRect.fromRectAndRadius(
      const Rect.fromLTWH(44, 114, 130, 64),
      const Radius.circular(12),
    );
    canvas.drawRRect(costura, _traco(CoresTrato.pontoSobrePetroleo, 2));

    // Fecho lateral da carteira.
    final fecho = RRect.fromRectAndRadius(
      const Rect.fromLTWH(138, 132, 50, 28),
      const Radius.circular(12),
    );
    canvas.drawRRect(fecho, _preencher(CoresTrato.superficie));
    canvas.drawRRect(fecho, _traco(CoresTrato.petroleo, 3));
    canvas.drawCircle(const Offset(154, 146), 6, _preencher(CoresTrato.laranja));
  }

  /// Desenha o símbolo de cifrão como curva vetorial pura (sem texto).
  void _desenharCifraoVetorial(Canvas canvas, Offset c) {
    final traco = _traco(CoresTrato.moedaOuroProfundo, 3.2);
    // Barra vertical central.
    canvas.drawLine(Offset(c.dx, c.dy - 14), Offset(c.dx, c.dy + 14), traco);
    // Curva em S.
    final curva = Path()
      ..moveTo(c.dx + 7, c.dy - 7)
      ..cubicTo(c.dx + 7, c.dy - 12, c.dx - 7, c.dy - 12, c.dx - 7, c.dy - 5)
      ..cubicTo(c.dx - 7, c.dy + 1, c.dx + 7, c.dy - 1, c.dx + 7, c.dy + 5)
      ..cubicTo(c.dx + 7, c.dy + 12, c.dx - 7, c.dy + 12, c.dx - 7, c.dy + 7);
    canvas.drawPath(curva, traco);
  }

  /// Página 3: moeda/estrela dos Tratinhos com brilho e relógio simples ao lado.
  void _desenharTratinhos(Canvas canvas) {
    canvas.drawCircle(const Offset(110, 114), 86, _preencher(CoresTrato.azulSuave));

    // Moeda dos Tratinhos à esquerda.
    const centroMoeda = Offset(86, 108);
    canvas.drawCircle(
      const Offset(90, 112),
      46,
      _preencher(CoresTrato.moedaOuroEscuro),
    );
    canvas.drawCircle(centroMoeda, 46, _preencher(CoresTrato.moedaOuro));
    canvas.drawCircle(centroMoeda, 46, _traco(CoresTrato.moedaOuroEscuro, 3));
    canvas.drawCircle(centroMoeda, 36, _preencher(CoresTrato.moedaOuroClaro));

    // Estrela de 5 pontas no centro da moeda.
    _desenharEstrela(canvas, centroMoeda, raioExterno: 20, raioInterno: 9.5);

    // Brilhos (sparkles de 4 pontas) ao redor da moeda.
    _desenharBrilho(canvas, const Offset(40, 56), 11, CoresTrato.moedaOuroClaro);
    _desenharBrilho(canvas, const Offset(118, 46), 9, CoresTrato.laranja);
    _desenharBrilho(canvas, const Offset(44, 162), 8, CoresTrato.superficie);

    // Relógio simples de 48h ao lado (círculo com coroa, arco e ponteiros, sem texto).
    const centroRelogio = Offset(156, 134);
    const raioRelogio = 36.0;

    // Coroa superior do relógio.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(148, 88, 16, 10),
        const Radius.circular(4),
      ),
      _preencher(CoresTrato.petroleo),
    );

    // Corpo e mostrador.
    canvas.drawCircle(centroRelogio, raioRelogio + 4, _preencher(CoresTrato.superficie));
    canvas.drawCircle(centroRelogio, raioRelogio, _preencher(CoresTrato.superficie));
    canvas.drawCircle(centroRelogio, raioRelogio, _traco(CoresTrato.petroleo, 3.5));

    // Arco de ciclo em laranja.
    canvas.drawArc(
      Rect.fromCircle(center: centroRelogio, radius: raioRelogio - 7),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      _traco(CoresTrato.laranja, 3.5),
    );

    // Quatro marcações simples de hora.
    final marca = _traco(CoresTrato.bordaControle, 2.5);
    canvas.drawLine(const Offset(156, 105), const Offset(156, 110), marca);
    canvas.drawLine(const Offset(156, 158), const Offset(156, 163), marca);
    canvas.drawLine(const Offset(127, 134), const Offset(132, 134), marca);
    canvas.drawLine(const Offset(180, 134), const Offset(185, 134), marca);

    // Ponteiros do relógio.
    final ponteiro = _traco(CoresTrato.petroleo, 4);
    canvas.drawLine(centroRelogio, const Offset(156, 115), ponteiro);
    canvas.drawLine(centroRelogio, const Offset(172, 141), ponteiro);
    canvas.drawCircle(centroRelogio, 4.5, _preencher(CoresTrato.laranja));
  }

  void _desenharEstrela(
    Canvas canvas,
    Offset centro, {
    required double raioExterno,
    required double raioInterno,
  }) {
    final caminho = Path();
    const pontas = 5;
    for (var i = 0; i < pontas * 2; i++) {
      final raio = i.isEven ? raioExterno : raioInterno;
      final angulo = -math.pi / 2 + i * math.pi / pontas;
      final x = centro.dx + raio * math.cos(angulo);
      final y = centro.dy + raio * math.sin(angulo);
      if (i == 0) {
        caminho.moveTo(x, y);
      } else {
        caminho.lineTo(x, y);
      }
    }
    caminho.close();
    canvas.drawPath(caminho, _preencher(CoresTrato.moedaOuroProfundo));
  }

  void _desenharBrilho(Canvas canvas, Offset centro, double raio, Color cor) {
    final interno = raio * 0.28;
    final caminho = Path()
      ..moveTo(centro.dx, centro.dy - raio)
      ..quadraticBezierTo(centro.dx + interno, centro.dy - interno, centro.dx + raio, centro.dy)
      ..quadraticBezierTo(centro.dx + interno, centro.dy + interno, centro.dx, centro.dy + raio)
      ..quadraticBezierTo(centro.dx - interno, centro.dy + interno, centro.dx - raio, centro.dy)
      ..quadraticBezierTo(centro.dx - interno, centro.dy - interno, centro.dx, centro.dy - raio)
      ..close();
    canvas.drawPath(caminho, _preencher(cor));
  }

  @override
  bool shouldRepaint(covariant _PintorIlustracaoProfissional oldDelegate) =>
      oldDelegate.pagina != pagina;
}
