// APP-LOTE-C: orçamento antigo incompleto (5.2), aditivo depois da execução (6.8) e antifraude.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/aditivo/aditivo.dart';
import 'package:trato/telas/aditivo/responder_aditivo_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/comuns/orcamento_vencido.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';

import 'apoio/fontes.dart';

const _mensagem = 'Este orçamento é antigo e não tem prazo, validade e garantia (Termos 5.2). '
    'O profissional precisa enviar um orçamento novo com os três.';
const _recusa = ErroTrato(TipoErro.recusado, _mensagem, codigoHttp: 409);

ClienteApi _api((int, Object) Function(http.Request r) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato(),
      cliente: MockClient((r) async {
        final (status, corpo) = responder(r);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
            headers: const {'content-type': 'application/json'});
      }),
    );

Future<void> _abrir(WidgetTester t, Widget tela) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

final _orcamento = Orcamento(
  id: 'o1',
  profissional: 'Exemplo',
  iniciais: 'EX',
  verificacao: '',
  totalCentavos: 20000,
  nota: 0,
  notaResumo: semAvaliacoes,
  servicosResumo: '0',
  servicosConcluidos: 0,
  quando: 'hoje',
  inicio: DateTime(2026, 11, 20),
  garantia: 'não informada',
  observacao: '',
  detalhe: const DetalheOrcamento(
    validoAte: '—',
    itens: [],
    notaMaterial: '',
    agendaTitulo: '',
    agendaDetalhe: '',
    garantiaTitulo: 'Garantia',
    garantiaDetalhe: '',
    foraDoEscopo: '',
    cancelamento: '',
  ),
);

