import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/ligacao_sessao.dart';
import 'package:trato/auth/servico_auth_fake.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/aditivo/aditivo.dart';
import 'package:trato/telas/conclusao/dados_exemplo.dart';
import 'package:trato/telas/nota_material/nota_material.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/verificacao/verificacao.dart';

// TESTES DE CONTRATO. Cada repositório fala com um HTTP simulado e confere método, caminho,
// corpo e a leitura da resposta. Os exemplos de resposta são copiados de `docs/api-rotas.md`
// (e, onde a doc não traz exemplo, dos modelos de `backend/src/trato/api/`).

const _pedido = {
  'id': 'ab12cd34',
  'estado': 'orcamento_aceito',
  'estado_nome': 'Orçamento aceito',
  'cliente_id': 'c1',
  'profissional_id': 'p1',
  'aberto_em': '2026-10-27T12:00:00Z',
  'concluido_em': null,
  'acoes_permitidas': <String>[],
  'codigo_inicio': null,
  'codigo_conclusao': null,
};

class _Chamada {
  _Chamada(this.metodo, this.caminho, this.consulta, this.corpo, this.autorizacao, this.idem);

  final String metodo;
  final String caminho;
  final Map<String, String> consulta;
  final Object? corpo;
  final String? autorizacao;
  final String? idem;
}

typedef _Rota = (int, Object?);

