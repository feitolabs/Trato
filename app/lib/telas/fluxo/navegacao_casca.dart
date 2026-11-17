import 'package:flutter/foundation.dart';

/// Controla a aba ativa da casca (Cliente ou Profissional) para permitir retornar ao Início
/// ou saltar entre abas ao concluir um fluxo, disparando atualização imediata.
class ControladorCasca {
  static void Function(int aba)? _irParaAba;
  static VoidCallback? _recarregarCasca;

  static void registrar({
    required void Function(int aba) irParaAba,
    VoidCallback? recarregarCasca,
  }) {
    _irParaAba = irParaAba;
    _recarregarCasca = recarregarCasca;
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

