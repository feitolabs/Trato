import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/config.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/conclusao/dados_exemplo.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';

const _pedidoJson = {
  'id': 'abcd1234',
  'estado': 'em_andamento',
  'estado_nome': 'Em andamento',
  'cliente_id': 'c1',
  'profissional_id': 'p1',
  'aberto_em': '2026-10-27T12:00:00Z',
  'janela': null,
  'concluido_em': null,
  'acoes_permitidas': <String>[],
  'codigo_inicio': '4821',
  'codigo_conclusao': '7310',
};

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _Chamada {
  _Chamada(this.metodo, this.caminho, this.corpo, this.autorizacao);

  final String metodo;
  final String caminho;
  final Map<String, dynamic>? corpo;
  final String? autorizacao;
}

/// Cliente com resposta simulada; guarda o que o app mandou.
(ClienteApi, List<_Chamada>) _cliente(
  http.Response Function(http.Request) responder, {
  bool comSessao = true,
  Duration tempoLimite = const Duration(seconds: 5),
}) {
  final chamadas = <_Chamada>[];
  final sessao = SessaoTrato();
  if (comSessao) sessao.entrar('valor-de-teste');
  final api = ClienteApi(
    urlBase: 'https://api.teste/',
    sessao: sessao,
    tempoLimite: tempoLimite,
    cliente: MockClient((req) async {
      chamadas.add(
        _Chamada(
          req.method,
          req.url.path + (req.url.hasQuery ? '?${req.url.query}' : ''),
          req.body.isEmpty ? null : jsonDecode(req.body) as Map<String, dynamic>,
          req.headers['Authorization'],
        ),
      );
      return responder(req);
    }),
  );
  return (api, chamadas);
}

