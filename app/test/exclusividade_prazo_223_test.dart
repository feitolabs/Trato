// Termos 22.3 (prazo da exclusividade suspenso) e 5.2 ("não incluído" obrigatório).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'apoio/orcamento.dart';

Map<String, dynamic> _json(Map<String, dynamic> extra) => {
      'id': 'e1',
      'pedido_id': 'p1',
      'cliente_id': 'c1',
      'profissional_id': 'x1',
      'status': 'aguardando_cliente',
      'criada_em': '2026-11-27T10:00:00Z',
      ...extra,
    };

Future<void> _abrir(WidgetTester t, Widget tela) async {
  t.view.physicalSize = const Size(320, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

Widget _cliente({required bool suspenso, DateTime? ate}) => PedidoAbertoTela(
      numero: 'AB12',
      dados: DadosDoPedido(
        titulo: 'Trocar chuveiro',
        descricao: 'Chuveiro queimado.',
        faixaMaxCentavos: 30000,
        ofertaExclusividade: OfertaExclusividadeCliente(
          id: 'e1',
          pedidoId: 'p1',
          status: 'aguardando_cliente',
          responderAte: ate,
          prazoSuspenso: suspenso,
        ),
      ),
      aoSalvar: ({
        required String descricao,
        required int faixaMaxCentavos,
        required String logradouro,
        required String numero,
        required String bairro,
        String? cep,
      }) async =>
          null,
      aoVerOrcamentos: () {},
    );

Widget _profissional({required bool suspenso}) {
  final ex = ExclusividadeProfissional(
      id: 'e1', pedidoId: 'p1', status: 'aguardando_cliente', prazoSuspenso: suspenso);
  return DetalhePedidoTela(
    dados: DetalhePedido(
      pedido: PedidoAberto(
          id: 'p1', titulo: 'Chuveiro', bairro: 'Savassi', prazo: 'hoje', exclusividade: ex),
      fechaEm: 'Publicado agora',
      clienteResumo: '',
      legendasFotos: const [],
      descricao: 'Trocar.',
      linhas: const [],
      exclusividade: ex,
    ),
  );
}

void main() {
  test('responder_ate nulo e prazo_suspenso: lidos; ausentes não quebram', () {
    for (final (extra, suspenso) in [
      (<String, dynamic>{'responder_ate': null, 'prazo_suspenso': true}, true),
      (<String, dynamic>{'responder_ate': null, 'prazo_suspenso': null}, false),
      (<String, dynamic>{}, false),
    ]) {
      final a = ExclusividadeApi.deJson(_json(extra));
      final b = OfertaExclusividadeApi.deJson(_json(extra));
      expect((a.responderAte, a.prazoSuspenso), (null, suspenso));
      expect((b.responderAte, b.prazoSuspenso), (null, suspenso));
    }
  });

  for (final ate in <DateTime?>[null, DateTime(2026, 12, 1, 18)]) {
    testWidgets('cliente, suspenso (data: $ate): explica e não mostra contagem', (t) async {
      await _abrir(t, _cliente(suspenso: true, ate: ate));
      expect(find.byKey(const ValueKey('prazo-exclusividade-suspenso')), findsOneWidget);
      expect(find.textContaining('Responda até'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('cliente, sem suspensão: data quando vem; nada quando é nula', (t) async {
    await _abrir(t, _cliente(suspenso: false, ate: DateTime(2026, 12, 1, 18)));
    expect(find.textContaining('Responda até'), findsOneWidget);
    await _abrir(t, _cliente(suspenso: false));
    expect(find.textContaining('Responda até'), findsNothing);
    expect(find.textContaining('Prazo suspenso'), findsNothing);
  });

  testWidgets('profissional, suspenso: explica e não fala em horas', (t) async {
    await _abrir(t, _profissional(suspenso: true));
    expect(find.textContaining('Prazo suspenso'), findsOneWidget);
    expect(find.textContaining('6h'), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final edicao in [false, true]) {
    testWidgets('não incluído com 1 caractere ou só espaços não envia (edição: $edicao)',
        (t) async {
      final enviados = <OrcamentoPronto>[];
      await _abrir(
        t,
        CalculadoraOrcamentoTela(
          servico: ServicoOrcamentoFake(),
          tituloPedido: 'Tomada',
          edicao: edicao,
          modoInicial: ModoOrcamento.valorFechado,
          valorFechadoInicial: '200,00',
          garantiaInicialDias: 90,
          prazoExecucaoInicialDias: 2,
          foraDoEscopoInicial: edicao ? '' : null,
          aoEnviar: enviados.add,
        ),
      );
      final botao = find.textContaining(RegExp(r'^Enviar (orçamento|nova versão)$'));
      for (final (texto, erro) in [
        ('   ', 'Diga o que não está incluído'),
        (' x ', 'pelo menos 2 caracteres'),
      ]) {
        await completarOrcamento(t, validade: '7', naoIncluido: texto);
        await t.ensureVisible(botao.last);
        await t.tap(botao.last);
        await t.pumpAndSettle();
        expect(enviados, isEmpty);
        expect(
          find.descendant(
              of: find.ancestor(
                  of: campoDoOrcamento('O que não está incluído'),
                  matching:
                      find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CampoTrato')),
              matching: find.textContaining(erro)),
          findsOneWidget,
        );
      }
      await completarOrcamento(t, validade: '7', naoIncluido: 'TV');
      await t.ensureVisible(botao.last);
      await t.tap(botao.last);
      await t.pumpAndSettle();
      expect(enviados.single.foraDoEscopo, 'TV');
    });
  }
}
