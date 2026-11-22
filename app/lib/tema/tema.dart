import 'package:flutter/material.dart';

import 'cores.dart';
import 'espacos.dart';
import 'tipografia.dart';

export 'controlador_tema.dart';
export 'cores.dart';
export 'espacos.dart';
export 'responsivo.dart';
export 'tipografia.dart';

/// Cores adaptáveis entre o tema claro e o escuro, expostas via [ThemeExtension].
@immutable
class CoresTemaTrato extends ThemeExtension<CoresTemaTrato> {
  const CoresTemaTrato({
    required this.petroleo,
    required this.sobrePetroleo,
    required this.fundo,
    required this.superficie,
    required this.borda,
    required this.bordaControle,
    required this.texto,
    required this.textoSecundario,
    required this.textoDica,
    required this.azulSuave,
    required this.azulTexto,
    required this.laranja,
    required this.ambarSuave,
    required this.ambarTexto,
    required this.verdeSuave,
    required this.verdeTexto,
    required this.vermelhoSuave,
    required this.vermelhoTexto,
  });

  final Color petroleo;
  final Color sobrePetroleo;
  final Color fundo;
  final Color superficie;
  final Color borda;
  final Color bordaControle;
  final Color texto;
  final Color textoSecundario;
  final Color textoDica;
  final Color azulSuave;
  final Color azulTexto;
  final Color laranja;
  final Color ambarSuave;
  final Color ambarTexto;
  final Color verdeSuave;
  final Color verdeTexto;
  final Color vermelhoSuave;
  final Color vermelhoTexto;

  static const claro = CoresTemaTrato(
    petroleo: CoresTrato.petroleo,
    sobrePetroleo: CoresTrato.creme,
    fundo: CoresTrato.creme,
    superficie: CoresTrato.superficie,
    borda: CoresTrato.borda,
    bordaControle: CoresTrato.bordaControle,
    texto: CoresTrato.petroleo,
    textoSecundario: CoresTrato.textoSecundario,
    textoDica: CoresTrato.textoDica,
    azulSuave: CoresTrato.azulSuave,
    azulTexto: CoresTrato.azulTexto,
    laranja: CoresTrato.laranja,
    ambarSuave: CoresTrato.ambarSuave,
    ambarTexto: CoresTrato.ambarTexto,
    verdeSuave: CoresTrato.verdeSuave,
    verdeTexto: CoresTrato.verdeTexto,
    vermelhoSuave: CoresTrato.vermelhoSuave,
    vermelhoTexto: CoresTrato.vermelhoTexto,
  );

  static const escuro = CoresTemaTrato(
    petroleo: CoresTratoEscuro.petroleo,
    sobrePetroleo: CoresTratoEscuro.sobrePetroleo,
    fundo: CoresTratoEscuro.fundo,
    superficie: CoresTratoEscuro.superficie,
    borda: CoresTratoEscuro.borda,
    bordaControle: CoresTratoEscuro.bordaControle,
    texto: CoresTratoEscuro.texto,
    textoSecundario: CoresTratoEscuro.textoSecundario,
    textoDica: CoresTratoEscuro.textoDica,
    azulSuave: CoresTratoEscuro.azulSuave,
    azulTexto: CoresTratoEscuro.azulTexto,
    laranja: CoresTratoEscuro.laranja,
    ambarSuave: CoresTratoEscuro.ambarSuave,
    ambarTexto: CoresTratoEscuro.ambarTexto,
    verdeSuave: CoresTratoEscuro.verdeSuave,
    verdeTexto: CoresTratoEscuro.verdeTexto,
    vermelhoSuave: CoresTratoEscuro.vermelhoSuave,
    vermelhoTexto: CoresTratoEscuro.vermelhoTexto,
  );

