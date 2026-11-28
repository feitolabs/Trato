// APP-LOTE-B: IP do aceite (1.4), data do selo (10.2), envio de orçamento (5.2) e avisos novos.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/cliente/avatar_iniciais.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/legal/registro_do_aceite.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/profissional_inicio/tratinhos_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'apoio/fontes.dart';

ClienteApi _api(Future<Object> Function(http.Request r) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato(),
      cliente: MockClient((r) async => http.Response.bytes(
          utf8.encode(jsonEncode(await responder(r))), 200,
          headers: const {'content-type': 'application/json'})),
    );

void _celularPequeno(WidgetTester t) {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

class _Consulta implements ConsultaDoAceite {
  _Consulta(this.ip);
  final String? ip;

  @override
  Future<RegistroDoAceite?> registroDoAceite() async => RegistroDoAceite.deJson({
        'registro_disponivel': true,
        'versao_aceita': '1.2',
        'aceita_em': '2026-11-22T12:00:00Z',
        if (ip != null) 'aceito_ip': ip,
      });
}

Notificacao _aviso(String tipo, {String? tela, String? papel, String? pedido}) => Notificacao(
      id: 'n1',
      tipo: tipoDaNotificacao(tipo),
      titulo: 't',
      texto: 'x',
      quando: 'agora',
      tela: tela,
      papel: papel,
      destinoId: pedido,
      tipoApi: tipo,
    );

void main() {
  setUpAll(carregarFontesTrato);

  for (final ip in ['203.0.113.7', null]) {
    testWidgets('1.4: registro do aceite ${ip == null ? 'sem' : 'com'} IP', (t) async {
      _celularPequeno(t);
      await t.pumpWidget(_app(Scaffold(
          body: SingleChildScrollView(child: CartaoRegistroDoAceite(consulta: _Consulta(ip))))));
      await t.pumpAndSettle();
      expect(find.textContaining('Endereço de IP'), ip == null ? findsNothing : findsOneWidget);
      if (ip != null) expect(find.textContaining(ip), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('10.2: o selo mostra a data só quando vem', (t) async {
    _celularPequeno(t);
    await t.pumpWidget(_app(Scaffold(
      body: Column(children: [
        SeloVerificacao('Verificado', conferidoEm: DateTime(2026, 11, 3, 12)),
        const SeloVerificacao('Verificado Plus'),
      ]),
    )));
    expect(find.text('Verificado\nConferido em 03/11/2026'), findsOneWidget);
    expect(find.text('Verificado Plus'), findsOneWidget);
  });

  for (final data in ['2026-11-03T15:00:00Z', null]) {
    test('10.2: o perfil da API ${data == null ? 'sem' : 'com'} selo_conferido_em', () async {
      final catalogo = RepositorioCatalogoApi(_api((r) async =>
          r.url.path == '/v1/profissionais/p1'
              ? {'id': 'p1', 'nome': 'Exemplo', 'nivel_verificacao': 'verificado',
                  'selo_conferido_em': data}
              : <Object>[]));
      final p = await catalogo.perfil('p1');
      expect(p.seloConferidoEm, data == null ? isNull : DateTime.parse(data));
    });
  }

  test('5.2: o envio manda prazo, validade futura e garantia (inclusive 0)', () async {
    Map<String, dynamic>? corpo;
    final servico = ServicoOrcamentoApi(_api((r) async {
      corpo = jsonDecode(r.body) as Map<String, dynamic>;
      return <String, Object>{};
    }), pedidoId: 'p1');
    await servico.enviar(const OrcamentoPronto(
      decimosDeslocamento: 0,
      decimosDeHora: 0,
      valorHoraCentavos: 0,
      garantiaDias: 0,
      prazoExecucaoDias: 3,
      validadeDias: 7,
      itens: [],
      materialPorMim: false,
      pedirSinalMaterial: false,
      totalCentavos: 10000,
      valorFechadoCentavos: 10000,
    ));
    expect(corpo!['prazo_execucao_dias'], 3);
    expect(corpo!['garantia_dias'], 0);
    expect(DateTime.parse(corpo!['validade_ate'] as String).isAfter(DateTime.now()), isTrue);
    expect(corpo!.containsKey('fora_do_escopo'), isFalse);
  });

  testWidgets('5.2: nova versão de orçamento antigo sem os campos não é enviada', (t) async {
    _celularPequeno(t);
    var envios = 0;
    await t.pumpWidget(_app(CalculadoraOrcamentoTela(
      servico: ServicoOrcamentoFake(),
      tituloPedido: 'Pedido de exemplo',
      edicao: true,
      horasInicial: '2',
      valorHoraInicial: '50,00',
      foraDoEscopoInicial: 'Material',
      aoEnviar: (_) => envios++,
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('Enviar nova versão'));
    await t.pumpAndSettle();
    expect(envios, 0);
    for (final erro in [
      'Escolha o prazo da garantia.',
      'Informe em quantos dias pretende concluir',
      'Informe por quantos dias o orçamento vale',
    ]) {
      expect(find.textContaining(erro, skipOffstage: false), findsWidgets, reason: erro);
    }
    expect(t.takeException(), isNull);
  });

  group('avisos novos', () {
    for (final tipo in ['conta.avaliacao_ocultada', 'execucao.janela_encerrada']) {
      test('$tipo abre o pedido, com e sem tela', () {
        for (final tela in ['pedido', null]) {
          final r = RotasTrato.destinoDaCaixa(
              _aviso(tipo, tela: tela, papel: 'profissional', pedido: 'p1'),
              modoAtualProfissional: false);
          expect(r, const ResultadoLink.valido(DestinoApp.pedido, 'p1', papel: 'profissional'));
        }
      });
    }

    for (final carteira in ['cliente', 'profissional']) {
      test('tratinhos_vencendo ($carteira) abre o saldo da carteira', () {
        final esperado = ResultadoLink.valido(DestinoApp.tratinhos, null, papel: carteira);
        for (final tela in ['notificacoes', null]) {
          expect(
              RotasTrato.destinoDaCaixa(
                  _aviso('pagamento.tratinhos_vencendo', tela: tela, papel: carteira),
                  modoAtualProfissional: false),
              esperado);
        }
        expect(
            resultadoDoPush({
              'evento': 'pagamento.tratinhos_vencendo',
              'tela': 'notificacoes',
              'carteira': carteira,
              'vence_em': '2026-12-10',
            }),
            esperado);
      });
    }

    testWidgets('saldo do profissional cabe no celular pequeno', (t) async {
      _celularPequeno(t);
      await t.pumpWidget(_app(const TratinhosProfissionalTela(
          resumo: ResumoExclusividades(
              itens: [], ativasOuPendentes: 0, limiteMaximo: 3, saldoProfissional: 50))));
      expect(find.text('50 Tratinhos'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
