import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'erros.dart';
import 'sessao.dart';

/// Cliente HTTP da API do Trato, adaptado para a web (sem `dart:io`).
/// Mesma base de `app/lib/dados/cliente_api.dart`: só sabe JSON e erros em português;
/// nenhuma regra de negócio ou de dinheiro aqui.
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

  Future<Object?> post(String caminho, {Object? corpo}) => _enviar('POST', caminho, corpo: corpo);

  Uri _uri(String caminho, Map<String, String>? consulta) {
    final base = urlBase.endsWith('/') ? urlBase.substring(0, urlBase.length - 1) : urlBase;
    return Uri.parse('$base$caminho').replace(queryParameters: consulta);
  }

  Future<Object?> _enviar(
    String metodo,
    String caminho, {
    Map<String, String>? consulta,
    Object? corpo,
  }) async {
    Future<http.Response> tentar() async {
      final pedido = http.Request(metodo, _uri(caminho, consulta))
        ..headers['Accept'] = 'application/json';
      final token = sessao.token;
      if (token != null && token.isNotEmpty) {
        pedido.headers['Authorization'] = 'Bearer $token';
      }
      if (corpo != null) {
        pedido.headers['Content-Type'] = 'application/json; charset=utf-8';
        pedido.body = jsonEncode(corpo);
      }
      return await http.Response.fromStream(await _cliente.send(pedido).timeout(tempoLimite));
    }

    http.Response resposta;
    try {
      resposta = await tentar();
    } on TimeoutException {
      throw ErroTrato.semInternet;
    } on http.ClientException {
      throw ErroTrato.semInternet;
    }
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
    if (codigo >= 500) throw ErroTrato.servidor;
    throw ErroTrato(
      TipoErro.recusado,
      _detalhe(resposta) ?? 'Não foi possível concluir. Confira os dados e tente de novo.',
    );
  }

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