  @override
  CoresTemaTrato copyWith({
    Color? petroleo,
    Color? sobrePetroleo,
    Color? fundo,
    Color? superficie,
    Color? borda,
    Color? bordaControle,
    Color? texto,
    Color? textoSecundario,
    Color? textoDica,
    Color? azulSuave,
    Color? azulTexto,
    Color? laranja,
    Color? ambarSuave,
    Color? ambarTexto,
    Color? verdeSuave,
    Color? verdeTexto,
    Color? vermelhoSuave,
    Color? vermelhoTexto,
  }) {
    return CoresTemaTrato(
      petroleo: petroleo ?? this.petroleo,
      sobrePetroleo: sobrePetroleo ?? this.sobrePetroleo,
      fundo: fundo ?? this.fundo,
      superficie: superficie ?? this.superficie,
      borda: borda ?? this.borda,
      bordaControle: bordaControle ?? this.bordaControle,
      texto: texto ?? this.texto,
      textoSecundario: textoSecundario ?? this.textoSecundario,
      textoDica: textoDica ?? this.textoDica,
      azulSuave: azulSuave ?? this.azulSuave,
      azulTexto: azulTexto ?? this.azulTexto,
      laranja: laranja ?? this.laranja,
      ambarSuave: ambarSuave ?? this.ambarSuave,
      ambarTexto: ambarTexto ?? this.ambarTexto,
      verdeSuave: verdeSuave ?? this.verdeSuave,
      verdeTexto: verdeTexto ?? this.verdeTexto,
      vermelhoSuave: vermelhoSuave ?? this.vermelhoSuave,
      vermelhoTexto: vermelhoTexto ?? this.vermelhoTexto,
    );
  }

  @override
  CoresTemaTrato lerp(ThemeExtension<CoresTemaTrato>? other, double t) {
    if (other is! CoresTemaTrato) return this;
    return CoresTemaTrato(
      petroleo: Color.lerp(petroleo, other.petroleo, t)!,
      sobrePetroleo: Color.lerp(sobrePetroleo, other.sobrePetroleo, t)!,
      fundo: Color.lerp(fundo, other.fundo, t)!,
      superficie: Color.lerp(superficie, other.superficie, t)!,
      borda: Color.lerp(borda, other.borda, t)!,
      bordaControle: Color.lerp(bordaControle, other.bordaControle, t)!,
      texto: Color.lerp(texto, other.texto, t)!,
      textoSecundario: Color.lerp(textoSecundario, other.textoSecundario, t)!,
      textoDica: Color.lerp(textoDica, other.textoDica, t)!,
      azulSuave: Color.lerp(azulSuave, other.azulSuave, t)!,
      azulTexto: Color.lerp(azulTexto, other.azulTexto, t)!,
      laranja: Color.lerp(laranja, other.laranja, t)!,
      ambarSuave: Color.lerp(ambarSuave, other.ambarSuave, t)!,
      ambarTexto: Color.lerp(ambarTexto, other.ambarTexto, t)!,
      verdeSuave: Color.lerp(verdeSuave, other.verdeSuave, t)!,
      verdeTexto: Color.lerp(verdeTexto, other.verdeTexto, t)!,
      vermelhoSuave: Color.lerp(vermelhoSuave, other.vermelhoSuave, t)!,
      vermelhoTexto: Color.lerp(vermelhoTexto, other.vermelhoTexto, t)!,
    );
  }
}

extension CoresTemaNoContexto on BuildContext {
  CoresTemaTrato get cores => Theme.of(this).extension<CoresTemaTrato>() ?? CoresTemaTrato.claro;
}

/// Tema Material do Trato, montado só com os tokens do protótipo.
abstract final class TemaTrato {
  static ThemeData get claro => _construir(CoresTemaTrato.claro, Brightness.light);

  static ThemeData get escuro => _construir(CoresTemaTrato.escuro, Brightness.dark);

