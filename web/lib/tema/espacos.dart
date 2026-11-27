/// Espaços, raios e tamanhos do protótipo, em dp (ver docs/design-tokens.md).
abstract final class EspacosTrato {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;

  static const double margemTela = 16;
  static const double margemTelaDensa = 16;
  static const double margemOnboarding = 24;

  static const double raioPequeno = 8;
  static const double raio = 12;
  static const double raioGrande = 16;
  static const double raioPilula = 999;

  static const double alturaBotao = 52;
  static const double alturaCampo = 52;
  static const double bordaFina = 1;
  static const double bordaControle = 1.5;

  /// Padding interno de cartões (protótipo: 16).
  static const double paddingCartao = 16;

  /// Altura de uma linha de lista em cartão ("Dados pessoais", extrato), sem o divisor.
  static const double alturaLinhaLista = 51;
}
