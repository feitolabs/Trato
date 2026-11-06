// Tema Material do painel admin, montado só com os tokens do DS v2. Ver LEIA-ME.md.

import 'package:flutter/material.dart';

import 'cores.dart';
import 'espacos.dart';
import 'tipografia.dart';

export 'cores.dart';
export 'espacos.dart';
export 'responsivo.dart';
export 'tipografia.dart';

abstract final class TemaTrato {
  static ThemeData get claro {
    const esquema = ColorScheme(
      brightness: Brightness.light,
      primary: CoresTrato.primaria,
      onPrimary: CoresTrato.textoSobrePrimaria,
      secondary: CoresTrato.textoLink,
      onSecondary: CoresTrato.fundoSuperficie,
      tertiary: CoresTrato.brasa,
      onTertiary: CoresTrato.primaria,
      error: CoresTrato.perigoTexto,
      onError: CoresTrato.fundoSuperficie,
      surface: CoresTrato.fundoSuperficie,
      onSurface: CoresTrato.textoPadrao,
      onSurfaceVariant: CoresTrato.textoMudo,
      outline: CoresTrato.bordaForte,
      outlineVariant: CoresTrato.bordaSuave,
      primaryContainer: CoresTrato.fundoSelecionado,
      onPrimaryContainer: CoresTrato.textoLink,
    );

    final raio = BorderRadius.circular(EspacosTrato.raio);
    const bordaCampo = BorderSide(color: CoresTrato.bordaForte, width: EspacosTrato.bordaFina);
    const aneldeFoco = BorderSide(color: CoresTrato.foco, width: EspacosTrato.aneldeFoco);

    // Estados do botão: padrão, hover, foco (anel de 2 px), pressionado, desabilitado.
    WidgetStateProperty<BorderSide?> lado(BorderSide padrao) => WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.focused) ? aneldeFoco : padrao,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: CoresTrato.fundoPagina,
      fontFamily: TipografiaTrato.fonteCorpo,
      textTheme: TextTheme(
        displayLarge: TipografiaTrato.marca,
        headlineMedium: TipografiaTrato.valor,
        titleLarge: TipografiaTrato.titulo,
        // Dropdown e campos usam titleMedium: ficam no corpo (14/20), igual ao campo de texto.
        titleMedium: TipografiaTrato.corpo,
        bodyLarge: TipografiaTrato.corpo,
        bodyMedium: TipografiaTrato.corpo,
        bodySmall: TipografiaTrato.legenda,
        labelLarge: TipografiaTrato.corpoForte,
        labelSmall: TipografiaTrato.etiqueta,
      ),
      focusColor: CoresTrato.foco.withValues(alpha: 0.16),
      appBarTheme: AppBarTheme(
        backgroundColor: CoresTrato.fundoSuperficie,
        foregroundColor: CoresTrato.primaria,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TipografiaTrato.secao,
      ),
      // Primário: verde-petróleo preenchido.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CoresTrato.primaria,
          foregroundColor: CoresTrato.textoSobrePrimaria,
          disabledBackgroundColor: CoresTrato.neutroFundo,
          disabledForegroundColor: CoresTrato.textoMudo,
          minimumSize: const Size(0, EspacosTrato.alturaBotao),
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte,
        ).copyWith(side: lado(BorderSide.none)),
      ),
      // Secundário: superfície com borda.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: CoresTrato.fundoSuperficie,
          foregroundColor: CoresTrato.primaria,
          disabledForegroundColor: CoresTrato.textoMudo,
          minimumSize: const Size(0, EspacosTrato.alturaBotao),
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte,
        ).copyWith(side: lado(bordaCampo)),
      ),
      // Link de ação: texto sublinhado, só para ações neutras.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CoresTrato.textoLink,
          disabledForegroundColor: CoresTrato.textoMudo,
          minimumSize: const Size(0, EspacosTrato.alturaBotao),
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3),
          shape: RoundedRectangleBorder(borderRadius: raio),
          textStyle: TipografiaTrato.corpoForte.copyWith(decoration: TextDecoration.underline),
        ).copyWith(side: lado(BorderSide.none)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: CoresTrato.primaria,
          minimumSize: const Size(EspacosTrato.alturaBotao, EspacosTrato.alturaBotao),
          iconSize: 16 + 4,
        ).copyWith(side: lado(BorderSide.none)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CoresTrato.fundoSuperficie,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo),
        floatingLabelStyle: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo),
        hintStyle: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo),
        helperStyle: TipografiaTrato.legenda,
        helperMaxLines: 3,
        errorStyle: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto),
        errorMaxLines: 3,
        counterStyle: TipografiaTrato.legenda,
        prefixStyle: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EspacosTrato.x4,
          vertical: EspacosTrato.x3,
        ),
        border: OutlineInputBorder(borderRadius: raio, borderSide: bordaCampo),
        enabledBorder: OutlineInputBorder(borderRadius: raio, borderSide: bordaCampo),
        focusedBorder: OutlineInputBorder(
          borderRadius: raio,
          borderSide: const BorderSide(color: CoresTrato.foco, width: EspacosTrato.aneldeFoco),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: raio,
          borderSide: const BorderSide(color: CoresTrato.perigoTexto, width: EspacosTrato.bordaFina),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: raio,
          borderSide: const BorderSide(color: CoresTrato.perigoTexto, width: EspacosTrato.aneldeFoco),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: raio,
          borderSide: const BorderSide(color: CoresTrato.bordaSuave, width: EspacosTrato.bordaFina),
        ),
      ),
      cardTheme: CardThemeData(
        color: CoresTrato.fundoSuperficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: const BorderSide(color: CoresTrato.bordaSuave, width: EspacosTrato.bordaFina),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CoresTrato.fundoSuperficie,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: CoresTrato.camadaModal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EspacosTrato.raioModal)),
        titleTextStyle: TipografiaTrato.secao,
        contentTextStyle: TipografiaTrato.corpo,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: CoresTrato.fundoSuperficie,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: CoresTrato.camadaModal,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(EspacosTrato.raioModal)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CoresTrato.primaria,
        contentTextStyle: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSobrePrimaria),
        shape: RoundedRectangleBorder(borderRadius: raio),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: CoresTrato.fundoSuperficie,
        selectedColor: CoresTrato.fundoSelecionado,
        side: const BorderSide(color: CoresTrato.bordaForte),
        labelStyle: TipografiaTrato.corpo,
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      dividerTheme: const DividerThemeData(color: CoresTrato.bordaSuave, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: CoresTrato.primaria,
          borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
        ),
        textStyle: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSobrePrimaria),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: CoresTrato.primaria),
    );
  }
}
