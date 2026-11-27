// TERMOS-APP8: exclusividade de 48 h pedida pelo cliente (13.6) e vencimento no extrato (13.4).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/exclusividade_cliente/modelos.dart';
import 'package:trato/telas/exclusividade_cliente/secao_exclusividade.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/telas/perfil_cliente/extrato_tratinhos_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
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
      home: Scaffold(body: SingleChildScrollView(child: tela)),
    );

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

const _escolhas = [
  EscolhaExclusividade(rotulo: 'Carlos · R\$ 200,00', orcamentoId: 'o1', profissionalId: 'p1'),
  EscolhaExclusividade(rotulo: 'Joana · R\$ 180,00', orcamentoId: 'o2', profissionalId: 'p2'),
];

SituacaoExclusividadeCliente _situacao({ExclusividadeDoCliente? ex, bool disponivel = true}) =>
    SituacaoExclusividadeCliente(
      disponivel: disponivel,
      custo: 100,
      duracaoHoras: 48,
      saldoLivre: 150,
      creditos: [CreditoTratinho(moedas: 150, expiraEm: DateTime(2027, 2, 10))],
      exclusividade: ex,
    );

(ClienteApi, List<(String, Object?)>) _api(Map<String, (int, Object)> respostas) {
  final chamadas = <(String, Object?)>[];
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((req) async {
      final chave = '${req.method} ${req.url.path}';
      chamadas.add((chave, req.body.isEmpty ? null : jsonDecode(req.body)));
      final (status, corpo) = respostas[chave] ?? (404, {'detail': 'Not Found'});
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return (api, chamadas);
}

void main() {
  setUpAll(carregarFontesTrato);

  group('API', () {
    test('lê a situação; 404 e 503 escondem; sem custo não oferece', () async {
      final (api, _) = _api({
        'GET /v1/pedidos/p1/exclusividade-cliente': (
          200,
          {
            'disponivel': true,
            'custo_moedas': 100,
            'duracao_horas': 48,
            'saldo_livre': 120,
            'creditos': [
              {'moedas': 120, 'expira_em': '2027-02-10T12:00:00Z'}
            ],
            'exclusividade': {
              'id': 'e1',
              'status': 'ativa',
              'profissional_id': 'p1',
              'expira_em': '2026-11-28T12:00:00Z',
              'devolvida': false,
            },
          }
        ),
        'GET /v1/pedidos/p3/exclusividade-cliente': (503, {'detail': 'x'}),
        'GET /v1/pedidos/p4/exclusividade-cliente': (403, {'detail': 'não'}),
      });
      final repo = RepositorioPedidosApi(api);
      final s = await repo.situacaoExclusividadeCliente('p1');
      expect((s!.custo, s.saldoLivre, s.creditos.single.moedas), (100, 120, 120));
      expect(s.exclusividade!.ativa, isTrue);
      expect(await repo.situacaoExclusividadeCliente('p2'), isNull);
      expect(await repo.situacaoExclusividadeCliente('p3'), isNull);
      await expectLater(repo.situacaoExclusividadeCliente('p4'), throwsA(isA<ErroTrato>()));
      expect(SituacaoExclusividadeCliente.deJson(const {'disponivel': true}).disponivel, isFalse);
    });

    test('pedir manda a escolha e a chave; desistir usa a rota do profissional', () async {
      final (api, chamadas) = _api({
        'POST /v1/pedidos/p1/exclusividade-cliente': (201, {'id': 'e1'}),
        'POST /v1/profissional/exclusividades/e1/desistir': (200, {'resultado': 'ok'}),
      });
      await RepositorioPedidosApi(api)
          .pedirExclusividadeCliente('p1', _escolhas.first, 'chave-123456');
      expect(chamadas.last.$2,
          {'orcamento_id': 'o1', 'profissional_id': 'p1', 'chave_idempotencia': 'chave-123456'});
      await RepositorioProfissionalApi(api).desistirDaExclusividade('e1');
      expect(chamadas.last.$1, 'POST /v1/profissional/exclusividades/e1/desistir');
    });

    test('avisos novos abrem o pedido', () {
      for (final evento in [
        'exclusividade.cliente_reservou',
        'exclusividade.cliente_fim',
        'exclusividade.cliente_devolvida',
      ]) {
        expect(
          resultadoDoPush(
              {'evento': evento, 'tela': 'pedido', 'pedido_id': 'p1', 'papel': 'profissional'}),
          const ResultadoLink.valido(DestinoApp.pedido, 'p1', papel: 'profissional'),
        );
        expect(tipoDaNotificacao(evento), TipoNotificacao.pedido);
      }
    });
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('avisa antes, só confirma com escolha, repete a chave no erro ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final pedidos = <(String?, String)>[];
        var falhar = true;
        var feito = false;
        await t.pumpWidget(_app(SecaoExclusividadeCliente(
          carregar: () async => (
            situacao: _situacao(
                ex: feito
                    ? ExclusividadeDoCliente(
                        id: 'e1',
                        status: 'ativa',
                        profissionalId: 'p2',
                        expiraEm: DateTime(2026, 11, 28, 14))
                    : null),
            escolhas: _escolhas,
          ),
          pedir: (escolha, chave) async {
            pedidos.add((escolha.orcamentoId, chave));
            if (falhar) {
              throw const ErroTrato(TipoErro.recusado, 'Você não tem Tratinhos suficientes.');
            }
            feito = true;
          },
        )));
        await t.pumpAndSettle();
        expect(find.textContaining('vence em 10/02/2027'), findsOneWidget);

        await _tocar(t, find.byKey(const Key('pedir-exclusividade-cliente')));
        expect(find.text(avisoExclusividade(100, 48)), findsOneWidget);
        for (final parte in [
          'Custa 100 Tratinhos',
          'vencer sem contratação',
          'aceitar outro profissional',
          'cancelar o pedido',
          'falha do Trato ou desistência do profissional',
        ]) {
          expect(avisoExclusividade(100, 48), contains(parte));
        }
        final confirmar = find.byKey(const Key('confirmar-exclusividade-cliente'));
        await _tocar(t, confirmar);
        expect(pedidos, isEmpty, reason: 'sem escolher, nada é enviado');

        await _tocar(t, find.text('Joana · R\$ 180,00'));
        await _tocar(t, confirmar);
        await t.ensureVisible(find.byKey(const Key('erro-exclusividade-cliente')));
        expect(find.text('Você não tem Tratinhos suficientes.'), findsOneWidget);

        falhar = false;
        await _tocar(t, confirmar);
        expect(pedidos.map((p) => p.$1), ['o2', 'o2']);
        expect(pedidos[0].$2, pedidos[1].$2);
        expect(find.textContaining('Ativa até 28/11/2026'), findsOneWidget);
        expect(find.byKey(const Key('pedir-exclusividade-cliente')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('encerrada diz se voltou; servidor sem a função esconde ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        Future<void> abrir(SituacaoExclusividadeCliente? s) async {
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(SecaoExclusividadeCliente(
            carregar: () async => (situacao: s, escolhas: _escolhas),
            pedir: (_, __) async {},
          )));
          await t.pumpAndSettle();
        }

        await abrir(_situacao(
            disponivel: false,
            ex: const ExclusividadeDoCliente(id: 'e', status: 'cancelada', devolvida: true)));
        expect(find.text('Os Tratinhos voltaram ao seu saldo.'), findsOneWidget);
        await abrir(_situacao(
            disponivel: false,
            ex: const ExclusividadeDoCliente(id: 'e', status: 'expirada_sem_contratacao')));
        expect(find.text('Venceu sem contratação.'), findsOneWidget);
        expect(find.text('Os Tratinhos usados não voltam.'), findsOneWidget);
        await abrir(null);
        expect(find.byKey(const Key('cartao-exclusividade-cliente')), findsNothing);
        await abrir(_situacao(disponivel: false));
        expect(find.byKey(const Key('cartao-exclusividade-cliente')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('extrato: vencimento de cada crédito ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(MaterialApp(
          theme: TemaTrato.claro,
          home: ExtratoTratinhosTela(
            perfil: PerfilCliente(
              nome: 'Ana',
              iniciais: 'A',
              resumo: '',
              grupos: const [],
              moedas: 50,
              moedasExtrato: [
                LancamentoTratinho(
                    tipo: 'bonus_avaliacao',
                    quantidade: 50,
                    criadaEm: DateTime(2026, 11, 1),
                    expiraEm: DateTime(2027, 1, 30)),
                LancamentoTratinho(
                    tipo: 'exclusividade_uso',
                    quantidade: -100,
                    criadaEm: DateTime(2026, 11, 2),
                    expiraEm: DateTime(2027, 1, 30)),
              ],
            ),
          ),
        ));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('Exclusividade em pedido'), 150,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Vence em 30/01/2027', skipOffstage: false), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('no pedido aberto: o cartão aparece; sem a função, não', (t) async {
    await _janela(t, const Size(390, 2400), 1);
    ligarDemoNosTestes();
    addTearDown(() => RotasTrato.repos = repositoriosDemo());
    for (final comFuncao in [true, false]) {
      await t.pumpWidget(const SizedBox());
      RotasTrato.repos = repositoriosDemo(pedidos: _Aberto(comFuncao ? _situacao() : null));
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => RotasTrato.abrirServico(c, 'ped-1'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('cartao-exclusividade-cliente'), skipOffstage: false),
          comFuncao ? findsOneWidget : findsNothing);
      expect(t.takeException(), isNull);
    }
  });
}

class _Aberto extends RepositorioPedidosFake {
  _Aberto(this.situacao);
  final SituacaoExclusividadeCliente? situacao;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => const PedidoEmExecucao(
        numero: '#AB12',
        titulo: 'Aguardando orçamentos',
        etapas: [],
        fotos: [],
        estadoApi: 'aberto',
      );

  @override
  Future<SituacaoExclusividadeCliente?> situacaoExclusividadeCliente(String pedidoId) async =>
      situacao;
}
