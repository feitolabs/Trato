// TERMOS-APP13: compensações do profissional (8.6 e 17.4), avisos, extrato e registro de chegada.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/atendimento/atendimento_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/ausencia/ausencia_tela.dart';
import 'package:trato/telas/ausencia/modelos.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/compensacoes/compensacoes_tela.dart';
import 'package:trato/telas/compensacoes/modelos.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
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

Widget _app(Widget tela, [GlobalKey<NavigatorState>? chave]) =>
    MaterialApp(theme: TemaTrato.claro, navigatorKey: chave, home: tela);

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

ClienteApi _api(Future<http.Response> Function(http.Request) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient(responder),
    );

http.Response _json(Object corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json'},
    );

Map<String, Object?> _divida(String id, String status, {int descontado = 2000}) => {
      'id': id,
      'pedido_id': 'ab12cd34',
      'origem': 'reembolso',
      'valor_centavos': 5000,
      'compensado_centavos': descontado,
      // De propósito diferente de valor - descontado: a tela mostra o que o servidor manda.
      'restante_centavos': status == 'aberta' ? 2900 : 0,
      'motivo': 'Reembolso ao cliente $id.',
      'status': status,
      'criada_em': '2026-11-20T10:00:00Z',
      'avisado_em': '2026-11-21T11:00:00Z',
      'cancelada_em': status == 'cancelada' ? '2026-11-25T12:00:00Z' : null,
      'motivo_cancelamento': status == 'cancelada' ? 'Contestação aceita.' : null,
    };

class _Servico implements ServicoCompensacoes {
  _Servico(this.itens, {this.falha});
  List<Compensacao>? itens;
  Object? falha;

  @override
  Future<List<Compensacao>?> listar() async {
    if (falha != null) throw falha!;
    return itens;
  }
}

