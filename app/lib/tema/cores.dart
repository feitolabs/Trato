import 'package:flutter/painting.dart';

/// Paleta do Trato, medida no protótipo (ver docs/design-tokens.md).
/// Único lugar do app onde uma cor pode ser escrita.
abstract final class CoresTrato {
  static const petroleo = Color(0xFF0E3A43);
  static const creme = Color(0xFFF4EEE2);
  static const superficie = Color(0xFFFBF8F1);
  static const borda = Color(0xFFD8CFBE);

  /// Contorno de campos e botões secundários (mais escuro que o dos cartões; medido no protótipo).
  static const bordaControle = Color(0xFFA3ABA3);

  static const azulClaro = Color(0xFF8FC1C8);
  static const azulSuave = Color(0xFFDCEBEE);
  static const azulTexto = Color(0xFF0B6067);

  static const laranja = Color(0xFFFF8A4C);

  static const ambarSuave = Color(0xFFF8EBCB);
  static const ambarTexto = Color(0xFF7C5100);

  static const verdeSuave = Color(0xFFE3EFE5);
  static const verdeTexto = Color(0xFF22683C);

  static const vermelhoSuave = Color(0xFFF8E0DC);
  static const vermelhoTexto = Color(0xFF9C221B);

  static const textoSecundario = Color(0xFF485D5A);
  static const textoDica = Color(0xFF6B6A68);

  /// Ponto inativo do indicador de páginas sobre fundo petróleo (splash).
  static const pontoSobrePetroleo = Color(0xFF2A5A64);

  static const logoAzul = Color(0xFF60B3C3);
  static const logoAzulClaro = Color(0xFFA8D3DA);
}
