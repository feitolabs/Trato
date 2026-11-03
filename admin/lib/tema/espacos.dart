// Espaços, raios e tamanhos do painel admin (DS v2, seção 3.3). Ver LEIA-ME.md.

/// Base de 4 px; escala 4, 8, 12, 16, 24, 32. Cards: 16 de padding e 12 de intervalo.
abstract final class EspacosTrato {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;

  static const double paddingCartao = 16;
  static const double intervaloCartoes = 12;

  /// Campos, botões e cards: 12. Modais: 24. Chips: totalmente arredondados.
  static const double raioPequeno = 8;
  static const double raio = 12;
  static const double raioGrande = 12;
  static const double raioModal = 24;
  static const double raioPilula = 999;

  /// Área de toque mínima: 44 px (botão do DS e RNF-01).
  static const double alturaBotao = 44;
  static const double alturaCampo = 48;
  static const double bordaFina = 1;
  static const double aneldeFoco = 2;

  /// Menu lateral fixo de ~240 px; conteúdo fluido com no máximo 1200 px.
  static const double larguraMenu = 240;
  static const double larguraMenuRecolhido = 72;
  static const double larguraMaximaConteudo = 1200;
}
