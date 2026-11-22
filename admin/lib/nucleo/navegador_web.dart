import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

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

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external _Blob(JSArray<JSAny> partes, _OpcoesBlob opcoes);
}

@JS()
@anonymous
extension type _OpcoesBlob._(JSObject _) implements JSObject {
  external factory _OpcoesBlob({String type});
}

@JS('URL.createObjectURL')
external String _criarUrl(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revogarUrl(String url);

@JS('document.createElement')
external JSObject _criarElemento(String tag);

/// Entrega os bytes já baixados (com o token de login) como arquivo, sem pôr o token em URL.
bool salvarArquivo(List<int> bytes, String nome, String tipo) {
  try {
    final blob = _Blob([Uint8List.fromList(bytes).toJS].toJS, _OpcoesBlob(type: tipo));
    final url = _criarUrl(blob);
    final a = _criarElemento('a');
    a.setProperty('href'.toJS, url.toJS);
    a.setProperty('download'.toJS, nome.toJS);
    a.callMethod('click'.toJS);
    _revogarUrl(url);
    return true;
  } catch (_) {
    return false;
  }
}
