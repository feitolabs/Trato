// Faixas de largura do painel admin (RNF-01). Ver LEIA-ME.md.

import 'package:flutter/widgets.dart';

import 'espacos.dart';

/// Três faixas: a partir de 1024 dp o menu lateral é fixo; de 768 a 1023 o menu fica recolhido só
/// com ícones; abaixo de 768 vira barra inferior com os cinco módulos mais usados e "Mais".
enum FaixaPainel {
  celular,
  tablet,
  desktop;

  static const limiteTablet = 768.0;
  static const limiteDesktop = 1024.0;

  static FaixaPainel daLargura(double largura) {
    if (largura < limiteTablet) return celular;
    if (largura < limiteDesktop) return tablet;
    return desktop;
  }

  static FaixaPainel de(BuildContext context) => daLargura(MediaQuery.sizeOf(context).width);

  bool get ehCelular => this == celular;
}

abstract final class Responsivo {
  /// Faixa de escala de fonte aceita. Respeita a acessibilidade do aparelho,
  /// mas limita para o layout não quebrar.
  static const escalaFonteMinima = 0.9;
  static const escalaFonteMaxima = 1.3;

  static double margemLateral(FaixaPainel faixa) =>
      faixa == FaixaPainel.celular ? EspacosTrato.x4 : EspacosTrato.x6;
}

/// Envolve o app: limita a escala de fonte do sistema à faixa suportada.
class EscalaFonteLimitada extends StatelessWidget {
  const EscalaFonteLimitada({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final midia = MediaQuery.of(context);
    return MediaQuery(
      data: midia.copyWith(
        textScaler: midia.textScaler.clamp(
          minScaleFactor: Responsivo.escalaFonteMinima,
          maxScaleFactor: Responsivo.escalaFonteMaxima,
        ),
      ),
      child: child,
    );
  }
}

/// Limita o conteúdo a 1200 dp e centraliza (grade da página, DS 3.3).
class ConteudoLimitado extends StatelessWidget {
  const ConteudoLimitado({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: EspacosTrato.larguraMaximaConteudo),
        child: child,
      ),
    );
  }
}
