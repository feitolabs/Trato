import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/carregador.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/navegacao_casca.dart';
import 'package:trato/telas/profissional_apoio/apoio.dart';
import 'package:trato/telas/recorrencias/servico_fake.dart';
import 'package:trato/telas/recorrencias/servicos_recorrentes_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/fontes.dart';

const _titulo = 'Ops, não encontramos isso';

/// Cliente de verdade respondendo com [status], como o backend.
ClienteApi _api(int status) => ClienteApi(
      urlBase: 'https://api.teste/',
      sessao: SessaoTrato()..entrar('t'),
      intervaloBaseRetry: Duration.zero,
      cliente: MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'detail': 'texto do servidor'})), status)),
    );

Future<void> _janela(WidgetTester t, {double fonte = 1, Size tamanho = const Size(390, 844)}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Abre [tela] por cima de uma tela "Início", como o app abre um detalhe.
Future<void> _empurrar(WidgetTester t, Widget tela, {ThemeData? tema}) async {
  await t.pumpWidget(MaterialApp(
    theme: tema ?? TemaTrato.claro,
    builder: (c, f) => EscalaFonteLimitada(child: f!),
    home: Builder(
      builder: (c) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => tela)),
          child: const Text('Início'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('Início'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);

  const tela = TelaNaoEncontrada(texto: TextosNaoEncontrado.pedido);

  for (final (tamanho, fonte) in [
    (const Size(390, 844), 1.0),
    (const Size(390, 844), 1.3),
    (const Size(320, 568), 1.3),
  ]) {
    testWidgets('layout em ${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte', (t) async {
      final semantica = t.ensureSemantics();
      await _janela(t, tamanho: tamanho, fonte: fonte);
      await _empurrar(t, tela);
      expect(t.takeException(), isNull);
      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(TextosNaoEncontrado.pedido), findsOneWidget);
      expect(find.bySemanticsLabel('Tratinho confuso'), findsOneWidget);
      final imagem = t.getSize(find.byType(Image));
      expect(imagem, const Size(180, 180));
      expect(t.getCenter(find.byType(Image)).dx, closeTo(tamanho.width / 2, 0.5));
      await t.ensureVisible(find.text('Voltar'));
      expect(find.text('Voltar ao início'), findsOneWidget);
      expect(find.text('Voltar'), findsOneWidget);
      semantica.dispose();
    });
  }

  testWidgets('"Voltar" volta uma tela; "Voltar ao início" vai à primeira e abre a aba 0',
      (t) async {
    await _janela(t);
    final abas = <int>[];
    ControladorCasca.registrar(irParaAba: abas.add);
    await _empurrar(t, tela);
    await t.tap(find.text('Voltar'));
    await t.pumpAndSettle();
    expect(find.text(_titulo), findsNothing);
    await t.tap(find.text('Início'));
    await t.pumpAndSettle();
    await t.tap(find.text('Voltar ao início'));
    await t.pumpAndSettle();
    expect(find.text('Início'), findsOneWidget);
    expect(abas, [0]);
    ControladorCasca.desregistrar(abas.add);
  });

  testWidgets('sem tela anterior não há "Voltar"; funciona no tema escuro', (t) async {
    await _janela(t);
    await t.pumpWidget(MaterialApp(theme: TemaTrato.escuro, home: tela));
    await t.pumpAndSettle();
    expect(find.text('Voltar ao início'), findsOneWidget);
    expect(find.text('Voltar'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a imagem do mascote existe nos assets', (t) async {
    final dados = await rootBundle.load(TelaNaoEncontrada.mascote);
    expect(dados.lengthInBytes, inInclusiveRange(1000, 200000));
  });

  for (final status in [404, 403]) {
    testWidgets('Carregador de detalhe com $status mostra a tela', (t) async {
      await _janela(t);
      final api = _api(status);
      await _empurrar(
        t,
        Carregador<Object?>(
          textoNaoEncontrado: TextosNaoEncontrado.conversa,
          carregar: () => api.get('/v1/pedidos/x/mensagens'),
          construir: (_, __) => const SizedBox(),
        ),
      );
      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(TextosNaoEncontrado.conversa), findsOneWidget);
      expect(find.text('Tentar de novo'), findsNothing);
    });

    testWidgets('PaginaCarregavel de detalhe com $status mostra a tela', (t) async {
      await _janela(t);
      final api = _api(status);
      await _empurrar(
        t,
        PaginaCarregavel<Object?>(
          titulo: 'Cobrança extra',
          textoNaoEncontrado: TextosNaoEncontrado.aditivo,
          carregar: () => api.get('/v1/contratos/x/aditivos'),
          construir: (_, __) => const SizedBox(),
        ),
      );
      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(TextosNaoEncontrado.aditivo), findsOneWidget);
    });
  }

  testWidgets('outro erro (500) e tela sem a frase continuam com "Tentar de novo"', (t) async {
    await _janela(t);
    for (final (status, frase) in [(500, TextosNaoEncontrado.pedido), (404, null)]) {
      final api = _api(status);
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: Carregador<Object?>(
          key: ValueKey(status),
          textoNaoEncontrado: frase,
          carregar: () => api.get('/v1/pedidos/x'),
          construir: (_, __) => const SizedBox(),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text(_titulo), findsNothing);
      expect(find.text('Tentar de novo'), findsOneWidget);
    }
  });

  testWidgets('detalhe do serviço recorrente que não existe mostra a tela', (t) async {
    await _janela(t);
    await _empurrar(
        t, DetalheRecorrenciaTela(servico: ServicoRecorrenciasFake(), recorrenciaId: 'sumiu'));
    expect(find.text(_titulo), findsOneWidget);
    expect(find.text(TextosNaoEncontrado.recorrencia), findsOneWidget);
  });

  // Print para o relatório: só grava quando pedido (--dart-define=PRINT_404=true).
  testWidgets('print da tela', (t) async {
    await _janela(t);
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;
    const chave = ValueKey('print');
    await t.pumpWidget(RepaintBoundary(
      key: chave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaTrato.claro,
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => tela)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.runAsync(() => precacheImage(
        const AssetImage(TelaNaoEncontrada.mascote), t.element(find.byType(Image))));
    await t.pumpAndSettle();
    final limite = t.renderObject<RenderRepaintBoundary>(find.byKey(chave));
    await t.runAsync(() async {
      final imagem = await limite.toImage(pixelRatio: 2);
      final dados = await imagem.toByteData(format: ui.ImageByteFormat.png);
      File('../harness/teste_real_superqa/prints/TELA-404.png')
          .writeAsBytesSync(dados!.buffer.asUint8List());
      imagem.dispose();
    });
  }, skip: !const bool.fromEnvironment('PRINT_404'));
}