void main() {
  setUpAll(carregarFontesTrato);

  test('5.2: as três rotas de negociação devolvem a recusa reconhecida pelo app', () async {
    final caminhos = <String>[];
    final repo = RepositorioOrcamentosApi(_api((r) {
      caminhos.add(r.url.path);
      return (409, {'detail': _mensagem});
    }));
    for (final acao in [
      () => repo.contraproporValor('p1', 'o1', 100),
      () => repo.aceitarContraproposta('p1', 'o1', 100),
      () => repo.proporNovaCondicao('p1', 'o1', 100),
    ]) {
      await expectLater(
          acao(),
          throwsA(isA<ErroTrato>()
              .having((e) => e.mensagem, 'mensagem', _mensagem)
              .having(ehOrcamentoIncompleto, 'incompleto', isTrue)));
    }
    expect(caminhos, hasLength(3));
    expect(
        ehRecusaDoOrcamento(const ErroTrato(
            TipoErro.recusado, 'Este orçamento foi substituído por uma versão mais nova.',
            codigoHttp: 409)),
        isFalse);
  });

  testWidgets('5.2: contraproposta recusada fica junto da ação e a tela segue', (t) async {
    var recusados = 0;
    await _abrir(
      t,
      DetalheOrcamentoTela(
        orcamento: _orcamento,
        aoAceitar: (_) {},
        aoFazerContraproposta: (_) async => throw _recusa,
        aoRecusar: (_) => recusados++,
      ),
    );
    await t.tap(find.text('Fazer contraproposta'));
    await t.pumpAndSettle();
    final aviso = find.byKey(const ValueKey('orcamento-incompleto'));
    expect(aviso, findsOneWidget);
    expect(t.widget<Text>(aviso).data,
        '$_mensagem Peça um orçamento novo ao profissional.');
    expect(find.text('Fazer contraproposta'), findsNothing);
    expect(find.text('Aceitar e ir para o pagamento'), findsOneWidget);
    expect(find.byKey(const ValueKey('botao-recusar-orcamento')), findsOneWidget);
    expect(recusados, 0);
  });

  testWidgets('5.2: na conversa, aceitar e nova proposta orientam o profissional', (t) async {
    await _abrir(
      t,
      ChatPedidoTela(
        conversa: const ConversaPedido(
          nome: 'Exemplo',
          iniciais: 'EX',
          numeroPedido: '#1',
          situacao: 'Aguardando',
          souCliente: false,
          orcamentosAtivos: {'o1'},
          respostasRapidas: [],
          mensagens: [
            MensagemChat(
              tipo: TipoMensagem.texto,
              hora: '10:00',
              texto: 'Contraproposta',
              contraproposta: ContrapropostaChat(
                orcamentoId: 'o1',
                valorCentavos: 100,
                ehPropostaDoProfissional: false,
              ),
            ),
          ],
        ),
        aoAceitarContraproposta: (_) async => throw _recusa,
        aoProporNovaCondicao: () async => throw _recusa,
      ),
    );
    const texto = '$_mensagem Envie um orçamento novo para continuar.';
    final nova = find.text('Nova proposta');
    await t.ensureVisible(nova);
    await t.tap(nova);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('recusa-da-proposta')), findsOneWidget);
    expect(find.text(texto), findsOneWidget);
    expect(t.takeException(), isNull);

    final aceitar = find.text('Aceitar e atualizar orçamento', skipOffstage: false);
    await t.ensureVisible(aceitar);
    await t.pumpAndSettle();
    await t.tap(aceitar);
    await t.pumpAndSettle();
    expect(find.text(texto, skipOffstage: false), findsNWidgets(2));
    expect(find.text('Aceitar e atualizar orçamento', skipOffstage: false), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final (aditivo, pedido, semValor) in [
    ('proposto', 'em_andamento', false),
    ('proposto', 'em_confirmacao', true),
    ('aprovado', 'concluido', true),
    ('pago', 'concluido', false),
    ('cancelado', 'em_andamento', true),
  ]) {
    testWidgets('6.8: aditivo $aditivo com pedido $pedido', (t) async {
      final servico = ServicoAditivoApi(
          _api((r) => switch (r.url.path) {
                '/v1/contratos/p1/aditivos' => (
                    200,
                    [
                      {'id': 'a1', 'descricao': 'Peça', 'valor_centavos': 500, 'estado': aditivo}
                    ]
                  ),
                '/v1/pedidos/p1' => (200, {'estado': pedido}),
                _ => (200, {'nome': 'Exemplo'}),
              }),
          nomeProfissional: 'Exemplo');
      expect((await servico.carregar('p1'))!.semValor, semValor);
      await _abrir(t, ResponderAditivoTela(servico: servico, aditivoId: 'p1'));
      expect(find.text('Aditivo não vale mais'), semValor ? findsOneWidget : findsNothing);
      if (semValor) {
        expect(find.text('Aprovar aditivo'), findsNothing);
        expect(find.textContaining('Pagar'), findsNothing);
      }
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('6.8: aprovar recusado com 409 mostra a mensagem do servidor', (t) async {
    const motivo = 'Só dá para decidir aditivo com o serviço em andamento.';
    var cobrancas = 0;
    final servico = ServicoAditivoApi(
        _api((r) => r.method == 'POST'
            ? (409, {'detail': motivo})
            : r.url.path.endsWith('/aditivos')
                ? (
                    200,
                    [
                      {'id': 'a1', 'descricao': 'Peça', 'valor_centavos': 500, 'estado': 'proposto'}
                    ]
                  )
                : (200, {'estado': 'em_andamento'})),
        nomeProfissional: 'Exemplo');
    await _abrir(
        t,
        ResponderAditivoTela(
            servico: servico, aditivoId: 'p1', aoCobrancaCriada: (_) => cobrancas++));
    await t.tap(find.text('Aprovar aditivo'));
    await t.pumpAndSettle();
    expect(find.text(motivo), findsOneWidget);
    expect(find.text('Aditivo aprovado'), findsNothing);
    expect(cobrancas, 0);
  });

  test('6.8: regra de exibição sem o estado do pedido deixa o servidor decidir', () {
    expect(aditivoSemValor('proposto', null), isFalse);
    expect(aditivoSemValor('recusado', 'concluido'), isFalse);
  });

  test('9.5: sinal antifraude que viesse na resposta não chega ao que o app mostra', () async {
    final api = _api((r) => (
          200,
          {
            'protocolo': 'INC-1',
            'cancelado': true,
            'estado_pedido': 'cancelado',
            'mensagem': 'Relato registrado.',
            'sinais': ['relato_repetido_do_cliente:2'],
          }
        ));
    final r = await ServicoSacApi(api).relatarPessoaDiferente('p1');
    expect('${r.mensagem} ${r.protocolo}', isNot(contains('relato_repetido')));
  });
}
