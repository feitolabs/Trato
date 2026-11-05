import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';

// Regressão (04/11/2026): o nome do serviço ("Orçamento geral") entrava na chave de idempotência,
// que vai num cabeçalho HTTP. Acento no cabeçalho derruba a chamada no aparelho, antes de sair,
// e o cliente via só "Algo deu errado". O servidor nunca recebia o POST.

final _asciiVisivel = RegExp(r'^[\x21-\x7E]+$');

const _pedidoCriado = {
  'id': 'ab12cd34',
  'estado': 'aberto',
  'estado_nome': 'Aberto',
  'cliente_id': 'c1',
  'profissional_id': null,
  'aberto_em': '2026-11-04T12:00:00Z',
  'concluido_em': null,
  'acoes_permitidas': <String>[],
  'codigo_inicio': null,
  'codigo_conclusao': null,
};

void main() {
  test('criar pedido com serviço acentuado manda a chave de idempotência só em ASCII', () async {
    final chaves = <String?>[];
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((req) async {
        chaves.add(req.headers['Idempotency-Key']);
        return http.Response(
          jsonEncode(_pedidoCriado),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final id = await RepositorioPedidosApi(api).criar(
      const RascunhoPedido(
        servicos: ['Orçamento geral', 'Instalação elétrica'],
        quantidade: 1,
        voltagem: '',
        descricao: 'Pintar a sala e dois quartos',
        prazo: 'Sem pressa · 10/11',
        faixa: FaixaPreco(minimoCentavos: 10000, maximoCentavos: 20000),
        categoriaId: 'cat-1',
        cidadeId: 'cid-1',
        bairro: 'Savassi',
      ),
    );

    expect(id, 'ab12cd34');
    expect(chaves, hasLength(1));
    expect(chaves.single, isNotNull);
    expect(_asciiVisivel.hasMatch(chaves.single!), isTrue, reason: 'chave: ${chaves.single}');
  });

  test('o ClienteApi limpa qualquer chave com acento ou espaço antes de enviar', () async {
    final chaves = <String?>[];
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((req) async {
        chaves.add(req.headers['Idempotency-Key']);
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );

    await api.post('/v1/qualquer', corpo: const {}, chaveIdempotencia: 'pedido-Orçamento geral-ção');

    expect(_asciiVisivel.hasMatch(chaves.single!), isTrue, reason: 'chave: ${chaves.single}');
    expect(chaves.single, 'pedido-Or_amento_geral-__o');
  });
}