List<Compensacao> _tres() => [
      for (final (id, status) in [('d1', 'aberta'), ('d2', 'quitada'), ('d3', 'cancelada')])
        Compensacao.deJson(_divida(id, status)),
    ];

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);

  group('1. API das compensações', () {
    test('lê os campos do servidor; campo ausente não quebra', () async {
      final caminhos = <String>[];
      final lista = await ServicoCompensacoesApi(_api((r) async {
        caminhos.add('${r.method} ${r.url.path}');
        return _json([
          _divida('d1', 'aberta'),
          {'id': 'velho'},
        ]);
      })).listar();
      expect(caminhos, ['GET /v1/me/compensacoes']);
      final d = lista!.first;
      expect(
        (d.valorCentavos, d.compensadoCentavos, d.restanteCentavos, d.pedidoId, d.status),
        (5000, 2000, 2900, 'ab12cd34', 'aberta'),
      );
      expect(d.motivo, 'Reembolso ao cliente d1.');
      expect(d.criadaEm, isNotNull);
      expect(d.avisadoEm, isNotNull);
      expect(lista.last.valorCentavos, isNull);
      expect(lista.last.situacaoTexto, 'Em acompanhamento');
    });

    for (final status in [404, 503]) {
      test('$status: a função não existe (nulo)', () async {
        final s = ServicoCompensacoesApi(_api((_) async => _json({'detail': 'x'}, status)));
        expect(await s.listar(), isNull);
      });
    }

    test('erro 500 é erro, não "sem função"', () async {
      final s = ServicoCompensacoesApi(_api((_) async => _json({'detail': 'x'}, 500)));
      await expectLater(s.listar(), throwsA(isA<ErroTrato>()));
    });
  });

  group('2. Tela', () {
    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} fonte $fonte';

        testWidgets('valores, situação, motivo, pedido, datas e atendimento ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final pedidos = <String?>[];
          await t.pumpWidget(_app(CompensacoesTela(
            servico: _Servico(_tres()),
            aoFalarComOTrato: (_, id) => pedidos.add(id),
          )));
          await t.pumpAndSettle();
          Finder em(String id, String texto) => find.descendant(
              of: find.byKey(ValueKey('compensacao-$id')), matching: find.text(texto));
          for (final texto in [
            'Pedido #AB12',
            'Aberta',
            'Valor',
            'R\$ 50,00',
            'Já descontado',
            'R\$ 20,00',
            'Falta descontar',
            'R\$ 29,00',
            'Reembolso ao cliente d1.',
            'Registrada em',
            'Aviso enviado em',
          ]) {
            expect(em('d1', texto), findsOneWidget, reason: texto);
          }
          expect(em('d1', 'Cancelada em'), findsNothing);
          expect(em('d2', 'Quitada'), findsOneWidget);
          expect(em('d3', 'Cancelada'), findsOneWidget);
          expect(em('d3', 'Cancelada em'), findsOneWidget);
          expect(em('d3', 'Contestação aceita.'), findsOneWidget);
          expect(find.byKey(const Key('compensacao-do-aviso')), findsNothing);
          await _tocar(t, find.byKey(const ValueKey('falar-d1')));
          expect(pedidos, ['ab12cd34']);
          expect(t.takeException(), isNull);
        });

        testWidgets('do aviso vem primeiro e marcada ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(CompensacoesTela(
            servico: _Servico(_tres()),
            compensacaoId: 'd3',
            aoFalarComOTrato: (_, __) {},
          )));
          await t.pumpAndSettle();
          double topo(String id) => t.getTopLeft(find.byKey(ValueKey('compensacao-$id'))).dy;
          expect(topo('d3'), lessThan(topo('d1')));
          expect(
            find.descendant(
                of: find.byKey(const ValueKey('compensacao-d3')),
                matching: find.byKey(const Key('compensacao-do-aviso'))),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        });

        testWidgets('carregando, erro, vazio e indisponível ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final s = _Servico([], falha: const ErroTrato(TipoErro.semInternet, 'Sem internet.'));
          await t.pumpWidget(_app(CompensacoesTela(servico: s, aoFalarComOTrato: (_, __) {})));
          expect(find.bySemanticsLabel('Carregando'), findsOneWidget);
          await t.pumpAndSettle();
          expect(find.text('Sem internet.'), findsOneWidget);
          s.falha = null;
          await _tocar(t, find.text('Tentar de novo'));
          expect(find.text('Nenhuma compensação'), findsOneWidget);
          expect(t.takeException(), isNull);

          final pedidos = <String?>[];
          await t.pumpWidget(_app(CompensacoesTela(
            key: const Key('outra'),
            servico: _Servico(null),
            aoFalarComOTrato: (_, id) => pedidos.add(id),
          )));
          await t.pumpAndSettle();
          expect(find.text('Compensações indisponíveis'), findsOneWidget);
          await _tocar(t, find.text('Falar com o Trato'));
          expect(pedidos, [null]);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('aviso de uma compensação que não está na lista', (t) async {
      await _janela(t, const Size(390, 844), 1);
      await t.pumpWidget(_app(CompensacoesTela(
        servico: _Servico(_tres()),
        compensacaoId: 'sumiu',
        aoFalarComOTrato: (_, __) {},
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('compensacao-nao-achada')), findsOneWidget);
      expect(find.byKey(const ValueKey('compensacao-d1')), findsOneWidget);
    });
  });

  group('3. Entrada na Carteira', () {
    for (final (nome, servico, aparece) in [
      ('com a função', _Servico(const []), true),
      ('404/503', _Servico(null), false),
      ('falha passageira', _Servico(null, falha: StateError('rede')), true),
    ]) {
      testWidgets('$nome: aparece = $aparece', (t) async {
        await _janela(t, const Size(320, 568), 1.3);
        var toques = 0;
        await t.pumpWidget(_app(CarteiraTela(
          dados: const DadosCarteira(extrato: []),
          entradaCompensacoes: EntradaDeCompensacoes(servico: servico, aoAbrir: () => toques++),
        )));
        await t.pumpAndSettle();
        final entrada = find.byKey(const Key('entrada-compensacoes'));
        expect(entrada, aparece ? findsOneWidget : findsNothing);
        if (aparece) {
          await _tocar(t, entrada);
          expect(toques, 1);
        }
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('na casca: Carteira abre as compensações e o atendimento', (t) async {
      await _janela(t, const Size(390, 844), 1);
      RotasTrato.repos = repositoriosDemo(compensacoes: _Servico(_tres()), sac: _Sac());
      await t.pumpWidget(_app(RotasTrato.cascaProfissionalParaTeste()));
      await t.pumpAndSettle();
      await t.tap(find.descendant(
          of: find.byType(BarraAbasFlutuante), matching: find.byIcon(
              Icons.account_balance_wallet_outlined)));
      await t.pumpAndSettle();
      await _tocar(t, find.byKey(const Key('entrada-compensacoes')));
      expect(find.byType(CompensacoesTela), findsOneWidget);
      await _tocar(t, find.byKey(const ValueKey('falar-d1')));
      expect(t.widget<AtendimentoTela>(find.byType(AtendimentoTela)).pedidoInicial, 'ab12cd34');
    });
  });

  group('4. Avisos', () {
    test('push: compensacao_id abre a compensação; sem ele, o pedido', () {
      ResultadoLink push(Object? id) =>
          resultadoDoPush({'tela': 'pedido', 'pedido_id': 'p1', 'compensacao_id': id});
      expect(
        push('d-1'),
        const ResultadoLink.valido(DestinoApp.compensacoes, 'd-1', papel: 'profissional'),
      );
      expect(
        push('../x'),
        const ResultadoLink.valido(DestinoApp.compensacoes, null, papel: 'profissional'),
      );
      expect(push(null), const ResultadoLink.valido(DestinoApp.pedido, 'p1'));
    });

    for (final tipo in ['registrada', 'cancelada']) {
      for (final tela in ['pedido', null]) {
        test('caixa: $tipo (data.tela: $tela) abre o item', () {
          final r = RotasTrato.destinoDaCaixa(
            Notificacao(
              id: 'n',
              titulo: 't',
              texto: 'x',
              quando: 'agora',
              tipo: TipoNotificacao.pagamento,
              tipoApi: 'pagamento.compensacao_$tipo',
              destinoId: 'p1',
              tela: tela,
              compensacaoId: 'd9',
            ),
            modoAtualProfissional: false,
          );
          expect(
            r,
            const ResultadoLink.valido(DestinoApp.compensacoes, 'd9', papel: 'profissional'),
          );
        });
      }
    }

    test('a caixa lê dados.compensacao_id da API e mantém ao marcar como lida', () async {
      final api = _api((_) async => _json([
            {
              'id': 'n1',
              'tipo': 'pagamento.compensacao_registrada',
              'titulo': 't',
              'criada_em': '2026-11-26T09:00:00Z',
              'dados': {
                'tela': 'pedido',
                'pedido_id': 'p1',
                'compensacao_id': 'd42',
                'chamado_id': 'c1',
              },
            }
          ]));
      final lista =
          await ServicoNotificacoesRepositorio(RepositorioNotificacoesApi(api)).listar();
      expect(lista.single.compensacaoId, 'd42');
      expect(lista.single.comoLida().compensacaoId, 'd42');
      expect(lista.single.comoLida().chamadoId, 'c1');
    });

    testWidgets('push abre a tela no item', (t) async {
      await _janela(t, const Size(390, 844), 1);
      RotasTrato.repos = repositoriosDemo(compensacoes: _Servico(_tres()));
      final nav = GlobalKey<NavigatorState>();
      await entrarNaContaDeTeste(ServicoAuthPadrao.atual);
      final anterior = DeepLinks.navegador;
      DeepLinks.navegador = () => nav.currentState;
      addTearDown(() => DeepLinks.navegador = anterior);
      await t.pumpWidget(_app(RotasTrato.cascaProfissionalParaTeste(), nav));
      await t.pumpAndSettle();
      DeepLinks.receberPush({'tela': 'pedido', 'pedido_id': 'p1', 'compensacao_id': 'd2'});
      await t.pumpAndSettle();
      expect(t.widget<CompensacoesTela>(find.byType(CompensacoesTela)).compensacaoId, 'd2');
      expect(
        find.descendant(
            of: find.byKey(const ValueKey('compensacao-d2')),
            matching: find.byKey(const Key('compensacao-do-aviso'))),
        findsOneWidget,
      );
    });
  });

  testWidgets('5. extrato: "Compensação" e "Compensação devolvida"', (t) async {
    Map<String, Object?> lanc(String id, String tipo, String debito, String credito,
            {String? estornoDe}) =>
        {
          'id': id,
          'pedido_id': 'ab12cd34',
          'tipo': tipo,
          'valor_centavos': 1500,
          'data': '2026-11-26T09:00:00Z',
          'debito': {'tipo': debito, 'titular': 'u'},
          'credito': {'tipo': credito, 'titular': 'u'},
          'estorno_de': estornoDe,
        };
    final repo = RepositorioProfissionalApi(_api((_) async => _json({
          'itens': [
            lanc('1', 'repasse', 'liberado', 'a_compensar'),
            lanc('2', 'estorno', 'a_compensar', 'liberado', estornoDe: '1'),
            lanc('3', 'repasse', 'a_liberar', 'liberado'),
            // Backend antigo: sem as contas, segue como antes.
            {...lanc('4', 'repasse', '', ''), 'debito': null, 'credito': null},
          ],
          'total': 4,
        })));
    final itens = await repo.extrato();
    expect([for (final i in itens) i.titulo], [
      'Pedido #AB12 · Compensação',
      'Pedido #AB12 · Compensação devolvida',
      'Pedido #AB12 · valor liberado',
      'Pedido #AB12 · valor liberado',
    ]);
    expect([for (final i in itens) i.liquidoCentavos], [-1500, 1500, 1500, 1500]);

    await _janela(t, const Size(320, 568), 1.3);
    await t.pumpWidget(_app(CarteiraTela(dados: DadosCarteira(extrato: itens))));
    await t.pumpAndSettle();
    for (final texto in [
      'Pedido #AB12 · Compensação',
      '-R\$ 15,00',
      'Descontado do repasse',
      'Pedido #AB12 · Compensação devolvida',
      'Desconto devolvido',
    ]) {
      expect(find.text(texto, skipOffstage: false), findsOneWidget, reason: texto);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('6. anexo registro_chegada com rótulo legível', (t) async {
    await _janela(t, const Size(320, 568), 1.3);
    await t.pumpWidget(_app(AusenciaTela(
      carregar: () async => const CasoAusencia(status: 'em_analise'),
      profissional: false,
      carregarAnexos: () async => const [
        AnexoAusencia(tipo: 'registro_chegada', arquivoId: 'a1', enviadoPor: 'profissional'),
      ],
    )));
    await t.pumpAndSettle();
    final rotulo = find.textContaining('Registro de chegada');
    await t.scrollUntilVisible(rotulo, 150, scrollable: find.byType(Scrollable).first);
    expect(rotulo, findsOneWidget);
    expect(find.textContaining('registro_chegada'), findsNothing);
    expect(t.takeException(), isNull);
  });
}

class _Sac implements ServicoSac {
  @override
  Object? noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
