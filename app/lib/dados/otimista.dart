import 'dart:async';
import 'package:flutter/foundation.dart';

/// Executa uma ação de toque com UI Otimista:
/// 1. "Atualize primeiro": executa [aoAtualizarLocal] síncrono imediatamente após o toque.
/// 2. "Sincronize depois": dispara [sincronizar] de forma assíncrona com o backend/banco.
/// 3. Se falhar: chama [aoReverter] para restaurar o estado original e notifica via [aoFalhar].
Future<bool> executarOtimista<T>({
  required VoidCallback aoAtualizarLocal,
  required Future<T> Function() sincronizar,
  required VoidCallback aoReverter,
  void Function(Object erro)? aoFalhar,
}) async {
  // 1. Atualiza primeiro na interface
  aoAtualizarLocal();

  // 2. Sincroniza em segundo plano
  try {
    await sincronizar();
    return true;
  } catch (erro) {
    // 3. Em caso de falha, reverte imediatamente e notifica
    aoReverter();
    aoFalhar?.call(erro);
    return false;
  }
}

/// Contêiner reativo para estados manipulados de forma otimista.
class ControladorOtimista<T> extends ChangeNotifier {
  ControladorOtimista(this._valor) : _valorConfirmado = _valor;

  T _valor;
  T _valorConfirmado;
  bool _sincronizando = false;
  Object? _ultimoErro;

  T get valor => _valor;
  T get valorConfirmado => _valorConfirmado;
  bool get sincronizando => _sincronizando;
  Object? get ultimoErro => _ultimoErro;

  /// Atualiza o valor visível na hora e sincroniza em background.
  Future<bool> atualizar(
    T novoValor,
    Future<void> Function(T valor) sincronizarRemoto, {
    void Function(Object erro)? aoFalhar,
  }) async {
    final valorAnterior = _valor;
    _valor = novoValor;
    _sincronizando = true;
    _ultimoErro = null;
    notifyListeners();

    try {
      await sincronizarRemoto(novoValor);
      _valorConfirmado = novoValor;
      _sincronizando = false;
      notifyListeners();
      return true;
    } catch (e) {
      _valor = valorAnterior;
      _sincronizando = false;
      _ultimoErro = e;
      notifyListeners();
      aoFalhar?.call(e);
      return false;
    }
  }

  /// Força a redefinição confirmada do valor (ex.: carregamento inicial).
  void redefinir(T novoValor) {
    _valor = novoValor;
    _valorConfirmado = novoValor;
    _sincronizando = false;
    _ultimoErro = null;
    notifyListeners();
  }
}

