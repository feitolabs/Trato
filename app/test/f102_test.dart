// TERMOS-APP4: textos de MEI, relato em 24 h (8.2), versão dos Termos num só lugar (1.4),
// atendimento por pessoa (25.5) e check-out sem código (5.7).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/config_publica.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/servico_ajuda_local.dart';
import 'package:trato/telas/auth/recuperar_senha_tela.dart';
import 'package:trato/telas/comuns/textos_dos_termos.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/telas/profissional/check_out_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/conclusao/dados_exemplo.dart';
import 'apoio/exemplos/telas/profissional/servico_check_out_fake.dart';
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

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

/// API simulada: pedido aguardando confirmação, com ou sem o código no check-out.
RepositorioPedidosApi _repo({required bool semCodigo}) => RepositorioPedidosApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        final Object corpo = switch (req.url.path) {
          '/v1/pedidos/p1' => {
              'id': 'p1',
              'cliente_id': 'c1',
              'estado': 'em_confirmacao',
              'estado_nome': 'Em confirmação',
              'aberto_em': '2026-11-20T10:00:00Z',
              'acoes_permitidas': ['confirmar_conclusao', 'abrir_disputa'],
              'check_out_sem_codigo': semCodigo,
            },
          '/v1/pedidos/p1/saldo' => {
              'cliente_pagou_centavos': 10000,
              'retido_centavos': 10000,
              'a_liberar_centavos': 0,
              'liberado_centavos': 0,
            },
          '/v1/pedidos/p1/eventos' => [
              {'acao': 'fazer_check_out', 'para': 'em_confirmacao', 'em': '2026-11-24T15:00:00Z'},
            ],
          _ => <Object>[],
        };
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }),
    ));

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() {
    ligarDemoNosTestes();
    ConfigPublica.atual = const ConfigPublica();
  });

  test('1. nenhum texto antigo de "CNPJ" no menu, no diálogo e no título', () {
    final fontes = [
      'lib/telas/fluxo/rotas.dart',
      'lib/telas/profissional_mei/meu_cnpj_tela.dart',
    ].map((f) => File(f).readAsStringSync()).join();
    for (final antigo in ["'Meu CNPJ'", "'Falta o seu CNPJ'", "'Informar meu CNPJ'"]) {
      expect(fontes, isNot(contains(antigo)));
    }
    expect(fontes, contains("'Meu MEI'"));
    expect(fontes, contains("'CNPJ do MEI'"));
  });

  test('2. relato: padrão 24 h; o valor do servidor continua mandando', () {
    expect(const ConfigPublica().prazoRespostaDisputaHoras, 24);
    expect(ConfigPublica.deJson(const {}).prazoRespostaDisputaHoras, 24);
    expect(
        ConfigPublica.deJson(const {'prazo_resposta_disputa_horas': 48}).prazoRespostaDisputaHoras,
        48);
  });

  test('3. a versão gravada é a do texto que o app mostra, de um único lugar', () {
    final termos = File('assets/legal/termos-de-uso.md').readAsStringSync();
    expect(termos, contains('**Versão $versaoDosTermos —'));
    final auth = File('lib/auth/servico_auth_supabase.dart').readAsStringSync();
    expect(auth, contains("'termos_versao': versaoDosTermos,"));
  });

  test('5.7: sem código não há prazo de confirmação tácita; com código segue igual', () async {
    final sem = await _repo(semCodigo: true).conclusao('p1');
    expect(sem.prazoConfirmacao, isNull);
    final pedidoSem = await _repo(semCodigo: true).acompanhar('p1');
    expect(pedidoSem.prazoConfirmacao, textoEncerradoSemCodigo);

    final com = await _repo(semCodigo: false).conclusao('p1');
    expect(com.prazoConfirmacao, contains('o pagamento é liberado'));
    final pedidoCom = await _repo(semCodigo: false).acompanhar('p1');
    expect(pedidoCom.prazoConfirmacao, contains('para confirmar'));
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('5.7: conclusão sem código fala do analista; com código não ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        for (final semCodigo in [true, false]) {
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(ConclusaoTela(
            resumo: ResumoConclusao(
              numeroPedido: '#AB12',
              nomeProfissional: 'Carlos',
              legendaFotoAntes: 'Antes',
              legendaFotoDepois: 'Depois',
              orcamentoCentavos: 10000,
              aditivoCentavos: 0,
              codigo: '1234',
              avisoLiberacao: 'x',
              checkOutSemCodigo: semCodigo,
            ),
          )));
          await t.pumpAndSettle();
          expect(find.text(textoAnalistaDecide, skipOffstage: false),
              semCodigo ? findsOneWidget : findsNothing);
          expect(t.takeException(), isNull);
        }
      });

      testWidgets('5.7: o check-out sem código avisa o profissional ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(CheckOutTela(servico: ServicoCheckOutFake(), tituloBarra: 'Pedido #AB12', remoto: true)));
        await t.pumpAndSettle();
        expect(find.text(textoAnalistaDecide), findsNothing);
        final link = find.text('Cliente sem bateria ou sinal?');
        await t.scrollUntilVisible(link, 150, scrollable: find.byType(Scrollable).first);
        await t.ensureVisible(link);
        await t.pumpAndSettle();
        await t.tap(link);
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text(textoAnalistaDecide), 150,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(textoAnalistaDecide), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('25.5: ajuda, relato e recuperar senha falam em pessoa ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(AjudaTela(
          servico: const ServicoAjudaLocal(),
          aoFalarComSuporte: () {},
        )));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.textContaining(textoAtendimentoHumano), 200,
            scrollable: find.byType(Scrollable).first);
        expect(t.takeException(), isNull);

        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(_app(const RelatarProblemaTela(dados: dadosRelatoExemplo)));
        await t.pumpAndSettle();
        expect(find.textContaining(textoAtendimentoHumano, skipOffstage: false), findsOneWidget);

        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(_app(const RecuperarSenhaTela()));
        await t.pumpAndSettle();
        expect(find.text(textoAtendimentoHumano, skipOffstage: false), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  test('25.5: a pergunta frequente existe mesmo sem e-mail do servidor', () {
    expect(
        ServicoAjudaLocal.perguntasFrequentes
            .any((p) => p.resposta.contains(textoAtendimentoHumano)),
        isTrue);
  });
}
