import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_localizacao.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';

const _bh = PosicaoAtual(latitude: -19.91674, longitude: -43.93456, precisaoMetros: 8);

ClienteApi _api(List<http.Request> pedidas, Object resposta, {int status = 200}) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((req) async {
        pedidas.add(req);
        return http.Response.bytes(
          utf8.encode(jsonEncode(resposta)),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

void main() {
  test('profissional manda a posição e recebe distância e ponto do pedido', () async {
    final pedidas = <http.Request>[];
    final api = _api(pedidas, [
      {
        'id': 'p1',
        'titulo': 'Limpeza',
        'bairro': 'Savassi',
        'urgente': false,
        'distancia_km': 2.1,
        'local_aprox_lat': -19.93,
        'local_aprox_lng': -43.94,
        'aberto_em': '2026-11-01T10:00:00Z',
      },
    ]);
    final repo = RepositorioProfissionalApi(api, posicao: () async => _bh);
    final lista = await repo.pedidosAbertos(const FiltroPedidosAbertos());
    final q = pedidas.single.url.queryParameters;
    expect(q['lat'], '-19.91674');
    expect(q['lng'], '-43.93456');
    expect(lista.single.distanciaKm, 2.1);
    expect(lista.single.latitude, -19.93);
  });

  test('sem GPS o app não manda posição e a distância fica indisponível', () async {
    final pedidas = <http.Request>[];
    final api = _api(pedidas, [
      {'id': 'p1', 'titulo': 'Limpeza', 'urgente': false, 'aberto_em': '2026-11-01T10:00:00Z'},
    ]);
    final repo = RepositorioProfissionalApi(api, posicao: () async => null);
    final lista = await repo.pedidosAbertos(const FiltroPedidosAbertos());
    expect(pedidas.single.url.queryParameters.containsKey('lat'), isFalse);
    expect(lista.single.distanciaKm, isNull);
  });

  test('cliente manda a região aproximada (arredondada) ao criar o pedido', () async {
    final pedidas = <http.Request>[];
    final api = _api(pedidas, {
      'id': 'ab12cd34',
      'estado': 'aberto',
      'estado_nome': 'Aberto',
      'cliente_id': 'c1',
      'aberto_em': '2026-11-01T10:00:00Z',
      'acoes_permitidas': <String>[],
    }, status: 201);
    await RepositorioPedidosApi(api, posicao: () async => _bh).criar(
      const RascunhoPedido(
        servicos: ['Limpeza'],
        quantidade: 1,
        voltagem: '',
        descricao: 'Limpar',
        prazo: 'Sem pressa',
        faixa: FaixaPreco(minimoCentavos: 0, maximoCentavos: 50000),
        categoriaId: 'c',
        cidadeId: 'x',
      ),
    );
    final corpo = jsonDecode(pedidas.first.body) as Map<String, dynamic>;
    expect(corpo['local_aprox_lat'], -19.92);
    expect(corpo['local_aprox_lng'], -43.93);
  });
}
