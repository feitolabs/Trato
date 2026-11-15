// Telas que antes mostravam texto ou valor fixo no lugar do dado real (v0.1.24).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/config_publica.dart';
import 'package:trato/dados/modelos_api.dart' show PedidoApi;
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/agenda/agenda_tela.dart';
import 'package:trato/telas/agenda/modelos.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/orcamentos/modelos.dart' show semAvaliacoes;
import 'package:trato/tema/tema.dart';

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

ClienteApi _api(http.Response Function(http.Request) responder) => ClienteApi(
      urlBase: 'https://api.teste/',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((r) async => responder(r)),
    );

Map<String, Object?> _pedido(String id, String estado, {Map<String, Object?> extra = const {}}) =>
    {
      'id': id,
      'estado': estado,
      'estado_nome': estado,
      'cliente_id': 'c1',
      'profissional_id': 'me',
      'aberto_em': '2026-11-07T12:00:00Z',
      'janela': null,
      'concluido_em': null,
      'acoes_permitidas': <String>[],
      'codigo_inicio': null,
      'codigo_conclusao': null,
      ...extra,
    };

Widget _app(Widget filho) => MaterialApp(theme: TemaTrato.claro, home: filho);

void main() {
  tearDown(() => ConfigPublica.atual = const ConfigPublica());

  group('Título do serviço no lugar de "Pedido #XXXX"', () {
    test('usa o título do servidor; sem título, o número', () {
      final com = PedidoApi.deJson(_pedido('ab12cd34', 'aberto', extra: {'titulo': 'Pintura'}));
      expect(com.rotulo, 'Pintura');
      final sem = PedidoApi.deJson(_pedido('ab12cd34', 'aberto'));
      expect(sem.rotulo, 'Pedido #AB12');
      final branco = PedidoApi.deJson(_pedido('ab12cd34', 'aberto', extra: {'titulo': '  '}));
      expect(branco.rotulo, 'Pedido #AB12');
    });

    test('a lista do cliente mostra o título e leva o número no subtítulo', () async {
      final api = _api((r) => _json([
            _pedido('ab12cd34', 'aberto', extra: {'titulo': 'Montagem de móveis'}),
          ]));
      final lista = await RepositorioPedidosApi(api).listar();
      final p = lista.emAndamento.single;
      expect(p.titulo, 'Montagem de móveis');
      expect(p.subtitulo, contains('Pedido #AB12'));
    });

    test('o profissional vê o título e o nome do cliente nos contratados', () async {
      final api = _api((r) {
        switch (r.url.path) {
          case '/v1/me':
            return _json({'id': 'me', 'nome': 'Ana Souza'});
          case '/v1/profissional/pedidos-abertos':
            return _json(<Object>[]);
          case '/v1/profissionais/me/saldo':
            return _json({'a_liberar_centavos': 0, 'liberado_centavos': 0});
          case '/v1/pedidos':
            return _json([
              _pedido('ab12cd34', 'agendado', extra: {
                'titulo': 'Pintura de sala',
                'cliente_nome': 'Mariana S.',
                'modalidade': 'remoto',
              }),
            ]);
        }
        return _json(<Object>[]);
      });
      final inicio = await RepositorioProfissionalApi(api).inicio();
      final c = inicio.contratados.single;
      expect(c.titulo, 'Pintura de sala');
      expect(c.cliente, 'Mariana S.');
      expect(inicio.proximo?.titulo, 'Pintura de sala · Mariana S.');
    });
  });

  group('Orçamentos recebidos', () {
    http.Response responder(http.Request r) {
      switch (r.url.path) {
        case '/v1/pedidos/p1':
          return _json(_pedido('p1', 'aberto', extra: {
            'aberto_em': DateTime.now().toUtc().subtract(const Duration(hours: 10)).toIso8601String(),
          }));
        case '/v1/pedidos/p1/orcamentos':
          return _json([
            {
              'id': 'o1',
              'profissional_id': 'pro1',
              'profissional_nome': 'Gabriel L.',
              'valor_centavos': 70500,
              'profissional_nota': 4.0,
              'profissional_servicos_concluidos': 1,
              'profissional_nivel_verificacao': 'verificado',
            },
            {
              'id': 'o2',
              'profissional_id': 'pro2',
              'profissional_nome': 'Novo P.',
              'valor_centavos': 50000,
              'profissional_nota': null,
              'profissional_servicos_concluidos': 0,
              'profissional_nivel_verificacao': 'basico',
            },
          ]);
      }
      return _json({'detail': 'não'}, 404);
    }

    test('nota, serviços e selo que o servidor manda; sem nota, "Sem avaliações"', () async {
      final r = await RepositorioOrcamentosApi(_api(responder)).listar('p1');
      final gabriel = r.orcamentos.firstWhere((o) => o.id == 'o1');
      expect(gabriel.notaResumo, '4,0');
      expect(gabriel.servicosResumo, '1');
      expect(gabriel.verificacao, 'Verificado');
      final novo = r.orcamentos.firstWhere((o) => o.id == 'o2');
      expect(novo.notaResumo, semAvaliacoes);
      expect(novo.verificacao, ''); // nível básico: sem selo
    });

    test('limite e tempo restante vêm da configuração', () async {
      ConfigPublica.atual = const ConfigPublica(limiteOrcamentos: 4, validadePedidoHoras: 48);
      final r = await RepositorioOrcamentosApi(_api(responder)).listar('p1');
      expect(r.pedido.limite, 4);
      expect(r.pedido.tempoRestante, anyOf('37 horas', '38 horas')); // 48 h - ~10 h
    });
  });

  group('Configuração pública', () {
    test('lê os prazos e ignora valores inválidos', () {
      final c = ConfigPublica.deJson({
        'limite_orcamentos_por_pedido': 3,
        'validade_pedido_horas': 24,
        'prazo_confirmacao_cliente_horas': 72,
        'prazo_retrabalho_atendimento_dias': 10,
        'prazo_resposta_disputa_horas': 'x',
        'prazo_liberacao_dias': 2,
      });
      expect(c.limiteOrcamentos, 3);
      expect(c.validadePedidoHoras, 24);
      expect(c.prazoConfirmacaoHoras, 72);
      expect(c.prazoRetrabalhoDias, 10);
      expect(c.prazoRespostaDisputaHoras, 48); // padrão
      expect(c.textoLiberacao, contains('em até 2 dias'));
      expect(const ConfigPublica().textoLiberacao, isNot(contains('em até')));
    });

    test('carrega do servidor sem login; erro mantém o que estava', () async {
      await ConfigPublica.carregar(_api((r) => _json({'limite_orcamentos_por_pedido': 7})));
      expect(ConfigPublica.atual.limiteOrcamentos, 7);
      await ConfigPublica.carregar(_api((r) => _json({'detail': 'fora'}, 500)));
      expect(ConfigPublica.atual.limiteOrcamentos, 7);
    });

    test('o formulário do pedido usa os números da configuração', () async {
      ConfigPublica.atual = const ConfigPublica(limiteOrcamentos: 3, validadePedidoHoras: 24);
      final api = _api((r) {
        if (r.url.path == '/v1/catalogo/categorias') {
          return _json([
            {'id': 'c1', 'nome': 'Pintura', 'slug': 'pintura'},
          ]);
        }
        if (r.url.path == '/v1/catalogo/cidades') {
          return _json([
            {'id': 'cid-1', 'nome': 'Divinopolis', 'uf': 'MG'},
          ]);
        }
        return _json(<Object>[]);
      });
      final f = await RepositorioCatalogoApi(api).formulario('c1');
      expect(f.avisoPrazo, 'Você recebe até 3 orçamentos em 24 horas.');
    });
  });

  group('Conclusão e avaliação', () {
    test('o aditivo pago aparece separado do orçamento', () async {
      final api = _api((r) {
        switch (r.url.path) {
          case '/v1/pedidos/p1':
            return _json(_pedido('p1', 'em_confirmacao'));
          case '/v1/pedidos/p1/saldo':
            return _json({
              'cliente_pagou_centavos': 115500,
              'retido_centavos': 0,
              'a_liberar_centavos': 0,
              'liberado_centavos': 0,
              'taxa_trato_centavos': 0,
            });
          case '/v1/contratos/p1/aditivos':
            return _json([
              {'id': 'a1', 'descricao': 'Horas', 'valor_centavos': 45000, 'estado': 'pago'},
              {'id': 'a2', 'descricao': 'Outro', 'valor_centavos': 9000, 'estado': 'proposto'},
            ]);
        }
        return _json(<Object>[]);
      });
      final r = await RepositorioPedidosApi(api).conclusao('p1');
      expect(r.aditivoCentavos, 45000);
      expect(r.orcamentoCentavos, 70500);
    });

    testWidgets('sem gorjeta no servidor, a tela não oferece gorjeta', (t) async {
      await t.pumpWidget(
        _app(
          AvaliacaoTela(
            dados: const DadosAvaliacao(
              nomeProfissional: 'Gabriel L.',
              valorLiberadoCentavos: 70500,
              criterios: ['Qualidade'],
              gorjetasCentavos: [1000, 2000],
              gorjetaDisponivel: false,
            ),
            aoEnviar: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Gorjeta (opcional)'), findsNothing);
      expect(find.textContaining('pagos'), findsOneWidget);
    });
  });

  group('Agenda', () {
    testWidgets('sem data marcada não aparece em "Hoje"', (t) async {
      await t.pumpWidget(
        _app(
          AgendaTela(
            hoje: DateTime(2026, 11, 14),
            carregar: () async => [
              Agendamento(
                id: 'a',
                pedidoId: 'a',
                dia: DateTime(2026, 11, 14),
                horario: 'Data da visita ainda não marcada',
                titulo: 'Pintura',
                local: 'Rua X',
                semData: true,
                cliente: 'Mariana S.',
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('SEM DATA MARCADA'), findsOneWidget);
      expect(find.text('HOJE'), findsNothing);
      expect(find.text('Cliente: Mariana S.'), findsOneWidget);
    });
  });
}
