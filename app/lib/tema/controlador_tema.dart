import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla e persiste a preferência de aparência do app (`light`, `dark` ou `system`).
/// Padrão inicial: `ThemeMode.light`.
class ControladorTema extends ChangeNotifier {
  ControladorTema({ThemeMode inicial = ThemeMode.light}) : _modo = inicial;

  static const chavePreferencia = 'trato_tema_modo';

  /// Instância global ligada ao [TratoApp].
  static final ControladorTema instancia = ControladorTema();

  ThemeMode _modo;

  ThemeMode get modo => _modo;

  static ThemeMode decodificar(String? valor) => switch (valor) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  static String codificar(ThemeMode modo) => switch (modo) {
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
      };

  /// Carrega a preferência salva no aparelho. Em caso de erro, mantém `light`.
  Future<void> carregar({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final lido = decodificar(p.getString(chavePreferencia));
      if (lido != _modo) {
        _modo = lido;
        notifyListeners();
      }
    } on Object {
      // Sem armazenamento disponível (ex.: teste sem binding): segue com o padrão.
    }
  }

  /// Atualiza o modo de tema e persiste em [SharedPreferences].
  Future<void> definir(ThemeMode novo, {SharedPreferences? prefs}) async {
    if (novo != _modo) {
      _modo = novo;
      notifyListeners();
    }
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.setString(chavePreferencia, codificar(novo));
    } on Object {
      // Falha ao gravar preferência não trava a troca visual na sessão.
    }
  }
}
