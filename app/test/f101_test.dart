// TERMOS-APP3: prazo da avaliação (12.1), só MEI e avisos obrigatórios vindos da API (15.2).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/linha_do_tempo.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart' show PreferenciaNotificacao;
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/carteira/avaliar_cliente_tela.dart';
import 'package:trato/telas/comuns/prazo_avaliacao.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/notificacoes/preferencias_notificacoes_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional_mei/mei.dart';
import 'package:trato/telas/profissional_mei/meu_cnpj_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(
      theme: TemaTrato.claro,
      builder: (c, f) => EscalaFonteLimitada(child: f!),
      home: tela,
    );

DadosAvaliacao _dados({DateTime? ate, bool encerrado = false}) => DadosAvaliacao(
      nomeProfissional: 'Carlos',
      valorLiberadoCentavos: 10000,
      criterios: const ['Qualidade'],
      gorjetasCentavos: const [],
      gorjetaDisponivel: false,
      avaliarAte: ate,
      prazoEncerrado: encerrado,
    );

PedidoEmExecucao _pedido(PrazoAvaliacao prazo) => PedidoEmExecucao(
      numero: '#AB12',
      titulo: 'Serviço finalizado',
      etapas: const [
        EtapaLinhaDoTempo(titulo: 'Finalizado', detalhe: '', estado: EstadoEtapa.feita),
      ],
      fotos: const [],
      estadoApi: 'concluido',
      prazoAvaliacao: prazo,
    );

/// API simulada: um pedido concluído; [avaliacao] é a resposta do GET da avaliação.
ClienteApi _api(Map<String, dynamic> avaliacao, [List<String>? chamadas]) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        chamadas?.add(req.url.path);
        final Object corpo = switch (req.url.path) {
          '/v1/pedidos/p1' => {
              'id': 'p1',
              'cliente_id': 'cli-1',
              'estado': 'concluido',
              'estado_nome': 'Concluído',
              'aberto_em': '2026-11-20T10:00:00Z',
              'acoes_permitidas': <String>[],
            },
          '/v1/pedidos/p1/saldo' => {
              'cliente_pagou_centavos': 10000,
              'retido_centavos': 0,
              'a_liberar_centavos': 10000,
              'liberado_centavos': 0,
            },
          '/v1/pedidos/p1/avaliacao' => avaliacao,
          _ => <Object>[],
        };
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }),
    );

class _Mei implements ServicoMei {
  _Mei(this.atual, [this.erro]);
  final DadosMei atual;
  final ErroTrato? erro;

  @override
  Future<DadosMei> carregar() async => atual;

  @override
  Future<DadosMei> validar(String cnpjSoDigitos) async => throw erro!;
}

class _Prefs extends RepositorioNotificacoesFake {
  _Prefs(this.itens);
  final List<PreferenciaNotificacao> itens;