/// `rotas` mapeia "MÉTODO /caminho" para (status, corpo). Rota fora da tabela falha o teste.
(ClienteApi, List<_Chamada>) _api(Map<String, _Rota> rotas, {SessaoTrato? sessao}) {
  final chamadas = <_Chamada>[];
  final s = sessao ?? (SessaoTrato()..entrar('valor-de-teste'));
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: s,
    cliente: MockClient((req) async {
      chamadas.add(
        _Chamada(
          req.method,
          req.url.path,
          req.url.queryParameters,
          req.body.isEmpty ? null : jsonDecode(req.body),
          req.headers['Authorization'],
          req.headers['Idempotency-Key'],
        ),
      );
      final r = rotas['${req.method} ${req.url.path}'];
      if (r == null) fail('rota inesperada: ${req.method} ${req.url.path}');
      return http.Response(
        jsonEncode(r.$2),
        r.$1,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return (api, chamadas);
}

void main() {
  group('Orçamentos', () {
    final rotas = <String, _Rota>{
      'GET /v1/pedidos/ab12cd34': (200, _pedido),
      'GET /v1/pedidos/ab12cd34/orcamentos': (
        200,
        [
          {
            'id': 'o1',
            'profissional_id': 'p1',
            'profissional_nome': 'Carlos Mendes',
            'versao': 1,
            'valor_centavos': 46000,
            'prazo_execucao_dias': 2,
            'garantia_dias': 90,
            'observacoes': 'Levo o material',
            'enviado_em': '2026-10-28T10:00:00Z',
            'aceito': false,
          },
        ],
      ),
      'GET /v1/orcamentos/o1': (
        200,
        {
          'id': 'o1',
          'profissional_id': 'p1',
          'profissional_nome': 'Carlos Mendes',
          'versao': 1,
          'valor_centavos': 46000,
          'prazo_execucao_dias': 2,
          'garantia_dias': 90,
          'observacoes': null,
          'enviado_em': '2026-10-28T10:00:00Z',
          'aceito': false,
          'status': 'enviado',
          'validade_ate': '2026-11-05T00:00:00Z',
          'fora_do_escopo': 'Infiltração',
          'sinal_material_centavos': 12000,
          'itens': [
            {
              'tipo': 'mao_de_obra',
              'descricao': 'Instalação',
              'quantidade': '1.00',
              'valor_unitario_centavos': 34000,
              'total_centavos': 34000,
            },
          ],
        },
      ),
    };

    test('lista e detalhe vêm da API; nada de taxa ou líquido', () async {
      final (api, chamadas) = _api(rotas);

      final r = await RepositorioOrcamentosApi(api).listar('ab12cd34');

      expect(chamadas.map((c) => '${c.metodo} ${c.caminho}'), [
        'GET /v1/pedidos/ab12cd34',
        'GET /v1/pedidos/ab12cd34/orcamentos',
        'GET /v1/orcamentos/o1',
      ]);
      expect(chamadas.every((c) => c.autorizacao == 'Bearer valor-de-teste'), isTrue);
      final o = r.orcamentos.single;
      expect(o.id, 'o1');
      expect(o.profissional, 'Carlos Mendes');
      expect(o.iniciais, 'CM');
      expect(o.totalCentavos, 46000);
      expect(o.garantia, '90 dias');
      expect(o.detalhe!.itens.single.centavos, 34000);
      expect(o.detalhe!.foraDoEscopo, 'Infiltração');
      expect(r.pedido.recebidos, 1);
    });

    test('falha no detalhe de um orçamento não derruba a lista', () async {
      final (api, _) = _api({...rotas, 'GET /v1/orcamentos/o1': (404, {'detail': 'Orçamento não encontrado.'})});

      final r = await RepositorioOrcamentosApi(api).listar('ab12cd34');

      expect(r.orcamentos.single.detalhe, isNull);
    });

    test('aceitar: POST /v1/pedidos/{id}/acoes/aceitar_orcamento só com o id', () async {
      final (api, chamadas) = _api({
        'POST /v1/pedidos/ab12cd34/acoes/aceitar_orcamento': (200, _pedido),
      });

      await RepositorioOrcamentosApi(api).aceitar('ab12cd34', 'o1');

      expect(chamadas.single.corpo, {
        'prova': {'orcamento_id': 'o1'},
      });
    });
  });

  group('Pagamento', () {
    test('dados: valor e meios do backend', () async {
      final (api, chamadas) = _api({
        'GET /v1/pedidos/ab12cd34/pagamento': (
          200,
          {
            'pedido_id': 'ab12cd34',
            'estado': 'orcamento_aceito',
            'valor_centavos': 46000,
            'pago_centavos': 0,
            'pagamento_confirmado': false,
            'meios_disponiveis': ['pix', 'cartao'],
            'cobranca_pendente_id': null,
          },
        ),
      });

      final d = await RepositorioPagamentoApi(api).dados('ab12cd34');

      expect(chamadas.single.metodo, 'GET');
      expect(d.valorAgoraCentavos, 46000);
      expect(d.opcoes.map((o) => o.metodo), [MetodoPagamento.pix, MetodoPagamento.cartao]);
    });

    test('cobrança Pix: POST /v1/contratos/{id}/cobranca {meio} com chave de idempotência', () async {
      final (api, chamadas) = _api({
        'POST /v1/contratos/ab12cd34/cobranca': (
          201,
          {
            'contrato_id': 'ab12cd34',
            'cobranca_id': 'cb1',
            'estado_pagamento': 'aguardando_confirmacao',
            'meio': 'pix',
            'valor_centavos': 46000,
            'tipo_instrucao': 'pix_copia_e_cola',
            'instrucao': '00020126-codigo',
            'criada_em': '2026-10-29T12:00:00Z',
          },
        ),
      });

      final c = await RepositorioPagamentoApi(api).criarCobranca('ab12cd34', MetodoPagamento.pix);

      expect(chamadas.single.corpo, {'meio': 'pix'});
      expect(chamadas.single.idem, 'cobranca-ab12cd34-pix');
      expect(c.id, 'cb1');
      expect(c.pixCopiaECola, '00020126-codigo');
    });

    test('cartão: o segredo do SDK nunca vira texto de tela', () async {
      final (api, _) = _api({
        'POST /v1/contratos/ab12cd34/cobranca': (
          201,
          {
            'contrato_id': 'ab12cd34',
            'cobranca_id': 'cb2',
            'estado_pagamento': 'aguardando_confirmacao',
            'meio': 'cartao',
            'valor_centavos': 46000,
            'tipo_instrucao': 'cartao_segredo_do_cliente',
            'instrucao': 'segredo-do-sdk',
            'criada_em': '2026-10-29T12:00:00Z',
          },
        ),
      });

      final c = await RepositorioPagamentoApi(api).criarCobranca('ab12cd34', MetodoPagamento.cartao);

      expect(c.pixCopiaECola, isNull);
    });

    test('status: só `pago: true` vira pago (D13)', () async {
      Future<StatusPagamento> consultar(Map<String, Object?> j) async {
        final (a, _) = _api({'GET /v1/contratos/ab12cd34/pagamento': (200, j)});
        return RepositorioPagamentoApi(a).status('ab12cd34');
      }

      Map<String, Object?> base(String estado, bool pago) => {
            'contrato_id': 'ab12cd34',
            'estado_pagamento': estado,
            'pago': pago,
            'valor_centavos': 46000,
            'pago_centavos': pago ? 46000 : 0,
            'cobranca_id': 'cb1',
            'meio': 'pix',
            'estado_pedido': 'orcamento_aceito',
          };
      expect(await consultar(base('aguardando_confirmacao', false)), StatusPagamento.aguardando);
      expect(await consultar(base('sem_cobranca', false)), StatusPagamento.aguardando);
      expect(await consultar(base('pago', true)), StatusPagamento.pago);
      expect(await consultar(base('falhou', false)), StatusPagamento.falhou);
      expect(await consultar(base('cancelada', false)), StatusPagamento.falhou);
    });

    test('409 de pedido que não espera pagamento chega como mensagem em português', () async {
      final (api, _) = _api({
        'POST /v1/contratos/ab12cd34/cobranca': (409, {'detail': 'Este pedido já foi pago.'}),
      });

      await expectLater(
        RepositorioPagamentoApi(api).criarCobranca('ab12cd34', MetodoPagamento.pix),
        throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', 'Este pedido já foi pago.')),
      );
    });
  });

  group('Garantia e avaliação', () {
    test('garantia: GET /v1/contratos/{id}/garantia', () async {
      final agora = DateTime.now().toUtc();
      final (api, chamadas) = _api({
        'GET /v1/contratos/ab12cd34/garantia': (
          200,
          {
            'contrato_id': 'ab12cd34',
            'iniciada': true,
            'ativa': true,
            'dias': 90,
            'inicio_em': agora.subtract(const Duration(days: 26)).toIso8601String(),
            'fim_em': agora.add(const Duration(days: 64, hours: 1)).toIso8601String(),
            'retrabalhos': <Object>[],
          },
        ),
      });

      final g = await RepositorioPedidosApi(api).garantia('ab12cd34');

      expect(chamadas.single.caminho, '/v1/contratos/ab12cd34/garantia');
      expect(g.diasTotal, 90);
      expect(g.diasRestantes, 64);
      expect(g.ativa, isTrue);
    });

    test('garantia antes da conclusão: aviso, não erro de servidor', () async {
      final (api, _) = _api({
        'GET /v1/contratos/ab12cd34/garantia': (
          200,
          {
            'contrato_id': 'ab12cd34',
            'iniciada': false,
            'ativa': false,
            'dias': 90,
            'inicio_em': null,
            'fim_em': null,
            'retrabalhos': <Object>[],
          },
        ),
      });

      await expectLater(
        RepositorioPedidosApi(api).garantia('ab12cd34'),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.recusado)),
      );
    });

    test('avaliação: POST /v1/contratos/{id}/avaliacao com nota 1 a 5', () async {
      final (api, chamadas) = _api({
        'POST /v1/contratos/ab12cd34/avaliacao': (
          201,
          {
            'pedido_id': 'ab12cd34',
            'direcao': 'cliente_para_profissional',
            'nota_geral': 5,
            'comentario': 'Ótimo',
            'etiquetas': <String>[],
            'criada_em': '2026-10-29T12:00:00Z',
          },
        ),
      });

      await RepositorioPedidosApi(api).avaliar(
        'ab12cd34',
        const EnvioAvaliacao(notas: [5, 5, 4, 5, 5], comentario: 'Ótimo', gorjetaCentavos: 0),
      );

      expect(chamadas.single.corpo, {'nota_geral': 5, 'comentario': 'Ótimo'});
    });

    test('gorjeta não tem rota: recusa em vez de sumir em silêncio', () async {
      final (api, chamadas) = _api({});

      await expectLater(
        RepositorioPedidosApi(api).avaliar(
          'ab12cd34',
          const EnvioAvaliacao(notas: [5], comentario: '', gorjetaCentavos: 2000),
        ),
        throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', contains('gorjeta'))),
      );
      expect(chamadas, isEmpty);
    });

    test('avaliação sem nenhuma estrela nem chega ao backend', () async {
      final (api, chamadas) = _api({});

      await expectLater(
        RepositorioPedidosApi(api).avaliar(
          'ab12cd34',
          const EnvioAvaliacao(notas: [0, 0], comentario: '', gorjetaCentavos: 0),
        ),
        throwsA(isA<ErroTrato>()),
      );
      expect(chamadas, isEmpty);
    });

    test('avaliar de novo (409) mostra o motivo do backend', () async {
      final (api, _) = _api({
        'POST /v1/contratos/ab12cd34/avaliacao': (409, {'detail': 'Você já avaliou este serviço.'}),
      });

      await expectLater(
        RepositorioPedidosApi(api).avaliar(
          'ab12cd34',
          const EnvioAvaliacao(notas: [4], comentario: '', gorjetaCentavos: 0),
        ),
        throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', 'Você já avaliou este serviço.')),
      );
    });
  });

  group('Chat e notificações', () {
    test('conversa: GET mensagens; enviar: POST {texto}', () async {
      final (api, chamadas) = _api({
        'GET /v1/pedidos/ab12cd34': (200, _pedido),
        'GET /v1/pedidos/ab12cd34/mensagens': (
          200,
          [
            {
              'id': 1,
              'autor_id': 'p1',
              'minha': false,
              'texto': 'Chego às 14h',
              'mascarada': false,
              'enviada_em': '2026-10-29T12:00:00Z',
              'lida_em': null,
            },
            {
              'id': 2,
              'autor_id': 'c1',
              'minha': true,
              'texto': 'Combinado',
              'mascarada': false,
              'enviada_em': '2026-10-29T12:01:00Z',
              'lida_em': '2026-10-29T12:02:00Z',
            },
          ],
        ),
        'POST /v1/pedidos/ab12cd34/mensagens': (201, {'id': 3}),
      });
      final repo = RepositorioChatApi(api);

      final c = await repo.conversa('ab12cd34');
      await repo.enviar('ab12cd34', 'Oi');

      expect(c.mensagens.map((m) => m.texto), ['Chego às 14h', 'Combinado']);
      expect(c.mensagens.map((m) => m.minha), [false, true]);
      expect(c.mensagens.last.lida, isTrue);
      expect(chamadas.last.corpo, {'texto': 'Oi'});
    });

    test('notificações: GET /v1/notificacoes', () async {
      final (api, chamadas) = _api({
        'GET /v1/notificacoes': (
          200,
          [
            {
              'id': 'n1',
              'tipo': 'disputa',
              'titulo': 'Disputa aberta',
              'corpo': 'Responda no prazo',
              'dados': {'pedido_id': 'ab12cd34'},
              'criada_em': '2026-10-01T12:00:00Z',
              'lida': false,
            },
          ],
        ),
      });

      final n = (await RepositorioNotificacoesApi(api).listar()).single;

      expect(chamadas.single.metodo, 'GET');
      expect(n.tipo, 'disputa');
      expect(n.destinoId, 'ab12cd34');
      expect(n.lida, isFalse);
      expect(n.texto, 'Responda no prazo');
    });
  });

  group('Perfil /me', () {
    const me = {
      'id': 'c1',
      'nome': 'Mariana Alves',
      'papel': 'cliente',
      'papeis': ['cliente'],
      'status': 'ativo',
      'nivel_verificacao': null,
      'nota_publica': 4.8,
      'servicos_concluidos': 6,
      'tem_perfil_profissional': false,
      'status_verificacao': null,
    };

    test('GET /v1/me vira o perfil do cliente', () async {
      final (api, chamadas) = _api({'GET /v1/me': (200, me)});

      final p = await RepositorioPerfilApi(api).carregar();

      expect(chamadas.single.autorizacao, 'Bearer valor-de-teste');
      expect(p.nome, 'Mariana Alves');
      expect(p.iniciais, 'MA');
      expect(p.resumo, 'Nota 4,8 · 6 serviços');
    });

    test('PATCH /v1/me {nome}', () async {
      final (api, chamadas) = _api({'PATCH /v1/me': (200, {...me, 'nome': 'Mari'})});

      final nome = await RepositorioPerfilApi(api).atualizarNome('Mari');

      expect(chamadas.single.metodo, 'PATCH');
      expect(chamadas.single.corpo, {'nome': 'Mari'});
      expect(nome, 'Mari');
    });
  });

  group('Profissional', () {
    const abertos = [
      {
        'id': 'pa1',
        'titulo': 'Instalar ventilador',
        'descricao': 'Sala, teto alto',
        'bairro': 'Savassi',
        'categoria_id': 'cat1',
        'faixa_preco_min_centavos': 20000,
        'faixa_preco_max_centavos': 50000,
        'urgente': true,
        'prazo_desejado': null,
        'aberto_em': '2026-10-29T12:00:00Z',
      },
    ];

    test('pedidos abertos: GET com filtros na query', () async {
      final (api, chamadas) = _api({'GET /v1/profissional/pedidos-abertos': (200, abertos)});

      final r = await RepositorioProfissionalApi(api).pedidosAbertos(
        const FiltroPedidosAbertos(
          categoriaId: 'cat1',
          bairro: 'Savassi',
          precoMinCentavos: 10000,
          precoMaxCentavos: 60000,
          ordenar: 'maior_valor',
          limite: 20,
        ),
      );

      expect(chamadas.single.consulta, {
        'categoria_id': 'cat1',
        'bairro': 'Savassi',
        'preco_min_centavos': '10000',
        'preco_max_centavos': '60000',
        'ordenar': 'maior_valor',
        'limite': '20',
      });
      final p = r.single;
      expect(p.titulo, 'Instalar ventilador');
      expect(p.urgente, isTrue);
      expect(p.faixaMinCentavos, 20000);
      expect(p.distanciaKm, isNull, reason: 'a API não devolve distância');
    });

    test('início junta /me, pedidos abertos e o próximo atendimento', () async {
      final (api, _) = _api({
        'GET /v1/me': (200, {'id': 'p1', 'nome': 'Carlos Mendes', 'papel': 'profissional'}),
        'GET /v1/profissional/pedidos-abertos': (200, abertos),
        'GET /v1/pedidos': (200, [_pedido, {..._pedido, 'estado': 'agendado', 'estado_nome': 'Agendado'}]),
      });

      final i = await RepositorioProfissionalApi(api).inicio();

      expect(i.nome, 'Carlos');
      expect(i.pedidos, hasLength(1));
      expect(i.proximo!.pedidoId, 'ab12cd34');
    });

    test('detalhe sai da lista; pedido que sumiu dá aviso', () async {
      final (api, _) = _api({'GET /v1/profissional/pedidos-abertos': (200, abertos)});
      final repo = RepositorioProfissionalApi(api);

      final d = await repo.detalhe('pa1');
      expect(d.descricao, 'Sala, teto alto');

      await expectLater(
        repo.detalhe('nao-existe'),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.naoEncontrado)),
      );
    });

    test('recusar: POST /v1/pedidos/{id}/recusar {motivo}', () async {
      final (api, chamadas) = _api({
        'POST /v1/pedidos/pa1/recusar': (200, {'pedido_id': 'pa1', 'recusado': true}),
      });

      await RepositorioProfissionalApi(api).recusar('pa1', MotivoRecusa.semAgenda);

      expect(chamadas.single.corpo, {'motivo': 'Sem agenda'});
    });

    test('calculadora: taxa e líquido vêm de POST /v1/orcamentos/resumo', () async {
      final (api, chamadas) = _api({
        'POST /v1/orcamentos/resumo': (
          200,
          {
            'valor_centavos': 100000,
            'taxa_centavos': 7000,
            'liquido_centavos': 93000,
            'custo_provedor_estimado_centavos': 500,
            'custo_provedor_estimativa': true,
          },
        ),
      });

      final r = await ServicoOrcamentoApi(api).resumir(100000);

      expect(chamadas.single.corpo, {'valor_centavos': 100000});
      expect(r.taxaCentavos, 7000, reason: 'valor do backend, não calculado no app');
      expect(r.liquidoCentavos, 93000);
      expect(r.taxaBps, isNull);
    });

    test('calculadora sem taxa configurada (503) vira erro de servidor', () async {
      final (api, _) = _api({'POST /v1/orcamentos/resumo': (503, {'detail': 'sem taxa'})});

      await expectLater(
        ServicoOrcamentoApi(api).resumir(100000),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.servidor)),
      );
    });
  });

  group('Aditivo e nota de materiais', () {
    test('aditivo: criar, carregar o proposto, aprovar e recusar', () async {
      final propostos = [
        {'id': 'ad1', 'contrato_id': 'ab12cd34', 'descricao': 'Trocar cabo', 'valor_centavos': 4500, 'estado': 'proposto'},
      ];
      final (api, chamadas) = _api({
        'POST /v1/contratos/ab12cd34/aditivos': (201, propostos.first),
        'GET /v1/contratos/ab12cd34/aditivos': (200, propostos),
        'POST /v1/contratos/ab12cd34/aditivos/ad1/aprovar': (
          200,
          {'aditivo': {...propostos.first, 'estado': 'aprovado'}, 'cobranca': null},
        ),
        'POST /v1/contratos/ab12cd34/aditivos/ad1/recusar': (
          200,
          {'aditivo': {...propostos.first, 'estado': 'recusado'}, 'cobranca': null},
        ),
      });
      final s = ServicoAditivoApi(api);

      await s.criar(const NovoAditivo(pedidoId: 'ab12cd34', motivo: 'Trocar cabo', valorCentavos: 4500));
      final d = await s.carregar('ab12cd34');
      await s.responder('ab12cd34', aprovar: true);
      await s.responder('ab12cd34', aprovar: false);

      expect(chamadas.first.corpo, {'descricao': 'Trocar cabo', 'valor_centavos': 4500});
      expect(d!.id, 'ad1');
      expect(d.valorCentavos, 4500);
      expect(chamadas.map((c) => c.caminho).where((c) => c.endsWith('aprovar')), hasLength(1));
      expect(chamadas.firstWhere((c) => c.caminho.endsWith('aprovar')).corpo, {'meio': 'pix'});
      expect(chamadas.last.caminho, endsWith('/recusar'));
    });

    test('profissional tentando aprovar (403) recebe o motivo', () async {
      final (api, _) = _api({
        'GET /v1/contratos/ab12cd34/aditivos': (
          200,
          [
            {'id': 'ad1', 'contrato_id': 'ab12cd34', 'descricao': 'x', 'valor_centavos': 1, 'estado': 'proposto'},
          ],
        ),
        'POST /v1/contratos/ab12cd34/aditivos/ad1/aprovar': (403, {'detail': 'Só o cliente decide.'}),
      });

      await expectLater(
        ServicoAditivoApi(api).responder('ab12cd34', aprovar: true),
        throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', 'Só o cliente decide.')),
      );
    });

    test('nota de materiais: enviar e ler (total vem do backend)', () async {
      final (api, chamadas) = _api({
        'POST /v1/contratos/ab12cd34/notas-material': (
          201,
          {
            'id': 'nm1',
            'contrato_id': 'ab12cd34',
            'itens': [
              {'descricao': 'Tomada', 'quantidade': '1', 'valor_unitario_centavos': 2300, 'total_centavos': 2300},
            ],
            'total_centavos': 2300,
            'enviada_em': '2026-10-29T12:00:00Z',
          },
        ),
        'GET /v1/contratos/ab12cd34/notas-material': (
          200,
          [
            {
              'id': 'nm1',
              'contrato_id': 'ab12cd34',
              'itens': [
                {'descricao': 'Tomada', 'quantidade': '1', 'valor_unitario_centavos': 2300, 'total_centavos': 2300},
              ],
              'total_centavos': 2300,
              'enviada_em': '2026-10-29T12:00:00Z',
            },
          ],
        ),
      });
      final s = ServicoNotaMaterialApi(api);

      await s.enviar(
        const EnvioNota(
          pedidoId: 'ab12cd34',
          fotoNota: 'u1/nota.jpg',
          itens: [ItemNota(descricao: 'Tomada', centavos: 2300)],
        ),
      );
      final n = await s.carregar('ab12cd34');

      expect(chamadas.first.corpo, {
        'foto_storage_path': 'u1/nota.jpg',
        'itens': [
          {'descricao': 'Tomada', 'quantidade': 1, 'valor_unitario_centavos': 2300},
        ],
      });
      expect(n!.somaCentavos, 2300);
    });
  });

  group('Verificação do profissional', () {
    test('sem verificação anterior: não enviada', () async {
      final (api, _) = _api({'GET /v1/profissional/verificacao': (200, <Object>[])});

      expect((await ServicoVerificacaoApi(api).carregarSituacao()).status, StatusVerificacao.naoEnviada);
    });

    test('lê o status e o motivo da mais recente', () async {
      final (api, _) = _api({
        'GET /v1/profissional/verificacao': (
          200,
          [
            {
              'id': 'v1',
              'nivel_solicitado': 'verificado',
              'status': 'recusada',
              'enviada_em': '2026-10-20T12:00:00Z',
              'documentos': ['documento_frente', 'selfie'],
              'status_app': 'pendente',
              'motivo': 'Foto escura',
              'finalidade': 'Conferir identidade',
              'retencao_dias': 90,
            },
          ],
        ),
      });
      final s = ServicoVerificacaoApi(api);

      final situacao = await s.carregarSituacao();
      final lgpd = await s.carregarTextoLgpd();

      expect(situacao.status, StatusVerificacao.pendente);
      expect(situacao.motivo, 'Foto escura');
      expect(lgpd.finalidade, 'Conferir identidade');
      expect(lgpd.retencao, contains('90'));
    });

    test('enviar: POST com consentimento e os upload_id de documento e selfie', () async {
      final (api, chamadas) = _api({
        'POST /v1/profissional/verificacao': (
          201,
          {
            'id': 'v2',
            'nivel_solicitado': 'verificado',
            'status': 'enviada',
            'enviada_em': '2026-10-29T12:00:00Z',
            'documentos': ['documento_frente', 'selfie'],
            'status_app': 'em_analise',
            'motivo': null,
            'finalidade': 'x',
            'retencao_dias': 90,
          },
        ),
      });

      await ServicoVerificacaoApi(api).enviar(const EnvioVerificacao(documento: 'up-1', selfie: 'up-2'));

      expect(chamadas.single.corpo, {
        'nivel_solicitado': 'verificado',
        'consentimento_lgpd': true,
        'documentos': [
          {'tipo': 'documento_frente', 'upload_id': 'up-1'},
          {'tipo': 'selfie', 'upload_id': 'up-2'},
        ],
      });
    });
  });

  group('Sessão', () {
    test('toda chamada leva o token e 401 limpa a sessão', () async {
      final sessao = SessaoTrato()..entrar('valor-de-teste');
      var expirou = 0;
      sessao.aoExpirar = () => expirou++;
      final (api, chamadas) = _api({
        'GET /v1/me': (401, {'detail': 'Sessão inválida.'}),
      }, sessao: sessao);

      await expectLater(
        RepositorioPerfilApi(api).carregar(),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.sessaoExpirada)),
      );

      expect(chamadas.single.autorizacao, 'Bearer valor-de-teste');
      expect(sessao.logada, isFalse);
      expect(expirou, 1);
    });

    test('o primeiro login chama GET /v1/me (cria o usuário no backend)', () async {
      final auth = ServicoAuthFake();
      final sessao = SessaoTrato();
      final (api, chamadas) = _api({
        'GET /v1/me': (200, {'id': 'c1', 'nome': null, 'papel': 'cliente'}),
      }, sessao: sessao);
      LigacaoSessao(auth, sessao, aoEntrar: () => RepositorioPerfilApi(api).carregar());

      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');
      await Future<void>.delayed(Duration.zero);

      expect(chamadas.single.caminho, '/v1/me');
      expect(chamadas.single.autorizacao, startsWith('Bearer '));
    });

    test('sem rede: mensagem de "sem internet"', () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((_) async => throw http.ClientException('sem rede')),
      );

      await expectLater(
        RepositorioNotificacoesApi(api).listar(),
        throwsA(isA<ErroTrato>().having((e) => e.tipo, 'tipo', TipoErro.semInternet)),
      );
    });
  });
}
