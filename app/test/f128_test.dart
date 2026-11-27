// APP-133: valor (também em reais) e validade dos Tratinhos, só com o que o servidor manda.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/ajuda/servico_ajuda_local.dart';
import 'package:trato/telas/carteira/avaliar_cliente_tela.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/comuns/prazo_avaliacao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/indicacoes/indique_e_ganhe_tela.dart';
import 'package:trato/telas/indicacoes/servico_fake.dart';
import 'package:trato/telas/perfil_cliente/extrato_tratinhos_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';

import 'apoio/exemplos/telas/carteira/dados_exemplo.dart';
import 'apoio/fontes.dart';

PerfilCliente _perfil({
  int? valor = 1,
  List<CreditoPorValidade> creditos = const [],
  DateTime? venceEm,
}) =>
    PerfilCliente(
      nome: 'Ana',
      iniciais: 'A',
      resumo: '',
      grupos: const [],
      moedas: 80,
      moedasValorCentavos: valor,
      moedasCreditos: creditos,
      moedasVenceEm: venceEm,
    );

Future<void> _abrir(WidgetTester t, Widget tela) async {
  t.view.physicalSize = const Size(320, 900);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('cada crédito mostra Tratinhos, reais e vencimento', (t) async {
    await _abrir(
      t,
      ExtratoTratinhosTela(
        perfil: _perfil(creditos: [
          CreditoPorValidade(moedas: 30, expiraEm: DateTime(2027, 1, 5)),
          const CreditoPorValidade(moedas: 50),
        ]),
      ),
    );
    expect(find.text('Valor: 1 Tratinho = R\$ 0,01'), findsOneWidget);
    expect(find.text('30 Tratinhos = R\$ 0,30: vence em 05/01/2027'), findsOneWidget);
    expect(find.text('50 Tratinhos = R\$ 0,50: vencimento não informado'), findsOneWidget);
  });

  testWidgets('sem dado do servidor: nem reais nem data inventados', (t) async {
    await _abrir(t, ExtratoTratinhosTela(perfil: _perfil(valor: null)));
    expect(find.textContaining('R\$'), findsNothing);
    expect(find.text('Vencimento não informado agora.'), findsOneWidget);
    expect(find.textContaining('90 dias'), findsNothing);
  });

  testWidgets('indicação mostra o valor só quando ele vem', (t) async {
    await _abrir(t, IndiqueEGanheTela(servico: ServicoIndicacoesFake(), valorMoedaCentavos: 1));
    expect(find.text('Valor: 1 Tratinho = R\$ 0,01'), findsOneWidget);
    await _abrir(t, IndiqueEGanheTela(key: UniqueKey(), servico: ServicoIndicacoesFake()));
    expect(find.textContaining('Valor: 1 Tratinho'), findsNothing);
  });

  testWidgets('carteira do profissional não promete quantidade fixa', (t) async {
    await _abrir(
      t,
      const Scaffold(body: CarteiraTela(dados: DadosExemploCarteira.completo, soExtrato: false)),
    );
    expect(find.textContaining('50 Tratinhos'), findsNothing);
  });

  testWidgets('avaliar cliente usa a quantidade do servidor, sem prazo fixo', (t) async {
    final prazo = PrazoAvaliacao.deJson({'bonus_moedas': 30});
    await _abrir(
      t,
      AvaliarClienteTela(pedidoNumero: '#1', prazo: prazo, aoEnviar: (_, __) async => 0),
    );
    expect(find.textContaining('rende +30 Tratinhos'), findsOneWidget);
    expect(find.textContaining('dias'), findsNothing);
    expect(PrazoAvaliacao.deJson({'bonus_moedas': 0}).bonusMoedas, isNull);
    expect(PrazoAvaliacao.deJson({}).bonusMoedas, isNull);
  });

  test('a ajuda não promete bônus nem prazo', () async {
    final itens = await const ServicoAjudaLocal().perguntas();
    final texto = itens.singleWhere((p) => p.pergunta == 'O que são Tratinhos?').resposta;
    expect(texto, contains('50 Tratinhos = R\$ 0,50'));
    expect(texto, isNot(contains('Você ganha')));
    expect(texto, isNot(contains('dias')));
  });

  test('os créditos e o vencimento chegam do servidor até o Perfil', () async {
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        final Object corpo = r.url.path == '/v1/me/moedas'
            ? {
                'saldo': 30,
                'valor_moeda_centavos': 1,
                'saldo_vence_em': '2027-01-05T15:00:00Z',
                'creditos': [
                  {'moedas': 30, 'expira_em': '2027-01-05T15:00:00Z'},
                ],
                'extrato': [
                  {
                    'tipo': 'bonus_indicacao',
                    'quantidade': 30,
                    'criada_em': '2026-10-07T15:00:00Z',
                    'expira_em': '2027-01-05T15:00:00Z',
                  }
                ],
              }
            : <String, Object>{'id': 'u1', 'nome': 'Ana'};
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200,
            headers: const {'content-type': 'application/json'});
      }),
    );
    final perfil = RotasTrato.soNoPerfilParaTeste(await RepositorioPerfilApi(api).carregar());
    expect(perfil.moedasCreditos.single.moedas, 30);
    expect(perfil.moedasCreditos.single.expiraEm, isNotNull);
    expect(perfil.moedasVenceEm, isNotNull);
    expect(perfil.moedasExtrato, hasLength(1));
  });
}
