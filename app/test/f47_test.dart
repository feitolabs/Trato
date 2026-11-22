import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/conclusao/modelos.dart';

Future<Map<String, dynamic>> _enviarNotas(List<int> notas) async {
  Map<String, dynamic>? corpoEnviado;
  final api = ClienteApi(
    urlBase: 'https://api.teste/',
    sessao: SessaoTrato()..entrar('token'),
    cliente: MockClient((r) async {
      if (r.url.path == '/v1/contratos/p1/avaliacao') {
        corpoEnviado = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'moedas_ganhas': 5}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('null', 404);
    }),
  );
  final repo = RepositorioPedidosApi(api);
  final moedas = await repo.avaliar(
    'p1',
    EnvioAvaliacao(notas: notas, comentario: '', gorjetaCentavos: 0),
  );
  expect(moedas, 5);
  return corpoEnviado!;
}

void main() {
  group('F47 · envio de nota_decimal na avaliação do cliente', () {
    test('média 4,8 envia nota_geral 5 e nota_decimal 4.8', () async {
      final corpo = await _enviarNotas([5, 5, 5, 5, 4]);
      expect(corpo['nota_geral'], 5);
      expect(corpo['nota_decimal'], 4.8);
    });

    test('média com dízima arredonda para 2 casas decimais', () async {
      final corpo = await _enviarNotas([5, 5, 4]);
      expect(corpo['nota_geral'], 5);
      expect(corpo['nota_decimal'], 4.67);
    });

    test('média inteira envia nota_geral e nota_decimal iguais', () async {
      final corpo = await _enviarNotas([4, 4, 4]);
      expect(corpo['nota_geral'], 4);
      expect(corpo['nota_decimal'], 4.0);
    });

    test('média fora de 1..5 envia apenas nota_geral e omite nota_decimal', () async {
      final corpo = await _enviarNotas([6, 6]);
      expect(corpo['nota_geral'], 5);
      expect(corpo.containsKey('nota_decimal'), isFalse);
    });
  });
}
