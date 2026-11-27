import 'dart:async';
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

@JS('window.open')
external JSAny? _abrirJanela(String url, String alvo, String recursos);

/// Abre um link em outra aba, sem dar a ela acesso ao painel nem enviar a origem.
bool abrirEmNovaAba(String url) {
  try {
    _abrirJanela(url, '_blank', 'noopener,noreferrer');
    return true;
  } catch (_) {
    return false;
  }
}

/// Abre o seletor de arquivo do navegador. Devolve null se a pessoa desistir. Arquivo acima de
/// [maximoBytes] volta sem os bytes (só com o tamanho), para a tela recusar sem carregá-lo.
Future<({String nome, String tipo, int tamanho, List<int> bytes})?> escolherArquivoNativo(
    String aceita, int maximoBytes) {
  final resposta = Completer<({String nome, String tipo, int tamanho, List<int> bytes})?>();
  final campo = _criarElemento('input');
  campo.setProperty('type'.toJS, 'file'.toJS);
  campo.setProperty('accept'.toJS, aceita.toJS);

  Future<void> ler() async {
    try {
      final lista = campo.getProperty<JSObject?>('files'.toJS);
      final arquivo = lista?.callMethod<JSObject?>('item'.toJS, 0.toJS);
      if (arquivo == null) {
        if (!resposta.isCompleted) resposta.complete(null);
        return;
      }
      final nome = arquivo.getProperty<JSString>('name'.toJS).toDart;
      final tipo = arquivo.getProperty<JSString>('type'.toJS).toDart;
      final tamanho = arquivo.getProperty<JSNumber>('size'.toJS).toDartInt;
      var bytes = <int>[];
      if (tamanho <= maximoBytes) {
        final buffer = await arquivo.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS).toDart;
        bytes = buffer.toDart.asUint8List();
      }
      if (!resposta.isCompleted) resposta.complete((nome: nome, tipo: tipo, tamanho: tamanho, bytes: bytes));
    } catch (e) {
      if (!resposta.isCompleted) resposta.completeError(e);
    }
  }

  campo.callMethod('addEventListener'.toJS, 'change'.toJS, ((JSAny? _) {
    ler();
  }).toJS);
  campo.callMethod('addEventListener'.toJS, 'cancel'.toJS, ((JSAny? _) {
    if (!resposta.isCompleted) resposta.complete(null);
  }).toJS);
  campo.callMethod('click'.toJS);
  return resposta.future;
}
