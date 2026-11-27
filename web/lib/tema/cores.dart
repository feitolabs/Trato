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

  /// Fundo e sobreposições para visualização de fotos.
  static const fundoModalFoto = Color(0xDE000000);
  static const fundoFotoPreto = Color(0xFF000000);
  static const overlayFoto = Color(0x8A000000);
  static const textoSobreFoto = Color(0xFFFFFFFF);

  /// Só no site web: fim do gradiente do painel de marca e véus brancos sobre o petróleo.
  static const petroleoProfundo = Color(0xFF0A2A31);
  static const veuGrade = Color.from(alpha: 0.05, red: 1, green: 1, blue: 1);
  static const veuCartao = Color.from(alpha: 0.06, red: 1, green: 1, blue: 1);
  static const veuIcone = Color.from(alpha: 0.08, red: 1, green: 1, blue: 1);
  static const veuTracejado = Color.from(alpha: 0.10, red: 1, green: 1, blue: 1);

  /// Moeda do Trato (gamificação): ouro da borda, da face e do relevo.
  static const moedaOuroClaro = Color(0xFFFFE9A6);
  static const moedaOuro = Color(0xFFF2B632);
  static const moedaOuroEscuro = Color(0xFFB87408);
  static const moedaOuroProfundo = Color(0xFF7A4A00);

  /// Toast/SnackBar elevado e distinto do botão primário no modo claro.
  static const toastFundo = Color(0xFF182B31);
  static const toastTexto = Color(0xFFF4F1E8);
  static const toastBorda = Color(0xFF2F4E57);
}

/// Paleta semântica usada em runtime pelo tema escuro (alto contraste e profundidade).
abstract final class CoresTratoEscuro {
  static const petroleo = Color(0xFF7FD0DD);
  static const sobrePetroleo = Color(0xFF08181D);
  static const fundo = Color(0xFF0B1317);
  static const superficie = Color(0xFF15242B);
  static const borda = Color(0xFF27414B);
  static const bordaControle = Color(0xFF3E626E);

  static const azulSuave = Color(0xFF1A3D47);
  static const azulTexto = Color(0xFF8AD7E3);

  static const laranja = Color(0xFFFF9457);

  static const ambarSuave = Color(0xFF3B2B12);
  static const ambarTexto = Color(0xFFF6C96E);

  static const verdeSuave = Color(0xFF163826);
  static const verdeTexto = Color(0xFF82DDA0);

  static const vermelhoSuave = Color(0xFF421C1B);
  static const vermelhoTexto = Color(0xFFF69088);

  static const texto = Color(0xFFF4F1E8);
  static const textoSecundario = Color(0xFFB8CCCB);
  static const textoDica = Color(0xFF8AA3A3);

  /// Toast/SnackBar elevado com contraste nítido no modo escuro.
  static const toastFundo = Color(0xFF1E343D);
  static const toastTexto = Color(0xFFF4F1E8);
  static const toastBorda = bordaControle;
}