  @override
  Future<List<PreferenciaNotificacao>> carregarPreferencias() async => itens;
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);

  group('1. Prazo da avaliação (12.1)', () {
    test('lê avaliar_ate e prazo_encerrado; campo ausente fica como antes', () async {
      final aberto = await RepositorioPedidosApi(
              _api({'avaliar_ate': '2026-12-25T12:00:00Z', 'prazo_encerrado': false}))
          .acompanhar('p1');
      expect(aberto.prazoAvaliacao.ate, isNotNull);
      expect(aberto.prazoAvaliacao.encerrado, isFalse);

      final fechado = await RepositorioPedidosApi(_api({'prazo_encerrado': true})).dadosAvaliacao('p1');
      expect(fechado.prazoEncerrado, isTrue);

      final antigo = await RepositorioPedidosApi(_api({'ja_avaliou': false})).acompanhar('p1');
      expect(antigo.prazoAvaliacao.ate, isNull);
      expect(antigo.prazoAvaliacao.encerrado, isFalse);
    });

    test('lista do profissional: o prazo lido fica guardado e Ver valores esconde o botão',
        () async {
      final chamadas = <String>[];
      final repo = RepositorioProfissionalApi(
          _api({'avaliar_ate': '2099-01-01T00:00:00Z', 'prazo_encerrado': false}, chamadas));
      await repo.prazoDaAvaliacao('p1');
      await repo.prazoDaAvaliacao('p1');
      expect(chamadas, ['/v1/pedidos/p1/avaliacao']);

      final valores = await RepositorioProfissionalApi(_api({'prazo_encerrado': true}))
          .valoresDoPedido('p1');
      expect(valores.podeAvaliarCliente, isFalse);
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

        testWidgets('tela de avaliação: mostra o prazo; encerrado tira o botão ($r)',
            (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(AvaliacaoTela(dados: _dados(ate: DateTime(2026, 12, 25, 14)))));
          await t.pumpAndSettle();
          expect(find.textContaining('Você pode avaliar até 25/12/2026'), findsOneWidget);
          expect(find.text('Enviar avaliação'), findsOneWidget);

          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(AvaliacaoTela(dados: _dados(encerrado: true))));
          await t.pumpAndSettle();
          expect(find.text(textoPrazoEncerrado), findsOneWidget);
          expect(find.text('Enviar avaliação'), findsNothing);
          expect(t.takeException(), isNull);
        });

        testWidgets('409 ao enviar: mostra o motivo do servidor e tira o botão ($r)',
            (t) async {
          await _janela(t, tamanho, fonte);
          const motivo = 'O prazo para avaliar (30 dias após a conclusão do pedido) terminou.';
          await t.pumpWidget(_app(AvaliacaoTela(
            dados: _dados(),
            notasIniciais: const [5],
            aoEnviar: (_) async =>
                throw const ErroTrato(TipoErro.recusado, motivo, codigoHttp: 409),
          )));
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('avaliar-ate')), findsNothing);
          await t.tap(find.text('Enviar avaliação'));
          await t.pumpAndSettle();
          expect(find.text(motivo), findsOneWidget);
          expect(find.text('Enviar avaliação'), findsNothing);
          expect(t.takeException(), isNull);
        });

        testWidgets('pedido concluído: botão some depois do prazo ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          Widget tela(PrazoAvaliacao p) => _app(PedidoExecucaoTela(
                pedido: _pedido(p),
                aoAvaliar: () {},
                aoVerGarantia: () {},
              ));
          await t.pumpWidget(tela(PrazoAvaliacao(ate: DateTime(2026, 12, 25, 14))));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(find.byKey(const ValueKey('prazo-avaliacao')), 150,
              scrollable: find.byType(Scrollable).first);
          expect(find.text('Avaliar'), findsOneWidget);

          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(tela(const PrazoAvaliacao(encerrado: true)));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(find.byKey(const ValueKey('prazo-avaliacao')), 150,
              scrollable: find.byType(Scrollable).first);
          expect(find.text('Avaliar'), findsNothing);
          expect(find.text(textoPrazoEncerrado), findsOneWidget);
          expect(find.textContaining('Ver garantia'), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets('avaliar o cliente: encerrado e 409 tiram o botão ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(AvaliarClienteTela(
            pedidoNumero: '#AB12',
            prazo: const PrazoAvaliacao(encerrado: true),
            aoEnviar: (_, __) async => 0,
          )));
          await t.pumpAndSettle();
          expect(find.text(textoPrazoEncerrado), findsOneWidget);
          expect(find.text('Enviar avaliação'), findsNothing);

          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(AvaliarClienteTela(
            pedidoNumero: '#AB12',
            aoEnviar: (_, __) async => throw const ErroTrato(
                TipoErro.recusado, 'O prazo terminou.',
                codigoHttp: 409),
          )));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('estrela_Nota do cliente_5')));
          await t.pumpAndSettle();
          await t.tap(find.text('Enviar avaliação'));
          await t.pumpAndSettle();
          expect(find.text('O prazo terminou.'), findsOneWidget);
          expect(find.text('Enviar avaliação'), findsNothing);
          expect(t.takeException(), isNull);
        });

        testWidgets('2. Só MEI: 422 de não-MEI leva ao "Abrir meu MEI" ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          const motivo = 'Só aceitamos MEI (Microempreendedor Individual). '
              'Este CNPJ não é optante pelo MEI.';
          // Mesmo quem já está verificado vê o caminho quando o novo número não é MEI.
          await t.pumpWidget(_app(MeuCnpjTela(
            servico: _Mei(
              const DadosMei(status: StatusMei.valido, podeOrcarEReceber: true),
              const ErroTrato(TipoErro.recusado, motivo, codigoHttp: 422),
            ),
          )));
          await t.pumpAndSettle();
          expect(find.textContaining('você precisa de um MEI ativo'), findsOneWidget);
          expect(find.textContaining('MEI ou outro'), findsNothing);
          expect(find.byKey(const Key('botao-abrir-mei')), findsNothing);
          await t.enterText(find.byKey(const Key('campo-cnpj')), '11444777000161');
          await t.ensureVisible(find.byKey(const Key('botao-validar-cnpj')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('botao-validar-cnpj')));
          await t.pumpAndSettle();
          expect(find.text(motivo), findsOneWidget);
          await t.scrollUntilVisible(find.byKey(const Key('botao-abrir-mei')), 150,
              scrollable: find.byType(Scrollable).first);
          expect(find.byKey(const Key('botao-abrir-mei')), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets('3. "obrigatorias" da API trava os três canais ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(PreferenciasNotificacoesTela(
            repositorio: _Prefs(const [
              PreferenciaNotificacao(categoria: 'agenda', obrigatoria: true, push: false),
              PreferenciaNotificacao(categoria: 'pagamentos', obrigatoria: false),
            ]),
          )));
          await t.pumpAndSettle();
          SwitchListTile chave(String k) => t.widget<SwitchListTile>(find.byKey(Key(k)));
          final lista = find.byType(Scrollable).first;
          await t.scrollUntilVisible(find.byKey(const Key('switch-email-agenda')), 150,
              scrollable: lista);
          for (final canal in ['push', 'app', 'email']) {
            expect(chave('switch-$canal-agenda').value, isTrue, reason: canal);
            expect(chave('switch-$canal-agenda').onChanged, isNull, reason: canal);
          }
          await t.scrollUntilVisible(find.byKey(const Key('switch-email-pagamentos')), 150,
              scrollable: lista);
          expect(chave('switch-email-pagamentos').onChanged, isNotNull,
              reason: 'a lista do servidor manda');
          expect(t.takeException(), isNull);
        });
      }
    }

    test('3. a API entrega "obrigatorias"; sem o campo fica nulo', () async {
      ClienteApi api(Map<String, dynamic> corpo) => ClienteApi(
            urlBase: 'https://api.teste',
            sessao: SessaoTrato()..entrar('t'),
            cliente: MockClient((_) async => http.Response(jsonEncode(corpo), 200,
                headers: const {'content-type': 'application/json'})),
          );
      final categorias = {
        'disputas': {'app': true, 'push': true, 'email': true},
        'agenda': {'app': true, 'push': false, 'email': true},
      };
      final novo = await RepositorioNotificacoesApi(api({
        'categorias': categorias,
        'obrigatorias': ['disputas'],
      })).carregarPreferencias();
      expect({for (final p in novo) p.categoria: p.obrigatoria},
          {'disputas': true, 'agenda': false});
      final antigo = await RepositorioNotificacoesApi(api({'categorias': categorias}))
          .carregarPreferencias();
      expect(antigo.map((p) => p.obrigatoria), everyElement(isNull));
    });
  });
}
