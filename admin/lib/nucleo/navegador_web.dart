import 'dart:js_interop';

@JS('window.history.replaceState')
external void _replaceState(JSAny? estado, String titulo, String url);

@JS('window.location.pathname')
external String get _caminho;

/// A URL em que o painel foi aberto.
Uri urlAtual() => Uri.base;

/// Tira o fragmento (e o token que veio nele) da barra de endereço e do histórico.
void limparHash() {
  try {
    _replaceState(null, '', _caminho);
  } catch (_) {
    // Se o navegador recusar, o token continua só em memória; nada a fazer.
  }
}
