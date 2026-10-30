import 'package:flutter/material.dart';

import 'cores.dart';
import 'espacos.dart';
import 'tipografia.dart';

export 'cores.dart';
export 'espacos.dart';
export 'responsivo.dart';
export 'tipografia.dart';

/// Tema Material do Trato, montado só com os tokens do protótipo.
abstract final class TemaTrato {
  static ThemeData get claro {
    const esquema = ColorScheme(
      brightness: Brightness.light,
      primary: CoresTrato.petroleo,
      onPrimary: CoresTrato.creme,
      secondary: CoresTrato.azulTexto,
      onSecondary: CoresTrato.superficie,
      tertiary: CoresTrato.laranja,
      onTertiary: CoresTrato.petroleo,
      error: CoresTrato.vermelhoTexto,
      onError: CoresTrato.superficie,
      surface: CoresTrato.superficie,
      onSurface: CoresTrato.petroleo,
      onSurfaceVariant: CoresTrato.textoSecundario,
      outline: CoresTrato.borda,
      primaryContainer: CoresTrato.azulSuave,
      onPrimaryContainer: CoresTrato.azulTexto,
    );

    final raio = BorderRadius.circular(EspacosTrato.raio);
    const bordaCartao = BorderSide(color: CoresTrato.borda, width: EspacosTrato.bordaFina);
    const bordaCampo =
        BorderSide(color: CoresTrato.bordaControle, width: EspacosTrato.bordaControle);

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: CoresTrato.creme,
      fontFamily: TipografiaTrato.fonteCorpo,
      textTheme: TextTheme(
        displayLarge: TipografiaTrato.marca,
        headlineMedium: TipografiaTrato.tituloGrande,
        titleLarge: TipografiaTrato.titulo,
        titleMedium: TipografiaTrato.tituloCartao,
        bodyLarge: TipografiaTrato.corpo,
        bodyMedium: TipografiaTrato.corpoPequeno,
        bodySmall: TipografiaTrato.legenda,
        labelLarge: TipografiaTrato.corpoForte,
        labelSmall: TipografiaTrato.sobretitulo,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: CoresTrato.creme,
        foregroundColor: CoresTrato.petroleo,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TipografiaTrato.corpoPequeno.copyWith(
          color: CoresTrato.textoSecundario,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CoresTrato.petroleo,
          foregroundColor: CoresTrato.creme,
          minimumSize: const Size.fromHeight(EspacosTrato.alturaBotao),
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: CoresTrato.superficie,
          foregroundColor: CoresTrato.petroleo,
          minimumSize: const Size.fromHeight(EspacosTrato.alturaBotao),
          side: bordaCampo,
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CoresTrato.azulTexto,
          textStyle: TipografiaTrato.corpoForte.copyWith(
            decoration: TextDecoration.underline,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CoresTrato.superficie,
        hintStyle: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoDica),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EspacosTrato.x4,
          vertical: (EspacosTrato.alturaCampo - 24) / 2,
        ),
        border: OutlineInputBorder(borderRadius: raio, borderSide: bordaCampo),
        enabledBorder: OutlineInputBorder(borderRadius: raio, borderSide: bordaCampo),
        focusedBorder: OutlineInputBorder(
          borderRadius: raio,
          borderSide: const BorderSide(color: CoresTrato.petroleo, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: CoresTrato.superficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: bordaCartao,
        ),
      ),
      dividerTheme: const DividerThemeData(color: CoresTrato.borda, thickness: 1),
    );
  }
}
