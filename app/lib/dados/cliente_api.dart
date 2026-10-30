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
  }) : _cliente = cliente ?? http.Client();

  final String urlBase;
  final SessaoTrato sessao;
  final Duration tempoLimite;
  final http.Client _cliente;

  Future<Object?> get(String caminho, {Map<String, String>? consulta}) =>
      _enviar('GET', caminho, consulta: consulta);

  Future<Object?> post(String caminho, {Object? corpo, String? chaveIdempotencia}) =>
      _enviar('POST', caminho, corpo: corpo, chaveIdempotencia: chaveIdempotencia);

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
  }) async {
    Future<http.Response> tentar() async {
      final pedido = http.Request(metodo, _uri(caminho, consulta))
        ..headers['Accept'] = 'application/json';
      final token = sessao.token;
      if (token != null && token.isNotEmpty) {
        pedido.headers['Authorization'] = 'Bearer $token';
      }
      if (chaveIdempotencia != null) {
        pedido.headers['Idempotency-Key'] = chaveIdempotencia;
      }
      if (corpo != null) {
        pedido.headers['Content-Type'] = 'application/json; charset=utf-8';
        pedido.body = jsonEncode(corpo);
      }
      try {
        return await http.Response.fromStream(await _cliente.send(pedido).timeout(tempoLimite));
      } on TimeoutException {
        throw ErroTrato.semInternet;
      } on SocketException {
        throw ErroTrato.semInternet;
      } on http.ClientException {
        throw ErroTrato.semInternet;
      }
    }

    var resposta = await tentar();
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
      throw ErroTrato(TipoErro.naoEncontrado, _detalhe(resposta) ?? 'Não encontramos isso.');
    }
    if (codigo == 501) throw ErroTrato.indisponivel;
    if (codigo >= 500) throw ErroTrato.servidor;
    // 400, 403, 409, 422...: o backend explica o motivo em `detail`.
    throw ErroTrato(
      TipoErro.recusado,
      _detalhe(resposta) ?? 'Não foi possível concluir. Confira os dados e tente de novo.',
    );
  }

  /// `detail` do FastAPI: texto (regras de negócio) ou lista (validação). Só texto vai à tela.
  String? _detalhe(http.Response resposta) {
    try {
      final json = jsonDecode(utf8.decode(resposta.bodyBytes));
      if (json is Map && json['detail'] is String) {
        return json['detail'] as String;
      }
    } on FormatException {
      // corpo que não é JSON: usa a mensagem padrão
    }
    return null;
  }

  void fechar() => _cliente.close();
}
