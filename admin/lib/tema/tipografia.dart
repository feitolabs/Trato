// Estilos de texto do painel admin (DS v2, seção 3.2). Ver LEIA-ME.md.

import 'package:flutter/painting.dart';

import 'cores.dart';

/// Bricolage Grotesque 800 em títulos e números de destaque; Hanken Grotesk em toda a interface.
/// Nenhum texto abaixo de 12 px. Valores em R$ usam numerais tabulares.
abstract final class TipografiaTrato {
  static const fonteTitulos = 'Bricolage';
  static const fonteCorpo = 'Hanken';

  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _estilo(
    String familia,
    double tamanho,
    int peso, {
    double? linha,
    double? espacamento,
    Color cor = CoresTrato.textoPadrao,
    bool tabular = false,
  }) {
    return TextStyle(
      fontFamily: familia,
      fontSize: tamanho,
      fontWeight: FontWeight.values[(peso ~/ 100) - 1],
      fontVariations: [FontVariation('wght', peso.toDouble())],
      // O DS dá a altura de linha em px (ex.: 20/26): height é a razão.
      height: linha == null ? null : linha / tamanho,
      letterSpacing: espacamento,
      color: cor,
      fontFeatures: tabular ? _tabular : null,
    );
  }

  // ---- Níveis do DS (--trato-type-*) ----

  /// Título de página: Bricolage 800 · 20/26 · -0,01em.
  static final titulo = _estilo(fonteTitulos, 20, 800, linha: 26, espacamento: -0.2);

  /// Subtítulo de página: Hanken 400 · 13/18 · muted.
  static final subtitulo = _estilo(fonteCorpo, 13, 400, linha: 18, cor: CoresTrato.textoMudo);

  /// Título de seção ou card: Bricolage 800 · 16/22.
  static final secao = _estilo(fonteTitulos, 16, 800, linha: 22);

  /// Corpo: Hanken 400 · 14/20.
  static final corpo = _estilo(fonteCorpo, 14, 400, linha: 20);

  /// Corpo forte: Hanken 700 · 14/20.
  static final corpoForte = _estilo(fonteCorpo, 14, 700, linha: 20);

  /// Dado destacado: Bricolage 800 · 24/30 · tabular.
  static final valor = _estilo(fonteTitulos, 24, 800, linha: 30, tabular: true);

  /// Legenda e etiqueta: Hanken 700 · 12/16 (mínimo do painel).
  static final etiqueta = _estilo(fonteCorpo, 12, 700, linha: 16);

  /// Legenda: Hanken 400 · 12/16 · muted (datas, textos de apoio).
  static final legenda = _estilo(fonteCorpo, 12, 400, linha: 16, cor: CoresTrato.textoMudo);

  /// Valores em R$ nas listas e no extrato: corpo com numerais tabulares.
  static final numeroTabular = _estilo(fonteCorpo, 14, 400, linha: 20, tabular: true);

  /// Sobretítulo de seção do menu ("OPERAÇÃO"): caixa-alta, espaçado, 12 px.
  static final sobretitulo = _estilo(
    fonteCorpo,
    12,
    700,
    linha: 16,
    espacamento: 1.2,
    cor: CoresTrato.textoMudo,
  );

  // ---- Nomes antigos (apontam para os níveis acima) ----

  static final marca = _estilo(fonteTitulos, 40, 800, linha: 44, espacamento: -1);
  static final marcaPequena = _estilo(fonteTitulos, 20, 800, linha: 24, espacamento: -0.2);
  static final lema = corpo;
  static final corpoGrande = corpo;
  static final tituloOpcao = secao;
  static final tituloGrande = valor;
  static final tituloCartao = secao;
  static final corpoPequeno = corpo;
}
