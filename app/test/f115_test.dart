// TERMOS-APP-1412: a localização só é lida no check-in e no check-out (Termos 14.12).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cache_leitura.dart';
import 'package:trato/dados/config.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_localizacao.dart';
import 'package:trato/telas/lgpd/modelos.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';

import 'apoio/exemplos/dados/servico_upload_fake.dart';
import 'apoio/exemplos/dispositivo/servico_camera_fake.dart';
import 'apoio/exemplos/dispositivo/servico_localizacao_fake.dart';

class _Localizacao extends ServicoLocalizacaoFake {
  var leituras = 0;

  @override
  Future<PosicaoAtual> posicaoAtual() {
    leituras++;
    return super.posicaoAtual();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// O app montado como em produção (`deConfig`), com o aparelho tendo localização.
  (RepositoriosTrato, _Localizacao, List<http.Request>) montar() {
    final pedidas = <http.Request>[];
    final gps = _Localizacao();
    final repos = http.runWithClient(
      () => RepositoriosTrato.deConfig(
        const ConfigTrato(apiUrl: 'https://api.teste'),
        SessaoTrato()..entrar('t'),
        criarUpload: (_) => ServicoUploadFake(),
        camera: ServicoCameraFake(),
        localizacao: gps,
        cache: CacheLeitura(CacheMemoria(), usuarioId: () => null),
      ),
      () => MockClient((req) async {
        pedidas.add(req);
        final criar = req.method == 'POST' && req.url.path == '/v1/pedidos';
        final corpo = criar
            ? {
                'id': 'ab12cd34',
                'estado': 'aberto',
                'estado_nome': 'Aberto',
                'cliente_id': 'c1',
                'aberto_em': '2026-11-26T10:00:00Z',
                'acoes_permitidas': <String>[],
              }
            : <Object>[];
        return http.Response(jsonEncode(corpo), criar ? 201 : 200,
            headers: const {'content-type': 'application/json'});
      }),
    );
    return (repos, gps, pedidas);
  }

  test('enviar pedido presencial não lê a posição; o endereço digitado vai', () async {
    final (repos, gps, pedidas) = montar();
    final id = await repos.pedidos.criar(const RascunhoPedido(
      servicos: ['Instalação'],
      quantidade: 1,
      voltagem: '',
      descricao: 'Trocar tomada',
      prazo: 'Esta semana',
      faixa: FaixaPreco(minimoCentavos: 0, maximoCentavos: 0),
      categoriaId: 'cat',
      cidadeId: 'bh',
      modalidade: Modalidade.presencial,
      endereco: EnderecoRascunho(
          cep: '30140-000', logradouro: 'Rua A', numero: '10', bairro: 'Savassi'),
    ));
    expect(id, isNotEmpty);
    final post = pedidas.singleWhere((r) => r.url.path == '/v1/pedidos' && r.method == 'POST');
    final corpo = jsonDecode(post.body) as Map<String, dynamic>;
    expect(corpo.keys.where((k) => k.contains('lat') || k.contains('lng')), isEmpty);
    expect(corpo['bairro'], 'Savassi');
    expect((corpo['endereco'] as Map)['logradouro'], 'Rua A');
    expect(gps.leituras, 0);
  });

  test('a lista de pedidos do profissional não lê nem envia a posição', () async {
    final (repos, gps, pedidas) = montar();
    await repos.profissional.pedidosAbertos(const FiltroPedidosAbertos(limite: 20));
    final q = pedidas
        .singleWhere((r) => r.url.path == '/v1/profissional/pedidos-abertos')
        .url
        .queryParameters;
    expect(q.keys, isNot(contains('lat')));
    expect(q.keys, isNot(contains('lng')));
    expect(gps.leituras, 0);
  });

  test('o consentimento de localização fala só de check-in e check-out', () {
    final c = consentimentosPadrao.singleWhere((c) => c.id == 'localizacao');
    expect(c.descricao, contains('check-in e check-out'));
    expect(c.descricao, isNot(contains('perto')));
  });
}