void main() {
  group('ConfigTrato', () {
    test('modo padrão é demonstração e não usa a rede', () {
      final c = ConfigTrato.doAmbiente();
      expect(c.modo, ModoTrato.demo);
      expect(c.usaApi, isFalse);
    });

    test('modo api sem URL cai em demonstração', () {
      expect(const ConfigTrato(modo: ModoTrato.api).usaApi, isFalse);
      expect(const ConfigTrato(modo: ModoTrato.api, apiUrl: 'https://x').usaApi, isTrue);
    });
  });

  group('ClienteApi', () {
    test('monta a URL, manda o token e lê o JSON', () async {
      final (api, chamadas) = _cliente((_) => _json({'ok': true}));

      final resposta = await api.get('/v1/pedidos', consulta: {'limite': '5'});

      expect(resposta, {'ok': true});
      expect(chamadas.single.caminho, '/v1/pedidos?limite=5');
      expect(chamadas.single.autorizacao, 'Bearer valor-de-teste');
    });

    test('sem sessão não manda Authorization', () async {
      final (api, chamadas) = _cliente((_) => _json([]), comSessao: false);
      await api.get('/v1/pedidos');
      expect(chamadas.single.autorizacao, isNull);
    });

    test('401 vira "sessão expirada"', () async {
      final (api, _) = _cliente((_) => _json({'detail': 'x'}, 401));
      await expectLater(
        api.get('/v1/pedidos'),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.sessaoExpirada)),
      );
    });

    test('500 vira erro do servidor, sem vazar o corpo', () async {
      final (api, _) = _cliente((_) => http.Response('Traceback secreto', 500));
      await expectLater(
        api.get('/v1/pedidos'),
        throwsA(
          isA<ErroTrato>()
              .having((e) => e.tipo, 'tipo', TipoErro.servidor)
              .having((e) => e.mensagem, 'mensagem', isNot(contains('Traceback'))),
        ),
      );
    });

    test('409 mostra o motivo que o backend explicou', () async {
      final (api, _) = _cliente((_) => _json({'detail': 'Esse orçamento não existe.'}, 409));
      await expectLater(
        api.post('/v1/x', corpo: {}),
        throwsA(
            isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', 'Esse orçamento não existe.')),
      );
    });

    test('falha de conexão e tempo esgotado viram "sem internet"', () async {
      final (semRede, _) = _cliente((_) => throw http.ClientException('sem rede'));
      await expectLater(
        semRede.get('/v1/pedidos'),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.semInternet)),
      );

      final sessao = SessaoTrato();
      final lento = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        tempoLimite: const Duration(milliseconds: 10),
        cliente: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        lento.get('/v1/pedidos'),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.semInternet)),
      );
    });
  });

  group('RepositorioPedidosApi', () {
    test('lista separa em andamento de finalizados e guarda o id', () async {
      final (api, chamadas) = _cliente(
        (_) => _json([
          _pedidoJson,
          {..._pedidoJson, 'id': 'zzzz9999', 'estado': 'concluido', 'estado_nome': 'Concluído'},
        ]),
      );

      final lista = await RepositorioPedidosApi(api).listar();

      expect(chamadas.single.caminho, '/v1/pedidos');
      expect(lista.emAndamento.single.id, 'abcd1234');
      expect(lista.emAndamento.single.estadoApi, 'em_andamento');
      expect(lista.emAndamento.single.statusTexto, startsWith('Em execução'));
      expect(lista.finalizados.single.statusTexto, 'Finalizado');
    });

    test('criar abre o pedido e devolve o id', () async {
      final (api, chamadas) = _cliente((_) => _json(_pedidoJson, 201));

      final id = await RepositorioPedidosApi(api).criar(
        const RascunhoPedido(
          servicos: ['Tomadas'],
          quantidade: 2,
          voltagem: '127 V',
          descricao: 'Trocar',
          prazo: 'Esta semana',
          faixa: FaixaPreco(minimoCentavos: 0, maximoCentavos: 30000),
        ),
      );

      expect(id, 'abcd1234');
      expect(chamadas.single.metodo, 'POST');
      expect(chamadas.single.caminho, '/v1/pedidos');
    });

    test('acompanhar monta a linha do tempo e traz o código de início', () async {
      final (api, _) = _cliente((req) {
        if (req.url.path.endsWith('/eventos')) {
          return _json([
            {
              'acao': 'aceitar_orcamento',
              'de': 'aberto',
              'para': 'orcamento_aceito',
              'ator_papel': 'cliente',
              'ator_id': 'c1',
              'em': '2026-10-27T15:00:00Z',
            },
          ]);
        }
        return _json(_pedidoJson);
      });

      final p = await RepositorioPedidosApi(api).acompanhar('abcd1234');

      expect(p.codigoInicio, '4821');
      expect(p.etapas.map((e) => e.titulo), [
        'Contratado',
        'A caminho',
        'Chegou',
        'Em execução',
        'Finalizado',
      ]);
      expect(p.etapas[0].detalhe, isNotEmpty);
    });

    test('confirmar conclusão e retrabalho usam as rotas certas', () async {
      final (api, chamadas) = _cliente(
        (req) => _json(req.url.path.endsWith('retrabalho') ? {'x': 1} : _pedidoJson, 201),
      );
      final repo = RepositorioPedidosApi(api);

      await repo.confirmarConclusao('abcd1234');
      await repo.pedirRetrabalho('abcd1234', 'Tomada solta');

      expect(chamadas[0].caminho, '/v1/pedidos/abcd1234/acoes/confirmar_conclusao');
      expect(chamadas[1].caminho, '/v1/pedidos/abcd1234/retrabalho');
      expect(chamadas[1].corpo, {'descricao': 'Tomada solta', 'fotos': <Object?>[]});
    });

    test('relatar problema abre a disputa; o valor congelado é do backend', () async {
      final (api, chamadas) = _cliente((_) => _json({}, 201));
      final repo = RepositorioPedidosApi(api);

      await repo.relatarProblema(
        'abcd1234',
        const EnvioRelato(
          motivo: 'Dano no local',
          descricao: 'Quebrou o azulejo',
          solucao: 'Reembolso parcial',
        ),
      );

      expect(chamadas.single.caminho, '/v1/pedidos/abcd1234/disputa');
      expect(chamadas.single.corpo!['motivo'], 'dano');
      expect(chamadas.single.corpo!.containsKey('valor'), isFalse);
    });

    test('dados do relato trazem o valor congelado calculado pelo backend', () async {
      final (api, _) = _cliente(
        (req) => req.url.path.endsWith('/saldo')
            ? _json({
                'pedido_id': 'abcd1234',
                'cliente_pagou_centavos': 20000,
                'retido_centavos': 12000,
                'a_liberar_centavos': 8000,
                'liberado_centavos': 0,
                'taxa_trato_centavos': 0,
              })
            : _json(_pedidoJson),
      );

      final dados = await RepositorioPedidosApi(api).dadosRelato('abcd1234');

      expect(dados.valorCongeladoCentavos, 20000);
    });
  });

  group('Orçamentos e pagamento', () {
    test('aceitar só manda o id do orçamento; taxa e líquido não saem do app', () async {
      final (api, chamadas) = _cliente((_) => _json(_pedidoJson));

      await RepositorioOrcamentosApi(api).aceitar('abcd1234', 'orc-1');

      expect(chamadas.single.caminho, '/v1/pedidos/abcd1234/acoes/aceitar_orcamento');
      expect(chamadas.single.corpo, {
        'prova': {'orcamento_id': 'orc-1'},
      });
    });
  });

  group('Profissional', () {
    test('extrato (D15) vira linhas do ledger, sem saldo próprio', () async {
      final (api, chamadas) = _cliente(
        (_) => _json({
          'itens': [
            {
              'id': 'l1',
              'pedido_id': 'abcd1234',
              'tipo': 'repasse',
              'valor_centavos': 46250,
              'data': '2026-10-26T10:00:00Z',
              'debito': {'tipo': 'a', 'titular': null},
              'credito': {'tipo': 'b', 'titular': 'p1'},
              'estorno_de': null,
            },
          ],
          'total': 1,
          'limite': 50,
          'deslocamento': 0,
        }),
      );

      final itens = await RepositorioProfissionalApi(api).extrato();

      expect(chamadas.single.caminho, startsWith('/v1/extrato'));
      expect(itens.single.brutoCentavos, 46250);
      expect(itens.single.titulo, contains('#ABCD'));
      expect(itens.single.status, StatusExtrato.liberado);
    });
  });

  group('ServicoCheckInApi', () {
    ServicoCheckInApi servico(ClienteApi api, {bool captura = true}) => ServicoCheckInApi(
          api,
          pedidoId: 'abcd1234',
          captura: captura ? _CapturaFalsa() : const CapturaIndisponivel(),
        );

    test('manda foto, localização e código; quem confere é o backend', () async {
      final (api, chamadas) = _cliente((_) => _json(_pedidoJson));
      final s = servico(api);
      await s.tirarFoto();
      await s.localizar();

      final r = await s.iniciarServico('4821');

      expect(r, ResultadoInicio.iniciado);
      final prova = chamadas.single.corpo!['prova'] as Map<String, dynamic>;
      expect(prova['codigo_inicio'], '4821');
      expect((prova['foto'] as Map)['arquivo_id'], 'arq-1');
      expect(prova['localizacao'], {'latitude': -23.5, 'longitude': -46.6});
    });

    test('código recusado pelo backend vira "código incorreto"', () async {
      final (api, _) = _cliente((_) => _json({'detail': 'Código errado.'}, 409));
      final s = servico(api);
      await s.tirarFoto();
      await s.localizar();

      expect(await s.iniciarServico('0000'), ResultadoInicio.codigoIncorreto);
    });

    test('sem foto e localização não chama o backend', () async {
      final (api, chamadas) = _cliente((_) => _json(_pedidoJson));
      final s = servico(api, captura: false);
      await s.tirarFoto();
      await s.localizar();

      await expectLater(s.iniciarServico('4821'), throwsA(isA<ErroTrato>()));
      expect(chamadas, isEmpty);
    });

    test('check-out manda a foto final e o código de conclusão', () async {
      final (api, chamadas) = _cliente((_) => _json(_pedidoJson));

      await servico(api).fazerCheckOut(
        fotoFinal: FotoCapturada(arquivoId: 'arq-2', tiradaEm: DateTime.utc(2026, 10, 29, 18)),
        codigo: '7310',
      );

      expect(chamadas.single.caminho, '/v1/pedidos/abcd1234/acoes/fazer_check_out');
      expect(
        (chamadas.single.corpo!['prova'] as Map)['codigo_conclusao'],
        '7310',
      );
    });
  });
}

class _CapturaFalsa implements CapturaCheckIn {
  @override
  Future<FotoCapturada?> foto() async =>
      FotoCapturada(arquivoId: 'arq-1', tiradaEm: DateTime.utc(2026, 10, 29, 17, 6));

  @override
  Future<PosicaoCapturada?> posicao() async => const PosicaoCapturada(-23.5, -46.6);
}
