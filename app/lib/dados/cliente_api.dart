import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'erros.dart';
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
  }) : _cliente = cliente ?? http.Client();

  final String urlBase;
  final SessaoTrato sessao;
  final Duration tempoLimite;
  final Duration intervaloBaseRetry;
  final http.Client _cliente;

  Future<Object?> get(String caminho, {Map<String, String>? consulta}) =>
      _enviar('GET', caminho, consulta: consulta);

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

  Future<Object?> patch(String caminho, {Object? corpo}) =>
      _enviar('PATCH', caminho, corpo: corpo);

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
          return await tentar();
        } on TimeoutException {
          if (tentativa == maxTentativas) throw ErroTrato.semInternet;
        } on SocketException {
          if (tentativa == maxTentativas) throw ErroTrato.semInternet;
        } on http.ClientException {
          if (tentativa == maxTentativas) throw ErroTrato.semInternet;
        }
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs *= 2;
        }
      }
      throw ErroTrato.semInternet;
    }

    var resposta = await executarComRetry();
    // 401 com sessão: tenta renovar o token uma vez e repete a chamada (mesma chave de
    // idempotência, então não duplica). Se não renovar, `_tratar` limpa a sessão.
    if (resposta.statusCode == 401 && sessao.logada) {
      final anterior = sessao.token;
      final novo = await sessao.renovarToken();
      if (novo != null && novo != anterior) resposta = await tentar();
    }
    return _tratar(resposta);
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
      );
    }
    if (codigo == 501) throw ErroTrato.indisponivel;
    if (codigo >= 500) throw ErroTrato.servidor;
    // 400, 403, 409, 422...: o backend explica o motivo em `detail`.
    throw ErroTrato(
      TipoErro.recusado,
      _detalhe(resposta) ?? 'Não foi possível concluir. Confira os dados e tente de novo.',
      codigoHttp: codigo,
    );
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
