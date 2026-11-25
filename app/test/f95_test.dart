import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/preferencias_notificacoes_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_catalogo_fake.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/carteira/dados_exemplo.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
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

PedidoEmExecucao _pedido(String estado, {bool jaAvaliou = false}) =>
    PedidoEmExecucao(
      numero: '#CCA5',
      titulo: 'Troca de chuveiro',
      etapas: const [],
      fotos: const [],
      estadoApi: estado,
      jaAvaliou: jaAvaliou,
      podeVerConclusao: false,
    );

class _PedidoConcluido extends RepositorioPedidosFake {
  _PedidoConcluido({this.jaAvaliou = false});
  final bool jaAvaliou;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async =>
      _pedido('concluido', jaAvaliou: jaAvaliou);
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('1. Garantia mínima pelo ID da categoria (P07)', () {
    const eletricista = CategoriaServico('Eletricista', Icons.bolt,
        id: 'cat-elet', garantiaMinimaDias: 90);
    const diarista =
        CategoriaServico('Diarista', Icons.cleaning_services, id: 'cat-dia');

    void ligar() => RotasTrato.repos = repositoriosDemo(
          catalogo: RepositorioCatalogoFake(
              categorias: const [eletricista, diarista]),
        );

    test('o id da categoria do pedido decide (o nome do pedido pode ser outro)',
        () async {
      ligar(); // o pedido de teste tem categoriaNome diferente das duas
      expect(
          await RotasTrato.garantiaMinimaParaTeste('p1',
              categoriaId: 'cat-elet'),
          90);
      expect(
          await RotasTrato.garantiaMinimaParaTeste('p1',
              categoriaId: 'cat-dia'),
          30);
    });

    test('id desconhecido ou sem dado: 30, nunca menos', () async {
      ligar();
      expect(
          await RotasTrato.garantiaMinimaParaTeste('p1',
              categoriaId: 'nao-existe'),
          30);
      expect(await RotasTrato.garantiaMinimaParaTeste('p1'), 30);
      RotasTrato.repos =
          repositoriosDemo(catalogo: RepositorioCatalogoFake(falhar: true));
      expect(
          await RotasTrato.garantiaMinimaParaTeste('p1',
              categoriaId: 'cat-elet'),
          30);
    });

    test('o pedido aberto da API traz o categoria_id', () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((req) async => http.Response.bytes(
              utf8.encode(jsonEncode([
                {
                  'id': 'pa1',
                  'titulo': 'Instalar ventilador',
                  'descricao': 'x',
                  'bairro': 'Savassi',
                  'categoria_id': 'cat-elet',
                  'urgente': false,
                  'prazo_desejado': null,
                  'aberto_em': '2026-10-29T12:00:00Z',
                },
                {
                  'id': 'pa2',
                  'titulo': 'Sem categoria',
                  'descricao': 'x',
                  'bairro': 'Savassi',
                  'urgente': false,
                  'prazo_desejado': null,
                  'aberto_em': '2026-10-29T12:00:00Z',
                },
              ])),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              },
            )),
      );
      final r = await RepositorioProfissionalApi(api)
          .pedidosAbertos(const FiltroPedidosAbertos());
      expect(r.first.categoriaId, 'cat-elet');
      expect(r.last.categoriaId, isNull,
          reason: 'backend antigo: sem o campo, sem quebrar');
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        for (final (rotulo, id, esperado) in [
          ('Eletricista', 'cat-elet', ['90 dias']),
          ('Diarista', 'cat-dia', ['30 dias', '60 dias', '90 dias']),
        ]) {
          testWidgets(
              'calculadora de $rotulo oferece ${esperado.join(' / ')} '
              '(${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte)',
              (t) async {
            await _janela(t, tamanho, fonte);
            ligar();
            final minima =
                await RotasTrato.garantiaMinimaParaTeste('p1', categoriaId: id);
            await t.pumpWidget(_app(CalculadoraOrcamentoTela(
              servico: ServicoOrcamentoFake(),
              tituloPedido: 'Pedido',
              garantiaMinimaDias: minima,
            )));
            await t.pumpAndSettle();
            await t.ensureVisible(find.text('Garantia').first);
            await t.pumpAndSettle();
            await t.tap(find.byType(DropdownButtonFormField<int>).first);
            await t.pumpAndSettle();
            final opcoes = {
              for (final w in t.widgetList<Text>(find.textContaining(' dias')))
                if (RegExp(r'^\d+ dias$').hasMatch(w.data ?? '')) w.data!,
            };
            expect(opcoes, esperado.toSet());
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });

  group('2. Avaliar cliente (P09)', () {
    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

        testWidgets(
            'pedido concluído (profissional): botão "Avaliar cliente" ($r)',
            (t) async {
          await _janela(t, tamanho, fonte);
          RotasTrato.repos = repositoriosDemo(pedidos: _PedidoConcluido());
          late BuildContext ctx;
          await t.pumpWidget(_app(Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          })));
          RotasTrato.abrirDestino(ctx, DestinoApp.pedido, 'ped-1',
              profissional: true);
          await t.pumpAndSettle();
          expect(find.byType(PedidoExecucaoTela), findsOneWidget);
          expect(find.widgetWithText(FilledButton, 'Avaliar cliente'),
              findsOneWidget);
          await t.tap(find.widgetWithText(FilledButton, 'Avaliar cliente'));
          await t.pumpAndSettle();
          expect(find.textContaining('Como foi atender'), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets('já avaliou: o botão some ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          RotasTrato.repos =
              repositoriosDemo(pedidos: _PedidoConcluido(jaAvaliou: true));
          late BuildContext ctx;
          await t.pumpWidget(_app(Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          })));
          RotasTrato.abrirDestino(ctx, DestinoApp.pedido, 'ped-1',
              profissional: true);
          await t.pumpAndSettle();
          expect(find.widgetWithText(FilledButton, 'Avaliar cliente'),
              findsNothing);
          expect(t.takeException(), isNull);
        });

        testWidgets('Carteira avisa dos 50 Tratinhos ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(const Scaffold(
              body: CarteiraTela(
                  dados: DadosExemploCarteira.completo, soExtrato: false))));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
              find.byKey(const Key('aviso-avaliar-cliente')), 200,
              scrollable: find.byType(Scrollable).first);
          expect(find.text('Você ganha 50 Tratinhos ao avaliar um cliente.'),
              findsOneWidget);
        });
      }
    }
  });

  group('4. Preferências de alertas salvam ao tocar (BUG-C14)', () {
    for (final fonte in _fontes) {
      testWidgets('o interruptor grava na hora e não há botão Salvar (x$fonte)',
          (t) async {
        await _janela(t, _tamanhos.first, fonte);
        final repo = RepositorioNotificacoesFake();
        await t
            .pumpWidget(_app(PreferenciasNotificacoesTela(repositorio: repo)));
        await t.pumpAndSettle();
        expect(find.text('Salvar preferências'), findsNothing);
        await t.tap(find.byKey(const Key('switch-push-orcamentos')));
        await t.pumpAndSettle();
        expect(repo.preferenciasSalvas.first.push, isFalse,
            reason: 'gravou sem "Salvar"');
        expect(find.byKey(const Key('preferencias-salvas')), findsOneWidget);
      });
    }

    testWidgets(
        'falhou: o interruptor volta, mostra o erro e "Tentar de novo" regrava',
        (t) async {
      await _janela(t, _tamanhos.last, 1.3);
      final repo = _RepoQueFalha();
      await t.pumpWidget(_app(PreferenciasNotificacoesTela(repositorio: repo)));
      await t.pumpAndSettle();
      bool ligado() => t
          .widget<SwitchListTile>(
              find.byKey(const Key('switch-push-orcamentos')))
          .value;
      expect(ligado(), isTrue);
      await t.tap(find.byKey(const Key('switch-push-orcamentos')));
      await t.pumpAndSettle();
      expect(ligado(), isTrue, reason: 'voltou ao valor gravado');
      expect(find.text('Sem internet agora.'), findsOneWidget);
      repo.falhar = false;
      await t
          .ensureVisible(find.byKey(const Key('preferencias-tentar-de-novo')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('preferencias-tentar-de-novo')));
      await t.pumpAndSettle();
      expect(ligado(), isFalse, reason: 'a nova tentativa gravou');
      expect(find.byKey(const Key('preferencias-erro')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('5. Um só "Ver garantia" no pedido finalizado', () {
    for (final fonte in _fontes) {
      for (final jaAvaliou in [false, true]) {
        testWidgets(
            'concluído ${jaAvaliou ? 'avaliado' : 'sem avaliar'}: um acesso à garantia (x$fonte)',
            (t) async {
          await _janela(t, _tamanhos.first, fonte);
          await t.pumpWidget(_app(Scaffold(
            body: PedidoExecucaoTela(
              pedido: _pedido('concluido', jaAvaliou: jaAvaliou),
              aoAvaliar: () {},
              aoVerGarantia: () {},
            ),
          )));
          await t.pumpAndSettle();
          final garantias = find.byWidgetPredicate((w) =>
              w is Text &&
              (w.data ?? '').toLowerCase().contains('ver garantia'));
          expect(garantias, findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}

class _RepoQueFalha extends RepositorioNotificacoesFake {
  bool falhar = true;

  @override
  Future<List<PreferenciaNotificacao>> salvarPreferencias(
      List<PreferenciaNotificacao> itens) async {
    if (falhar) {
      throw const ErroTrato(TipoErro.semInternet, 'Sem internet agora.');
    }
    return super.salvarPreferencias(itens);
  }
}
