import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/atendimento.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/servicos/servicos_recentes_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _aviso = 'Não passe contato. Fora do app não há garantia.';

PedidoEmExecucao _pedido(String estado, {bool remoto = false}) => PedidoEmExecucao(
      numero: '#4821',
      titulo: 'Serviço',
      etapas: const [],
      fotos: const [],
      estadoApi: estado,
      remoto: remoto,
      visita: 'Qui, 03/12 · 14h às 16h',
      profissionalNome: 'Carlos Eduardo Lima',
      podeVerConclusao: false,
    );

class _PedidosEmAndamento extends RepositorioPedidosFake {
  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => _pedido('em_andamento');
}

Future<void> _janela(WidgetTester t,
    {double fonte = 1, Size tamanho = const Size(390, 844)}) async {
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

/// Dentro da tela sem rolar nada.
void _naTela(WidgetTester t, Finder alvo, double altura) {
  expect(alvo, findsOneWidget);
  final r = t.getRect(alvo);
  expect(r.top, greaterThanOrEqualTo(0));
  expect(r.bottom, lessThanOrEqualTo(altura));
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  for (final (tamanho, teclado, fonte) in [
    (const Size(390, 844), 0.0, 1.0),
    (const Size(390, 844), 340.0, 1.3),
    (const Size(320, 568), 260.0, 1.0),
  ]) {
    testWidgets(
        'chat: aviso de contato fixo (${tamanho.width.toInt()}x${tamanho.height.toInt()}, '
        'teclado $teclado, x$fonte)', (t) async {
      await _janela(t, tamanho: tamanho, fonte: fonte);
      t.view.viewInsets = FakeViewPadding(bottom: teclado);
      await t.pumpWidget(_app(const ChatPedidoTela(
        conversa: ConversaPedido(
          nome: 'Carlos',
          iniciais: 'C',
          numeroPedido: '#1',
          situacao: 'pago',
          respostasRapidas: ['Ok'],
          mensagens: [],
        ),
      )));
      await t.pumpAndSettle();
      _naTela(t, find.text(_aviso), tamanho.height - teclado);
      expect(t.takeException(), isNull);
    });
  }

  for (final estado in ['agendado', 'a_caminho', 'em_andamento']) {
    for (final fonte in [1.0, 1.3]) {
      testWidgets('cliente em "$estado" x$fonte: status, outra parte e Chat/Ajuda/SOS fixos',
          (t) async {
        await _janela(t, fonte: fonte);
        var sos = 0, chat = 0, ajuda = 0;
        await t.pumpWidget(_app(PedidoExecucaoTela(
          pedido: _pedido(estado),
          aoConversar: () => chat++,
          aoAjuda: () => ajuda++,
          aoSosEmergencia: () => sos++,
        )));
        await t.pumpAndSettle();
        expect(find.text(statusDeAtendimento(estado)), findsOneWidget);
        expect(find.text('Qui, 03/12 · 14h às 16h'), findsOneWidget);
        expect(find.text('Carlos L.'), findsOneWidget);
        for (final chave in ['atendimento-chat', 'atendimento-ajuda', 'botao-sos-emergencia']) {
          final alvo = find.byKey(ValueKey(chave));
          _naTela(t, alvo, 844);
          expect(t.getSize(alvo).height, greaterThanOrEqualTo(64));
          await t.tap(alvo);
        }
        expect((chat, ajuda, sos), (1, 1, 1));
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('concluído não mostra a barra; remoto não mostra SOS', (t) async {
    await _janela(t);
    await t.pumpWidget(_app(PedidoExecucaoTela(pedido: _pedido('concluido'))));
    await t.pumpAndSettle();
    expect(find.byType(BarraAtendimento), findsNothing);
    await t.pumpWidget(_app(PedidoExecucaoTela(pedido: _pedido('em_andamento', remoto: true))));
    await t.pumpAndSettle();
    expect(find.byType(BarraAtendimento), findsOneWidget);
    expect(find.byKey(const ValueKey('botao-sos-emergencia')), findsNothing);
  });

  for (final fonte in [1.0, 1.3]) {
    testWidgets('profissional x$fonte: o atendimento abre em tela com SOS e as ações', (t) async {
      await _janela(t, fonte: fonte);
      await t.pumpWidget(_app(RotasTrato.cascaProfissionalParaTeste()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Fazer check-in').first);
      await t.tap(find.text('Fazer check-in').first);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-atendimento')), findsOneWidget);
      expect(find.byKey(const ValueKey('outra-parte')), findsOneWidget);
      _naTela(t, find.byKey(const ValueKey('botao-sos-emergencia')), 844);
      _naTela(t, find.byKey(const ValueKey('atendimento-chat')), 844);
      expect(find.text('Conversar com o cliente'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('botao-sos-emergencia')));
      await t.pumpAndSettle();
      expect(find.text('Ligar 190'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    });
  }

  testWidgets('Ajuda do pedido vai direto ao relato dele', (t) async {
    await _janela(t, tamanho: const Size(390, 1600));
    RotasTrato.repos = repositoriosDemo(pedidos: _PedidosEmAndamento());
    await t.pumpWidget(_app(Builder(
      builder: (c) => Scaffold(
        body: TextButton(
          onPressed: () => RotasTrato.abrirServico(c, 'ped-1'),
          child: const Text('abrir'),
        ),
      ),
    )));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('atendimento-ajuda')));
    await t.pumpAndSettle();
    // Ajuda no atendimento leva DIRETO ao relato do pedido (P06).
    expect(find.byType(AjudaTela), findsNothing);
    expect(find.byType(RelatarProblemaTela), findsOneWidget);
    expect(find.byType(ServicosRecentesTela), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
