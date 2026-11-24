import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cache_leitura.dart';
import 'erros.dart';
import 'estado_conexao.dart';
import 'sessao.dart';

/// Cliente HTTP da API do Trato: URL base, cabeçalho Authorization, tempo limite e erros em
/// português simples. Só sabe JSON; não sabe de regra de negócio.
class ClienteApi {
  ClienteApi({
    required this.urlBase,
    required this.sessao,
    http.Client? cliente,
    this.tempoLimite = const Duration(seconds: 15),
    this.intervaloBaseRetry = const Duration(milliseconds: 200),
    this.cache,
  }) : _cliente = cliente ?? http.Client() {
    // Sair da conta apaga as leituras guardadas deste aparelho.
    if (cache != null) sessao.aoSair.add(() => unawaited(cache!.limpar()));
  }

  /// Últimas leituras para mostrar sem internet (opcional).
  final CacheLeitura? cache;

  final String urlBase;
  final SessaoTrato sessao;
  final Duration tempoLimite;
  final Duration intervaloBaseRetry;
  final http.Client _cliente;

  Future<Object?> get(String caminho, {Map<String, String>? consulta}) =>
      _enviar('GET', caminho, consulta: consulta);

  /// Busca bytes brutos (ex.: extrato mensal em PDF). Trata 401 e erros HTTP como [_enviar].
  Future<Uint8List> getBytes(String caminho, {Map<String, String>? consulta}) async {
    Future<http.Response> tentar() async {
      final pedido = http.Request('GET', _uri(caminho, consulta))
        ..headers['Accept'] = 'application/pdf, */*';
      final efetivo = sessao.token;
      if (efetivo != null && efetivo.isNotEmpty) {
        pedido.headers['Authorization'] = 'Bearer $efetivo';
      }
      return await http.Response.fromStream(await _cliente.send(pedido).timeout(tempoLimite));
    }

    http.Response resposta;
    try {
      resposta = await tentar();
    } on TimeoutException {
      EstadoConexao.marcarOffline();
      throw ErroTrato.semInternet;
    } on SocketException {
      EstadoConexao.marcarOffline();
      throw ErroTrato.semInternet;
    } on http.ClientException {
      EstadoConexao.marcarOffline();
      throw ErroTrato.semInternet;
    }
    EstadoConexao.marcarOnline();
    if (resposta.statusCode == 401 && sessao.logada) {
      final anterior = sessao.token;
      final novo = await sessao.renovarToken();
      if (novo != null && novo != anterior) resposta = await tentar();
    }
    if (resposta.statusCode >= 200 && resposta.statusCode < 300) {
      return resposta.bodyBytes;
    }
    _tratar(resposta);
    throw ErroTrato.servidor;
  }

  Future<Object?> post(
    String caminho, {
    Map<String, String>? consulta,
    Object? corpo,
    String? chaveIdempotencia,
    String? token,
  }) =>
      _enviar(
        'POST',
        caminho,
        consulta: consulta,
        corpo: corpo,
        chaveIdempotencia: chaveIdempotencia,
        token: token,
      );

  Future<Object?> patch(String caminho, {Object? corpo}) => _enviar('PATCH', caminho, corpo: corpo);

  Future<Object?> put(String caminho, {Object? corpo}) => _enviar('PUT', caminho, corpo: corpo);

  Future<Object?> delete(String caminho, {Object? corpo}) =>
      _enviar('DELETE', caminho, corpo: corpo);

  Uri _uri(String caminho, Map<String, String>? consulta) {
    final base = urlBase.endsWith('/') ? urlBase.substring(0, urlBase.length - 1) : urlBase;
    return Uri.parse('$base$caminho').replace(queryParameters: consulta);
  }

  Future<Object?> _enviar(
    String metodo,
    String caminho, {
    Map<String, String>? consulta,
    Object? corpo,
    String? chaveIdempotencia,
    String? token,
  }) async {
    Future<http.Response> tentar() async {
      final pedido = http.Request(metodo, _uri(caminho, consulta))
        ..headers['Accept'] = 'application/json';
      final efetivo = token ?? sessao.token;
      if (efetivo != null && efetivo.isNotEmpty) {
        pedido.headers['Authorization'] = 'Bearer $efetivo';
      }
      if (chaveIdempotencia != null) {
        // Cabeçalho HTTP só aceita ASCII visível: acento ou espaço na chave derrubaria a chamada
        // antes de sair do aparelho.
        pedido.headers['Idempotency-Key'] =
            chaveIdempotencia.replaceAll(RegExp(r'[^\x21-\x7E]'), '_');
      }
      if (corpo != null) {
        pedido.headers['Content-Type'] = 'application/json; charset=utf-8';
        pedido.body = jsonEncode(corpo);
      }
      return await http.Response.fromStream(await _cliente.send(pedido).timeout(tempoLimite));
    }

    Future<http.Response> executarComRetry() async {
      final permitirRetry = metodo == 'GET' || chaveIdempotencia != null;
      final maxTentativas = permitirRetry ? 3 : 1;
      var delayMs = intervaloBaseRetry.inMilliseconds;

      for (var tentativa = 1; tentativa <= maxTentativas; tentativa++) {
        try {
          final resposta = await tentar();
          EstadoConexao.marcarOnline();
          if (resposta.statusCode == 429 && permitirRetry && tentativa < maxTentativas) {
            if (intervaloBaseRetry > Duration.zero) {
              final esperaMs = delayMs > 0 ? delayMs * 2 : 500;
              await Future.delayed(Duration(milliseconds: esperaMs));
              delayMs = esperaMs;
            }
            continue;
          }
          return resposta;
        } on TimeoutException {
          if (tentativa == maxTentativas) _semRede();
        } on SocketException {
          if (tentativa == maxTentativas) _semRede();
        } on http.ClientException {
          if (tentativa == maxTentativas) _semRede();
        }
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs *= 2;
        }
      }
      _semRede();
    }

