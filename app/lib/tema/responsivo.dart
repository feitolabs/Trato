import 'package:flutter/widgets.dart';

import 'espacos.dart';

/// Faixas de largura de tela (dp). O protótipo foi desenhado em 390.
enum TamanhoTela {
  /// Até 359 dp (ex.: iPhone SE 1ª geração, Androids compactos).
  pequeno,

  /// 360 a 599 dp: a maioria dos celulares.
  celular,

  /// 600 dp ou mais: tablets e celulares dobráveis abertos.
  tablet;

  static const limitePequeno = 360.0;
  static const limiteTablet = 600.0;

  static TamanhoTela daLargura(double largura) {
    if (largura < limitePequeno) return pequeno;
    if (largura < limiteTablet) return celular;
    return tablet;
  }

  static TamanhoTela de(BuildContext context) => daLargura(MediaQuery.sizeOf(context).width);
}

abstract final class Responsivo {
  /// Largura máxima do conteúdo no tablet: mantém a leitura no tamanho do protótipo.
  static const larguraMaximaConteudo = 560.0;

  /// Faixa de escala de fonte aceita. Respeita a acessibilidade do aparelho,
  /// mas limita para o layout não quebrar.
  static const escalaFonteMinima = 0.9;
  static const escalaFonteMaxima = 1.3;

  static double margemLateral(TamanhoTela tamanho) => switch (tamanho) {
        TamanhoTela.pequeno => EspacosTrato.margemTelaDensa,
        TamanhoTela.celular => EspacosTrato.margemTela,
        TamanhoTela.tablet => EspacosTrato.x8,
      };
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

/// Centraliza o conteúdo da tela e aplica a margem lateral do tamanho atual.
/// No tablet, o conteúdo fica com no máximo [Responsivo.larguraMaximaConteudo].
class ConteudoResponsivo extends StatelessWidget {
  const ConteudoResponsivo({
    super.key,
    required this.child,
    this.comMargem = true,
    this.margem,
  });

  final Widget child;
  final bool comMargem;

  /// Margem fixa (ex.: 24 no onboarding e no login, como no protótipo). Em tablet vale a do tamanho.
  final double? margem;

  @override
  Widget build(BuildContext context) {
    final tamanho = TamanhoTela.de(context);
    final margem = !comMargem
        ? 0.0
        : (this.margem != null && tamanho == TamanhoTela.celular)
            ? this.margem!
            : Responsivo.margemLateral(tamanho);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsivo.larguraMaximaConteudo + margem * 2),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: margem),
          child: child,
        ),
      ),
    );
  }
}
