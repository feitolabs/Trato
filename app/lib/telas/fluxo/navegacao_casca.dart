import 'package:flutter/foundation.dart';

/// Controla a aba ativa da casca (Cliente ou Profissional) para permitir retornar ao Início
/// ou saltar entre abas ao concluir um fluxo, disparando atualização imediata.
class ControladorCasca {
  static void Function(int aba)? _irParaAba;
  static VoidCallback? _recarregarCasca;
  static var _profissional = false;

  /// Chamado quando uma casca aparece (o deep link espera por ela). O `deep_link.dart` liga.
  static VoidCallback? aoCascaPronta;

  /// Há uma casca (Início) na tela.
  static bool get ativa => _irParaAba != null;

  /// A casca na tela é a do profissional.
  static bool get souProfissional => _profissional;

  static void registrar({
    required void Function(int aba) irParaAba,
    VoidCallback? recarregarCasca,
    bool profissional = false,
  }) {
    _irParaAba = irParaAba;
    _recarregarCasca = recarregarCasca;
    _profissional = profissional;
    aoCascaPronta?.call();
  }

  static void desregistrar(void Function(int aba) irParaAba) {
    if (identical(_irParaAba, irParaAba)) {
      _irParaAba = null;
      _recarregarCasca = null;
    }
  }

  static void selecionarAba(int aba) {
    _irParaAba?.call(aba);
    _recarregarCasca?.call();
  }

  static void recarregarAtual() => _recarregarCasca?.call();
}

