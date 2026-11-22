import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Ilustrações vetoriais do onboarding do cliente (4 páginas, desenhadas em código).
/// Sem imagens, sem texto interno e usando somente a paleta [CoresTrato].
class IlustracaoOnboardingCliente extends StatelessWidget {
  const IlustracaoOnboardingCliente({
    super.key,
    required this.pagina,
    this.tamanho = 220,
  });

  final int pagina;
  final double tamanho;

  static const _rotulos = <String>[
    'Ilustração: conte o que você precisa pelo celular',
    'Ilustração: compare três orçamentos e escolha o melhor',
    'Ilustração: pague com segurança e proteção',
    'Ilustração: avalie com cinco estrelas e ganhe Tratinhos',
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
          painter: _PintorIlustracaoCliente(pagina),
        ),
      ),
    );
  }
}

class _PintorIlustracaoCliente extends CustomPainter {
  const _PintorIlustracaoCliente(this.pagina);

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
        _desenharPedido(canvas);
      case 1:
        _desenharComparacao(canvas);
      case 2:
        _desenharPagamento(canvas);
      case 3:
        _desenharAvaliacao(canvas);
    }

    canvas.restore();
  }

  /// Página 0: celular com formulário curto, balão de mensagem e lápis.
  void _desenharPedido(Canvas canvas) {
    canvas.drawCircle(const Offset(108, 114), 85, _preencher(CoresTrato.azulSuave));
    canvas.drawCircle(const Offset(178, 166), 8, _preencher(CoresTrato.ambarSuave));

    // Corpo do celular.
    final celular = RRect.fromRectAndRadius(
      const Rect.fromLTWH(34, 30, 106, 164),
      const Radius.circular(22),
    );
    canvas.drawRRect(celular, _preencher(CoresTrato.petroleo));

    // Tela interna.
    final tela = RRect.fromRectAndRadius(
      const Rect.fromLTWH(42, 46, 90, 132),
      const Radius.circular(14),
    );
    canvas.drawRRect(tela, _preencher(CoresTrato.creme));

    // Alto-falante e indicador inferior.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(73, 36, 28, 4),
        const Radius.circular(2),
      ),
      _preencher(CoresTrato.pontoSobrePetroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(71, 184, 32, 4),
        const Radius.circular(2),
      ),
      _preencher(CoresTrato.pontoSobrePetroleo),
    );

    // Formulário curto dentro da tela.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(52, 58, 46, 7),
        const Radius.circular(3.5),
      ),
      _preencher(CoresTrato.petroleo),
    );
    // Campo 1.
    final campo1 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(52, 72, 70, 22),
      const Radius.circular(7),
    );
    canvas.drawRRect(campo1, _preencher(CoresTrato.superficie));
    canvas.drawRRect(campo1, _traco(CoresTrato.borda, 1.5));
    canvas.drawCircle(const Offset(62, 83), 4, _preencher(CoresTrato.laranja));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(71, 80, 40, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.bordaControle),
    );

    // Campo 2 (descrição curta).
    final campo2 = RRect.fromRectAndRadius(
      const Rect.fromLTWH(52, 102, 70, 38),
      const Radius.circular(8),
    );
    canvas.drawRRect(campo2, _preencher(CoresTrato.superficie));
    canvas.drawRRect(campo2, _traco(CoresTrato.borda, 1.5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 112, 52, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.petroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 124, 38, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.bordaControle),
    );

    // Botão inferior do formulário.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(52, 149, 70, 18),
        const Radius.circular(9),
      ),
      _preencher(CoresTrato.petroleo),
    );

    // Balão de mensagem saindo no topo direito (contorno contínuo sem costura).
    final balao = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(108, 34, 78, 48),
          const Radius.circular(14),
        ),
      );
    final rabinho = Path()
      ..moveTo(120, 76)
      ..lineTo(111, 93)
      ..lineTo(135, 80)
      ..close();
    final balaoUnido = Path.combine(PathOperation.union, balao, rabinho);
    canvas.drawPath(balaoUnido, _preencher(CoresTrato.superficie));
    canvas.drawPath(balaoUnido, _traco(CoresTrato.petroleo, 3));
    // Duas linhas dentro do balão.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(122, 48, 50, 7),
        const Radius.circular(3.5),
      ),
      _preencher(CoresTrato.petroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(122, 61, 34, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.logoAzul),
    );

    // Lápis inclinado ao lado direito.
    canvas.save();
    canvas.translate(172, 134);
    canvas.rotate(0.58);

    // Borracha superior.
    final borracha = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-10, -44, 20, 14),
      const Radius.circular(6),
    );
    canvas.drawRRect(borracha, _preencher(CoresTrato.ambarSuave));
    canvas.drawRRect(borracha, _traco(CoresTrato.petroleo, 2.8));

    // Virola metálica.
    final virola = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-10, -33, 20, 10),
      const Radius.circular(2),
    );
    canvas.drawRRect(virola, _preencher(CoresTrato.superficie));
    canvas.drawRRect(virola, _traco(CoresTrato.petroleo, 2.8));

    // Corpo do lápis.
    final corpoLapis = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-10, -23, 20, 48),
      const Radius.circular(3),
    );
    canvas.drawRRect(corpoLapis, _preencher(CoresTrato.laranja));
    canvas.drawRRect(corpoLapis, _traco(CoresTrato.petroleo, 2.8));

    // Ponta de madeira + grafite.
    final ponta = Path()
      ..moveTo(-10, 25)
      ..lineTo(10, 25)
      ..lineTo(0, 45)
      ..close();
    canvas.drawPath(ponta, _preencher(CoresTrato.creme));
    canvas.drawPath(ponta, _traco(CoresTrato.petroleo, 2.8));

    final grafite = Path()
      ..moveTo(-4, 37)
      ..lineTo(4, 37)
      ..lineTo(0, 45)
      ..close();
    canvas.drawPath(grafite, _preencher(CoresTrato.petroleo));

    canvas.restore();
  }

  /// Página 1: 3 cartões de orçamento lado a lado, o do meio destacado com check.
  void _desenharComparacao(Canvas canvas) {
    canvas.drawCircle(const Offset(110, 116), 86, _preencher(CoresTrato.azulSuave));

    // Cartões laterais (esquerda e direita).
    _desenharCartaoLateral(canvas, esquerda: 20, bolinha: CoresTrato.logoAzul);
    _desenharCartaoLateral(canvas, esquerda: 146, bolinha: CoresTrato.laranja);

    // Sombra plana do cartão central.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(72, 56, 82, 126),
        const Radius.circular(16),
      ),
      _preencher(CoresTrato.logoAzulClaro),
    );

    // Cartão do meio destacado.
    final centro = RRect.fromRectAndRadius(
      const Rect.fromLTWH(68, 50, 84, 126),
      const Radius.circular(16),
    );
    canvas.drawRRect(centro, _preencher(CoresTrato.superficie));
    canvas.drawRRect(centro, _traco(CoresTrato.petroleo, 3.2));

    // Cabeçalho suave e linhas de orçamento no cartão central.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 62, 42, 12),
        const Radius.circular(6),
      ),
      _preencher(CoresTrato.verdeSuave),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 84, 62, 10),
        const Radius.circular(5),
      ),
      _preencher(CoresTrato.petroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 102, 52, 7),
        const Radius.circular(3.5),
      ),
      _preencher(CoresTrato.bordaControle),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 115, 44, 7),
        const Radius.circular(3.5),
      ),
      _preencher(CoresTrato.bordaControle),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 132, 64, 10),
        const Radius.circular(5),
      ),
      _preencher(CoresTrato.ambarSuave),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 150, 64, 16),
        const Radius.circular(8),
      ),
      _preencher(CoresTrato.petroleo),
    );

    // Selo de check no canto superior direito do cartão central.
    const centroSelo = Offset(146, 52);
    canvas.drawCircle(centroSelo, 22, _preencher(CoresTrato.superficie));
    canvas.drawCircle(centroSelo, 18, _preencher(CoresTrato.verdeTexto));
    final check = Path()
      ..moveTo(138, 52)
      ..lineTo(144, 58)
      ..lineTo(155, 46);
    canvas.drawPath(check, _traco(CoresTrato.superficie, 4));
  }

  void _desenharCartaoLateral(
    Canvas canvas, {
    required double esquerda,
    required Color bolinha,
  }) {
    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(esquerda, 70, 54, 100),
      const Radius.circular(12),
    );
    canvas.drawRRect(card, _preencher(CoresTrato.creme));
    canvas.drawRRect(card, _traco(CoresTrato.bordaControle, 2));

    canvas.drawCircle(Offset(esquerda + 16, 88), 7, _preencher(bolinha));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(esquerda + 10, 104, 34, 7),
        const Radius.circular(3.5),
      ),
      _preencher(CoresTrato.textoSecundario),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(esquerda + 10, 118, 26, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.bordaControle),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(esquerda + 10, 130, 30, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.bordaControle),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(esquerda + 10, 146, 34, 13),
        const Radius.circular(6.5),
      ),
      _preencher(CoresTrato.borda),
    );
  }

  /// Página 2: cartão de pagamento com cadeado de segurança.
  void _desenharPagamento(Canvas canvas) {
    canvas.drawCircle(const Offset(110, 114), 86, _preencher(CoresTrato.azulSuave));
    canvas.drawCircle(const Offset(44, 54), 9, _preencher(CoresTrato.creme));

    // Sombra plana do cartão.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(32, 68, 150, 96),
        const Radius.circular(18),
      ),
      _preencher(CoresTrato.logoAzulClaro),
    );

    // Cartão principal.
    final cartao = RRect.fromRectAndRadius(
      const Rect.fromLTWH(28, 62, 150, 96),
      const Radius.circular(18),
    );
    canvas.drawRRect(cartao, _preencher(CoresTrato.petroleo));

    // Faixa superior sutil do cartão.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 76, 150, 14),
        const Radius.circular(2),
      ),
      _preencher(CoresTrato.azulTexto),
    );

    // Chip dourado do cartão.
    final chip = RRect.fromRectAndRadius(
      const Rect.fromLTWH(44, 100, 28, 22),
      const Radius.circular(5),
    );
    canvas.drawRRect(chip, _preencher(CoresTrato.moedaOuro));
    canvas.drawRRect(chip, _traco(CoresTrato.moedaOuroEscuro, 1.8));
    canvas.drawLine(
      const Offset(44, 111),
      const Offset(72, 111),
      _traco(CoresTrato.moedaOuroEscuro, 1.5),
    );
    canvas.drawLine(
      const Offset(58, 100),
      const Offset(58, 122),
      _traco(CoresTrato.moedaOuroEscuro, 1.5),
    );

    // Blocos simbólicos no cartão (sem dígitos ou texto).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 134, 24, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.logoAzulClaro),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(76, 134, 24, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.logoAzulClaro),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(108, 134, 20, 6),
        const Radius.circular(3),
      ),
      _preencher(CoresTrato.pontoSobrePetroleo),
    );

    // Bandeira decorativa (dois círculos sobrepostos no espaço livre do cartão).
    canvas.drawCircle(const Offset(104, 111), 9.5, _preencher(CoresTrato.laranja));
    canvas.drawCircle(const Offset(115, 111), 9.5, _preencher(CoresTrato.moedaOuro));

    // Cadeado de segurança em destaque no canto inferior direito.
    // Manilha (arco) com contorno claro para destacar sobre o cartão.
    final arco = Path()
      ..moveTo(142, 128)
      ..lineTo(142, 114)
      ..arcToPoint(
        const Offset(174, 114),
        radius: const Radius.circular(16),
      )
      ..lineTo(174, 128);
    canvas.drawPath(arco, _traco(CoresTrato.superficie, 12));
    canvas.drawPath(arco, _traco(CoresTrato.petroleo, 6));

    // Halo externo e corpo do cadeado.
    final haloCadeado = RRect.fromRectAndRadius(
      const Rect.fromLTWH(124, 122, 68, 58),
      const Radius.circular(15),
    );
    canvas.drawRRect(haloCadeado, _preencher(CoresTrato.superficie));

    final corpoCadeado = RRect.fromRectAndRadius(
      const Rect.fromLTWH(129, 127, 58, 48),
      const Radius.circular(12),
    );
    canvas.drawRRect(corpoCadeado, _preencher(CoresTrato.verdeTexto));

    // Fechadura central do cadeado.
    canvas.drawCircle(const Offset(158, 146), 6.5, _preencher(CoresTrato.superficie));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(154.5, 149, 7, 13),
        const Radius.circular(3.5),
      ),
      _preencher(CoresTrato.superficie),
    );
  }

  /// Página 3: 5 estrelas de avaliação e uma moeda dos Tratinhos com estrela ao lado.
  void _desenharAvaliacao(Canvas canvas) {
    canvas.drawCircle(const Offset(110, 114), 86, _preencher(CoresTrato.azulSuave));

    // Sombra plana do cartão de avaliação.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(26, 56, 138, 84),
        const Radius.circular(18),
      ),
      _preencher(CoresTrato.logoAzulClaro),
    );

    // Cartão de avaliação com 5 estrelas.
    final cartao = RRect.fromRectAndRadius(
      const Rect.fromLTWH(22, 50, 138, 84),
      const Radius.circular(18),
    );
    canvas.drawRRect(cartao, _preencher(CoresTrato.superficie));
    canvas.drawRRect(cartao, _traco(CoresTrato.petroleo, 3));

    // Fileira de 5 estrelas preenchidas.
    for (var i = 0; i < 5; i++) {
      _desenharEstrela(
        canvas,
        Offset(43 + i * 24.0, 80),
        raioExterno: 10.5,
        raioInterno: 4.8,
        cor: CoresTrato.laranja,
      );
    }

    // Duas linhas sutis de comentário abaixo das 5 estrelas.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(38, 102, 82, 8),
        const Radius.circular(4),
      ),
      _preencher(CoresTrato.petroleo),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(38, 116, 56, 7),
        const Radius.circular(3.5),
      ),
      _preencher(CoresTrato.bordaControle),
    );

    // Moeda dos Tratinhos com estrela ao lado direito inferior.
    const centroMoeda = Offset(154, 138);
    canvas.drawCircle(
      const Offset(158, 142),
      40,
      _preencher(CoresTrato.moedaOuroEscuro),
    );
    canvas.drawCircle(centroMoeda, 40, _preencher(CoresTrato.moedaOuro));
    canvas.drawCircle(centroMoeda, 40, _traco(CoresTrato.moedaOuroEscuro, 3));
    canvas.drawCircle(centroMoeda, 31, _preencher(CoresTrato.moedaOuroClaro));
    _desenharEstrela(
      canvas,
      centroMoeda,
      raioExterno: 17,
      raioInterno: 8,
      cor: CoresTrato.moedaOuroProfundo,
    );

    // Brilhos decorativos ao redor da moeda.
    _desenharBrilho(canvas, const Offset(182, 84), 10, CoresTrato.moedaOuro);
    _desenharBrilho(canvas, const Offset(108, 168), 8.5, CoresTrato.laranja);
    _desenharBrilho(canvas, const Offset(194, 110), 6.5, CoresTrato.moedaOuro);
  }

  void _desenharEstrela(
    Canvas canvas,
    Offset centro, {
    required double raioExterno,
    required double raioInterno,
    required Color cor,
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
    canvas.drawPath(caminho, _preencher(cor));
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
  bool shouldRepaint(covariant _PintorIlustracaoCliente oldDelegate) =>
      oldDelegate.pagina != pagina;
}
