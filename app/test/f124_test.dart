// APP-52-ORCAMENTO: o orçamento só sai com o que a cláusula 5.2 pede.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';

import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'apoio/fontes.dart';
import 'apoio/orcamento.dart';

const _erroGarantia = 'Escolha o prazo da garantia.';
const _erroPrazo = 'Informe em quantos dias pretende concluir (mínimo 1 dia).';
const _erroValidade = 'Informe por quantos dias o orçamento vale (mínimo 1 dia).';
const _erroFora = 'Diga o que não está incluído. Se nada ficar de fora, escreva isso.';

Future<List<OrcamentoPronto>> _abrir(
  WidgetTester t, {
  ModoOrcamento modo = ModoOrcamento.valorFechado,
  int? garantia,
  int? prazo,
  String? fora,
  Size tamanho = const Size(390, 1600),
  double fonte = 1,
}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final enviados = <OrcamentoPronto>[];
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: CalculadoraOrcamentoTela(
      servico: ServicoOrcamentoFake(),
      tituloPedido: 'Trocar tomada',
      modoInicial: modo,
      valorFechadoInicial: '200,00',
      horasInicial: '2',
      valorHoraInicial: '90',
      garantiaInicialDias: garantia,
      prazoExecucaoInicialDias: prazo,
      foraDoEscopoInicial: fora,
      aoEnviar: enviados.add,
    ),
  ));
  await t.pumpAndSettle();
  return enviados;
}

Future<void> _enviar(WidgetTester t) async {
  await t.tap(find.text('Enviar orçamento'));
  await t.pumpAndSettle();
}

Future<void> _escolherGarantia(WidgetTester t, String opcao) async {
  final campo = find.byType(DropdownButtonFormField<int>);
  await t.ensureVisible(campo);
  await t.pumpAndSettle();
  await t.tap(campo);
  await t.pumpAndSettle();
  await t.tap(find.text(opcao).last);
  await t.pumpAndSettle();
}

String _texto(WidgetTester t, String rotulo) =>
    t.widget<TextField>(campoDoOrcamento(rotulo)).controller!.text;

void main() {
  setUpAll(carregarFontesTrato);

  for (final modo in ModoOrcamento.values) {
    testWidgets('novo (${modo.name}): nada vem escolhido e cada falta tem seu aviso', (t) async {
      final enviados = await _abrir(t, modo: modo);
      expect(find.text('Escolha'), findsOneWidget);
      expect(_texto(t, 'Prazo estimado para concluir'), isEmpty);
      expect(_texto(t, 'Validade do orçamento'), isEmpty);
      expect(_texto(t, 'O que não está incluído'), isEmpty);
      expect(find.textContaining('Válido por'), findsNothing);
      await _enviar(t);
      expect(enviados, isEmpty);
      for (final erro in [_erroGarantia, _erroPrazo, _erroValidade, _erroFora]) {
        expect(find.text(erro), findsOneWidget);
      }
    });
  }

  for (final (falta, aviso) in [
    ('garantia', _erroGarantia),
    ('prazo', _erroPrazo),
    ('validade', _erroValidade),
    ('fora', _erroFora),
  ]) {
    testWidgets('faltando só $falta, não envia', (t) async {
      final enviados = await _abrir(
        t,
        garantia: falta == 'garantia' ? null : 90,
        prazo: falta == 'prazo' ? null : 2,
      );
      await completarOrcamento(
        t,
        validade: falta == 'validade' ? '0' : '7',
        naoIncluido: falta == 'fora' ? '   ' : 'Pintura',
      );
      await _enviar(t);
      expect(enviados, isEmpty);
      expect(find.text(aviso), findsOneWidget);
    });
  }

  testWidgets('preenchido pelo profissional: envia o que ele escolheu', (t) async {
    final enviados = await _abrir(t);
    await _escolherGarantia(t, '60 dias');
    await t.enterText(campoDoOrcamento('Prazo estimado para concluir'), '4');
    await completarOrcamento(t, validade: '10', naoIncluido: 'Material');
    expect(find.textContaining('Válido por 10 dias'), findsOneWidget);
    await _enviar(t);
    final o = enviados.single;
    expect(
      (o.garantiaDias, o.prazoExecucaoDias, o.validadeDias, o.foraDoEscopo),
      (60, 4, 10, 'Material'),
    );
  });

  testWidgets('edição: mantém o que já foi escolhido e pede a validade de novo', (t) async {
    final enviados = await _abrir(t, garantia: 90, prazo: 5, fora: 'Pintura');
    await _enviar(t);
    expect(enviados, isEmpty);
    expect(find.text(_erroValidade), findsOneWidget);
    expect(find.text(_erroGarantia), findsNothing);
    expect(find.text(_erroPrazo), findsNothing);
    expect(find.text(_erroFora), findsNothing);
  });

  testWidgets('320 px com fonte 1,3x: os avisos cabem na tela', (t) async {
    for (final modo in ModoOrcamento.values) {
      await _abrir(t, modo: modo, tamanho: const Size(320, 568), fonte: 1.3);
      await _enviar(t);
      expect(t.takeException(), isNull, reason: modo.name);
    }
  });

  test('a validade enviada ao servidor conta os dias escolhidos', () async {
    Map<String, dynamic>? corpo;
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        corpo = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('{}', 201, headers: const {'content-type': 'application/json'});
      }),
    );
    final antes = DateTime.now().toUtc();
    await ServicoOrcamentoApi(api, pedidoId: 'p1').enviar(const OrcamentoPronto(
      decimosDeslocamento: 0,
      decimosDeHora: 0,
      valorHoraCentavos: 0,
      valorFechadoCentavos: 20000,
      garantiaDias: 60,
      prazoExecucaoDias: 4,
      validadeDias: 10,
      itens: [],
      materialPorMim: true,
      pedirSinalMaterial: false,
      totalCentavos: 20000,
      foraDoEscopo: 'Material',
    ));
    final validade = DateTime.parse(corpo!['validade_ate'] as String);
    expect(validade.difference(antes).inMinutes, closeTo(10 * 24 * 60, 1));
    expect(corpo!['garantia_dias'], 60);
    expect(corpo!['prazo_execucao_dias'], 4);
    expect(corpo!['fora_do_escopo'], 'Material');
  });
}
