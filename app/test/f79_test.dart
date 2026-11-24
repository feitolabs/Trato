import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart' show FiltroPedidosAbertos;
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dispositivo/servico_localizacao.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';

/// BUG-P02 (ANR na Home do profissional): o stack mostrou a thread principal parada em
/// `LocationManager.removeNmeaListener`. A Home atualiza a cada poucos segundos e cada
/// atualização pedia a posição de novo (o `timeout` só para de esperar, não cancela o GPS), então
/// os pedidos de localização se empilhavam. Agora: 1 pedido por vez, posição reaproveitada e pausa
/// depois de falha.
void main() {
  late List<http.Request> pedidas;

  RepositorioProfissionalApi repo(
    Future<PosicaoAtual?> Function() posicao, {
    required DateTime Function() agora,
  }) {
    pedidas = [];
    final api = ClienteApi(
      urlBase: 'https://api.teste/',
      sessao: SessaoTrato()..entrar('t'),
      intervaloBaseRetry: Duration.zero,
      cliente: MockClient((req) async {
        pedidas.add(req);
        return http.Response(jsonEncode({'itens': <Object>[]}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    return RepositorioProfissionalApi(api, posicao: posicao, agora: agora);
  }

  Future<void> atualizar(RepositorioProfissionalApi r) =>
      r.pedidosAbertos(const FiltroPedidosAbertos(limite: 20));

  const aqui = PosicaoAtual(latitude: -19.9, longitude: -43.9, precisaoMetros: 10);

  test('localização lenta: várias atualizações da Home pedem a posição uma vez só', () async {
    var pedidosDeGps = 0;
    final nunca = Completer<PosicaoAtual?>();
    var agora = DateTime(2030, 1, 1, 12);
    final r = repo(() {
      pedidosDeGps++;
      return nunca.future; // o GPS do aparelho não responde
    }, agora: () => agora);

    for (var i = 0; i < 6; i++) {
      await atualizar(r); // cada uma espera 1,5 s no máximo e segue sem distância
      agora = agora.add(const Duration(seconds: 8)); // intervalo da Home
    }
    expect(pedidosDeGps, 1, reason: 'cada pedido de GPS acorda o serviço de localização do Android');
    expect(pedidas, hasLength(6)); // a lista de pedidos continua carregando
    expect(pedidas.every((p) => !p.url.queryParameters.containsKey('lat')), isTrue);
  });

  test('a posição obtida é reaproveitada por 2 minutos e depois renovada', () async {
    var pedidosDeGps = 0;
    var agora = DateTime(2030, 1, 1, 12);
    final r = repo(() async {
      pedidosDeGps++;
      return aqui;
    }, agora: () => agora);

    await atualizar(r);
    expect(pedidas.last.url.queryParameters['lat'], '-19.9');
    for (var i = 0; i < 10; i++) {
      agora = agora.add(const Duration(seconds: 8));
      await atualizar(r);
    }
    expect(pedidosDeGps, 1);
    expect(pedidas.last.url.queryParameters['lat'], '-19.9'); // segue com distância

    agora = agora.add(const Duration(minutes: 2));
    await atualizar(r);
    expect(pedidosDeGps, 2);
  });

  test('depois de uma falha, espera 1 minuto antes de pedir de novo', () async {
    var pedidosDeGps = 0;
    var agora = DateTime(2030, 1, 1, 12);
    final r = repo(() async {
      pedidosDeGps++;
      throw StateError('sem sinal');
    }, agora: () => agora);

    await atualizar(r);
    for (var i = 0; i < 5; i++) {
      agora = agora.add(const Duration(seconds: 8));
      await atualizar(r);
    }
    expect(pedidosDeGps, 1);
    expect(pedidas, hasLength(6)); // sem localização, a Home carrega do mesmo jeito

    agora = agora.add(const Duration(minutes: 1));
    await atualizar(r);
    expect(pedidosDeGps, 2);
  });

  test('o pedido lento que termina depois guarda a posição para as próximas atualizações',
      () async {
    final tardia = Completer<PosicaoAtual?>();
    var pedidosDeGps = 0;
    var agora = DateTime(2030, 1, 1, 12);
    final r = repo(() {
      pedidosDeGps++;
      return tardia.future;
    }, agora: () => agora);

    await atualizar(r); // demora: segue sem distância
    tardia.complete(aqui);
    await Future<void>.delayed(Duration.zero);
    agora = agora.add(const Duration(seconds: 8));
    await atualizar(r);
    expect(pedidasComLat(pedidas), 1);
    expect(pedidosDeGps, 1);
  });

  group('BUG-P01: Login com teclado aberto', () {
    for (final (largura, altura, teclado, escala) in [
      (320.0, 568.0, 260.0, 1.0),
      (411.0, 700.0, 330.0, 1.3),
      (390.0, 844.0, 300.0, 1.0),
    ]) {
      testWidgets('${largura.toInt()}x${altura.toInt()} fonte x$escala: "Entrar" inteiro acima do teclado',
          (tester) async {
        tester.view.physicalSize = Size(largura, altura);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: teclado);
        tester.platformDispatcher.textScaleFactorTestValue = escala;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: LoginTela(servico: ServicoAuthFake())));
        await tester.pumpAndSettle();

        // A área rolável vai até o teclado: o rodapé não ocupa lugar fixo.
        final rolagem = tester.getRect(find.byType(SingleChildScrollView).first);
        expect(rolagem.bottom, closeTo(altura - teclado, 0.5), reason: 'rodapé fixo roubando espaço');

        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -6000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final entrar = tester.getRect(find.widgetWithText(BotaoPrimario, 'Entrar'));
        expect(entrar.top, greaterThanOrEqualTo(0));
        expect(entrar.bottom, lessThanOrEqualTo(altura - teclado + 0.5), reason: 'botão atrás do teclado');
        expect(entrar.height, greaterThanOrEqualTo(44), reason: 'botão esmagado');
        expect(find.widgetWithText(BotaoPrimario, 'Entrar').hitTestable(), findsOneWidget);
        // O link de criar conta vem depois do botão, sem cobri-lo.
        final criar = tester.getRect(find.text('Criar conta'));
        expect(criar.top, greaterThanOrEqualTo(entrar.bottom));
      });
    }

    testWidgets('sem teclado o rodapé continua fixo embaixo', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: LoginTela(servico: ServicoAuthFake())));
      await tester.pumpAndSettle();
      final rolagem = tester.getRect(find.byType(SingleChildScrollView).first);
      final criar = tester.getRect(find.text('Criar conta'));
      expect(criar.top, greaterThanOrEqualTo(rolagem.bottom)); // fora da rolagem, fixo
    });
  });
}

int pedidasComLat(List<http.Request> p) =>
    p.where((r) => r.url.queryParameters.containsKey('lat')).length;

