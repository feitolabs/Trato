// APP-VALIDADE-PAG: a tela de pagamento mostra a validade que o servidor manda e a devolução.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/comuns/orcamento_vencido.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';

import 'apoio/fontes.dart';

RepositorioPagamentoApi _repo(Map<String, Object?> pagamento, [List<String>? chamadas]) =>
    RepositorioPagamentoApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        chamadas?.add(r.url.path);
        final Object corpo = r.url.path.endsWith('/pagamento') ? pagamento : <String, Object>{};
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200,
            headers: const {'content-type': 'application/json'});
      }),
    ));

const _base = <String, Object?>{
  'valor_centavos': 20000,
  'meios_disponiveis': ['pix'],
};

void _janela(WidgetTester t) {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('mostra a validade enviada, sem tirar o botão de pagar', (t) async {
    final dados = await _repo({..._base, 'validade_ate': '2099-11-30T15:00:00Z'}).dados('p1');
    _janela(t);
    await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: PagamentoTela(dados: dados)));
    await t.pumpAndSettle();
    expect(find.textContaining('Orçamento válido até 30/11/2099, '), findsOneWidget);
    expect(find.textContaining('Pagar R\$'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final (nome, extra) in [
    ('ausente', <String, Object?>{}),
    ('null', <String, Object?>{'validade_ate': null}),
    ('inválido', <String, Object?>{'validade_ate': 'amanhã'}),
  ]) {
    testWidgets('validade $nome: não mostra nada e não quebra', (t) async {
      final dados = await _repo({..._base, ...extra}).dados('p1');
      expect(dados.validadeAte, isNull);
      _janela(t);
      await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: PagamentoTela(dados: dados)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('validade-orcamento')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('já vencido na abertura: sem "Pagar", com o aviso', (t) async {
    final dados = await _repo({..._base, 'validade_ate': '2020-01-01T12:00:00Z'}).dados('p1');
    _janela(t);
    await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: PagamentoTela(dados: dados)));
    await t.pumpAndSettle();
    expect(find.text(textoOrcamentoVencido), findsOneWidget);
    expect(find.textContaining('Pagar R\$'), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final (nome, extra) in [
    ('pago', <String, Object?>{'pagamento_confirmado': true}),
    ('em confirmação', <String, Object?>{'estado': 'aguardando_confirmacao'}),
  ]) {
    testWidgets('vencido mas $nome: a tela não muda', (t) async {
      final dados =
          await _repo({..._base, 'validade_ate': '2020-01-01T12:00:00Z', ...extra}).dados('p1');
      _janela(t);
      await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: PagamentoTela(dados: dados)));
      await t.pumpAndSettle();
      expect(find.text(textoOrcamentoVencido), findsNothing);
      expect(find.textContaining('Pagar R\$'), findsOneWidget);
    });
  }

  test('recalcular (cupom ou Tratinhos) mantém a validade do servidor', () async {
    final repo = _repo({..._base, 'validade_ate': '2026-11-30T15:00:00Z'});
    final dados = await repo.recalcular('p1', usarMoedas: true);
    expect(dados.validadeAte, DateTime.utc(2026, 11, 30, 15).toLocal());
  });

  testWidgets('estado_pagamento "devolvida" do servidor mostra o aviso', (t) async {
    final chamadas = <String>[];
    final repo = _repo({'pago': false, 'estado_pagamento': 'devolvida'}, chamadas);
    _janela(t);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: AguardandoPagamentoTela(
        consultar: () => repo.status('p1'),
        aoConfirmar: () => fail('não confirma'),
      ),
    ));
    await t.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text('Pagamento devolvido'), findsOneWidget);
    expect(find.text('A cobrança consta como devolvida.'), findsOneWidget);
    expect(chamadas, ['/v1/contratos/p1/pagamento']);
    expect(t.takeException(), isNull);
  });
}