    http.Response resposta;
    try {
      resposta = await executarComRetry();
    } on ErroTrato catch (e) {
      // Sem internet numa leitura: mostra a última resposta guardada, se houver.
      if (metodo == 'GET' && e.tipo == TipoErro.semInternet) {
        final guardado = await _lerDoCache(caminho, consulta);
        if (guardado.achou) {
          EstadoConexao.dadosSalvos.value = true;
          return guardado.valor;
        }
      }
      rethrow;
    }
    // 401 com sessão: tenta renovar o token uma vez e repete a chamada (mesma chave de
    // idempotência, então não duplica). Se não renovar, `_tratar` limpa a sessão.
    if (resposta.statusCode == 401 && sessao.logada) {
      final anterior = sessao.token;
      final novo = await sessao.renovarToken();
      if (novo != null && novo != anterior) resposta = await tentar();
    }
    final resultado = _tratar(resposta);
    if (metodo == 'GET') _guardarNoCache(caminho, consulta, resultado);
    return resultado;
  }

  Future<({bool achou, Object? valor})> _lerDoCache(
    String caminho,
    Map<String, String>? consulta,
  ) async {
    try {
      return await cache?.buscar(caminho, consulta) ?? (achou: false, valor: null);
    } on Object {
      return (achou: false, valor: null);
    }
  }

  void _guardarNoCache(String caminho, Map<String, String>? consulta, Object? json) {
    final c = cache;
    if (c == null) return;
    unawaited(c.guardar(caminho, consulta, json).catchError((Object _) {}));
  }

  /// Falha de rede: avisa o banner "Sem conexão" e lança o erro de sempre.
  Never _semRede() {
    EstadoConexao.marcarOffline();
    throw ErroTrato.semInternet;
  }

  Object? _tratar(http.Response resposta) {
    final codigo = resposta.statusCode;
    if (codigo >= 200 && codigo < 300) {
      if (resposta.bodyBytes.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(resposta.bodyBytes));
      } on FormatException {
        throw ErroTrato.servidor;
      }
    }
    if (codigo == 401) {
      sessao.expirar();
      throw ErroTrato.sessaoExpirada;
    }
    if (codigo == 404) {
      throw ErroTrato(
        TipoErro.naoEncontrado,
        _detalhe(resposta) ?? 'Não encontramos isso.',
        codigoHttp: codigo,
        codigo: _codigoErro(resposta),
      );
    }
    if (codigo == 501) throw ErroTrato.indisponivel;
    if (codigo >= 500) {
      final cod = _codigoErro(resposta);
      if (cod != null) {
        throw ErroTrato(
          TipoErro.servidor,
          _detalhe(resposta) ?? ErroTrato.servidor.mensagem,
          codigoHttp: codigo,
          codigo: cod,
        );
      }
      throw ErroTrato.servidor;
    }
    // 400, 403, 409, 422...: o backend explica o motivo em `detail` e opcionalmente em `codigo`.
    throw ErroTrato(
      TipoErro.recusado,
      _detalhe(resposta) ?? 'Não foi possível concluir. Confira os dados e tente de novo.',
      codigoHttp: codigo,
      codigo: _codigoErro(resposta),
    );
  }

  String? _codigoErro(http.Response resposta) {
    try {
      final json = jsonDecode(utf8.decode(resposta.bodyBytes));
      if (json is Map && json['codigo'] is String) {
        final c = (json['codigo'] as String).trim();
        if (c.isNotEmpty) return c;
      }
    } on FormatException {
      // corpo que não é JSON
    }
    return null;
  }

  /// `detail` do FastAPI: texto (regras de negócio) ou lista (validação).
  String? _detalhe(http.Response resposta) {
    try {
      final json = jsonDecode(utf8.decode(resposta.bodyBytes));
      if (json is Map) {
        final d = json['detail'];
        if (d is String && d.trim().isNotEmpty) return d;
        if (d is List && d.isNotEmpty) {
          final msgs = <String>[];
          for (final item in d) {
            if (item is Map && item['msg'] is String) {
              msgs.add(item['msg'] as String);
            } else if (item is String) {
              msgs.add(item);
            }
          }
          if (msgs.isNotEmpty) return msgs.join('. ');
        }
      }
    } on FormatException {
      // corpo que não é JSON: usa a mensagem padrão
    }
    return null;
  }

  void fechar() => _cliente.close();
}
