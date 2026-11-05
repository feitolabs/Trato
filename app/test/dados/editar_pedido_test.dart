import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';

const _dados = {
  'titulo': 'Pintar sala',
  'descricao': 'Sala de 35 m2',
  'faixa_preco_max_centavos': 90000,
  'endereco': {'logradouro': 'Rua das Flores', 'numero': '10', 'bairro': 'Centro'},
};

void main() {
  group('centavosDoTexto', () {
    test('aceita R\$, ponto de milhar e vírgula', () {
      expect(centavosDoTexto('R\$ 1.250,50'), 125050);
      expect(centavosDoTexto('900'), 90000);
      expect(centavosDoTexto('900,5'), 90050);
      expect(centavosDoTexto('0,99'), 99);
    });
    test('vazio ou lixo vira nulo', () {
      expect(centavosDoTexto(''), isNull);
      expect(centavosDoTexto('abc'), isNull);
    });
  });

  group('RepositorioPedidosApi.editar', () {
    (RepositorioPedidosApi, List<http.Request>) montar() {
      final pedidas = <http.Request>[];
      final cliente = MockClient((req) async {
        pedidas.add(req);
        return http.Response.bytes(
          utf8.encode(jsonEncode(_dados)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final sessao = SessaoTrato()..entrar('valor-de-teste');
      final api = ClienteApi(urlBase: 'https://api.teste/', sessao: sessao, cliente: cliente);
      return (RepositorioPedidosApi(api), pedidas);
    }

    test('manda PATCH só com o que mudou e lê o endereço de volta', () async {
      final (repo, pedidas) = montar();
      final novos = await repo.editar(
        'abcd1234',
        descricao: 'Sala de 35 m2',
        faixaMaxCentavos: 90000,
        logradouro: ' Rua das Flores ',
        numero: '10',
        bairro: 'Centro',
      );
      final req = pedidas.single;
      expect(req.method, 'PATCH');
      expect(req.url.path, '/v1/pedidos/abcd1234');
      final corpo = jsonDecode(req.body) as Map<String, dynamic>;
      expect(corpo['faixa_preco_max_centavos'], 90000);
      expect((corpo['endereco'] as Map)['logradouro'], 'Rua das Flores');
      expect(novos.enderecoResumo, 'Rua das Flores, 10 · Centro');
      expect(novos.faixaMaxCentavos, 90000);
    });

    test('sem rua não manda endereço', () async {
      final (repo, pedidas) = montar();
      await repo.editar('abcd1234', faixaMaxCentavos: 0);
      final corpo = jsonDecode(pedidas.single.body) as Map<String, dynamic>;
      expect(corpo.containsKey('endereco'), isFalse);
      expect(corpo['faixa_preco_max_centavos'], 0);
    });

    test('dados lê GET /dados', () async {
      final (repo, pedidas) = montar();
      final d = await repo.dados('abcd1234');
      expect(pedidas.single.url.path, '/v1/pedidos/abcd1234/dados');
      expect(d.descricao, 'Sala de 35 m2');
    });
  });
}