  static ThemeData _construir(CoresTemaTrato c, Brightness brilho) {
    final esquema = ColorScheme(
      brightness: brilho,
      primary: c.petroleo,
      onPrimary: c.sobrePetroleo,
      secondary: c.azulTexto,
      onSecondary: c.superficie,
      tertiary: c.laranja,
      onTertiary: c.petroleo,
      error: c.vermelhoTexto,
      onError: c.superficie,
      surface: c.superficie,
      onSurface: c.texto,
      onSurfaceVariant: c.textoSecundario,
      outline: c.borda,
      primaryContainer: c.azulSuave,
      onPrimaryContainer: c.azulTexto,
    );

    final raio = BorderRadius.circular(EspacosTrato.raio);
    final bordaCartao = BorderSide(color: c.borda, width: EspacosTrato.bordaFina);
    final bordaCampo = BorderSide(color: c.bordaControle, width: EspacosTrato.bordaControle);

    return ThemeData(
      useMaterial3: true,
      brightness: brilho,
      colorScheme: esquema,
      scaffoldBackgroundColor: c.fundo,
      fontFamily: TipografiaTrato.fonteCorpo,
      extensions: [c],
      textTheme: TextTheme(
        displayLarge: TipografiaTrato.marca.copyWith(color: c.texto),
        headlineMedium: TipografiaTrato.tituloGrande.copyWith(color: c.texto),
        headlineSmall: TipografiaTrato.titulo.copyWith(color: c.texto),
        titleLarge: TipografiaTrato.titulo.copyWith(color: c.texto),
        titleMedium: TipografiaTrato.tituloCartao.copyWith(color: c.texto),
        titleSmall: TipografiaTrato.corpoForte.copyWith(color: c.texto),
        bodyLarge: TipografiaTrato.corpo.copyWith(color: c.texto),
        bodyMedium: TipografiaTrato.corpoPequeno.copyWith(color: c.texto),
        bodySmall: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
        labelLarge: TipografiaTrato.corpoForte.copyWith(color: c.texto),
        labelMedium: TipografiaTrato.corpoPequeno.copyWith(color: c.texto),
        labelSmall: TipografiaTrato.sobretitulo.copyWith(color: c.textoSecundario),
      ).apply(bodyColor: c.texto, displayColor: c.texto),
      iconTheme: IconThemeData(color: c.texto),
      primaryIconTheme: IconThemeData(color: c.texto),
      appBarTheme: AppBarTheme(
        backgroundColor: c.fundo,
        foregroundColor: c.texto,
        iconTheme: IconThemeData(color: c.texto),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.petroleo,
          foregroundColor: c.sobrePetroleo,
          minimumSize: const Size.fromHeight(EspacosTrato.alturaBotao),
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.petroleo,
          foregroundColor: c.sobrePetroleo,
          minimumSize: const Size.fromHeight(EspacosTrato.alturaBotao),
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: c.superficie,
          foregroundColor: c.texto,
          minimumSize: const Size.fromHeight(EspacosTrato.alturaBotao),
          side: bordaCampo,
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.azulTexto,
          textStyle: TipografiaTrato.corpoForte.copyWith(decoration: TextDecoration.underline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.superficie,
        hintStyle: TipografiaTrato.corpo.copyWith(color: c.textoDica),
        labelStyle: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
        floatingLabelStyle: TipografiaTrato.corpoPequeno.copyWith(color: c.petroleo),
        errorStyle: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EspacosTrato.x4,
          vertical: (EspacosTrato.alturaCampo - 24) / 2,
        ),
        border: OutlineInputBorder(borderRadius: raio, borderSide: bordaCampo),
        enabledBorder: OutlineInputBorder(borderRadius: raio, borderSide: bordaCampo),
        focusedBorder: OutlineInputBorder(
          borderRadius: raio,
          borderSide: BorderSide(color: c.petroleo, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.superficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: bordaCartao,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.petroleo,
        textColor: c.texto,
        titleTextStyle: TipografiaTrato.corpoForte.copyWith(color: c.texto),
        subtitleTextStyle: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.superficie,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TipografiaTrato.titulo.copyWith(color: c.texto),
        contentTextStyle: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: bordaCartao,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.superficie,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(EspacosTrato.raioGrande)),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.borda, thickness: 1),
      // Avisos (toasts): cartão flutuante arredondado, longe da borda e com texto legível.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.petroleo,
        contentTextStyle: TipografiaTrato.corpo.copyWith(color: c.sobrePetroleo),
        shape: RoundedRectangleBorder(borderRadius: raio),
        insetPadding: const EdgeInsets.fromLTRB(
          EspacosTrato.x4,
          0,
          EspacosTrato.x4,
          EspacosTrato.x6,
        ),
        showCloseIcon: true,
        closeIconColor: c.sobrePetroleo,
      ),
    );
  }
}
