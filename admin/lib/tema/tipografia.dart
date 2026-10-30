// CÓPIA de app/lib/tema/tipografia.dart. Não edite aqui: mude no app e copie de novo.
// Origem e regra: admin/lib/tema/LEIA-ME.md.

import 'package:flutter/painting.dart';

import 'cores.dart';

/// Estilos de texto do protótipo (ver docs/design-tokens.md).
/// As fontes são variáveis: o peso vai em [FontWeight] e no eixo `wght`.
abstract final class TipografiaTrato {
  static const fonteTitulos = 'Archivo';
  static const fonteCorpo = 'Figtree';

  static TextStyle _estilo(
    String familia,
    double tamanho,
    int peso, {
    double? altura,
    double? espacamento,
    Color cor = CoresTrato.petroleo,
  }) {
    return TextStyle(
      fontFamily: familia,
      fontSize: tamanho,
      fontWeight: FontWeight.values[(peso ~/ 100) - 1],
      fontVariations: [FontVariation('wght', peso.toDouble())],
      height: altura,
      letterSpacing: espacamento,
      color: cor,
    );
  }

  static final marca = _estilo(fonteTitulos, 72, 900, altura: 1, espacamento: -2);
  static final lema = _estilo(fonteCorpo, 18, 400, altura: 1.4);
  static final marcaPequena = _estilo(fonteTitulos, 24, 800, altura: 1, espacamento: -0.5);
  static final corpoGrande = _estilo(fonteCorpo, 17, 400, altura: 1.65);
  static final tituloOpcao = _estilo(fonteTitulos, 20, 800, altura: 1.2, espacamento: -0.2);
  static final tituloGrande = _estilo(fonteTitulos, 28, 800, altura: 1.15, espacamento: -0.4);
  static final titulo = _estilo(fonteTitulos, 22, 800, altura: 1.2, espacamento: -0.2);
  static final tituloCartao = _estilo(fonteCorpo, 17, 700, altura: 1.3);
  static final corpo = _estilo(fonteCorpo, 16, 400, altura: 1.5);
  static final corpoForte = _estilo(fonteCorpo, 16, 700, altura: 1.3);
  static final corpoPequeno = _estilo(fonteCorpo, 14, 400, altura: 1.4);
  static final legenda = _estilo(
    fonteCorpo,
    13,
    400,
    altura: 1.4,
    cor: CoresTrato.textoSecundario,
  );
  static final sobretitulo = _estilo(
    fonteCorpo,
    13,
    700,
    espacamento: 1.5,
    cor: CoresTrato.textoSecundario,
  );
}
