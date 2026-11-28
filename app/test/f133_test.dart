// APP-AVISOS-100: o app mostra o que o servidor passou a informar.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/servico_recorrencias_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/ausencia/ausencia_tela.dart';
import 'package:trato/telas/conta_bloqueada/pedidos_contratados.dart';
import 'package:trato/telas/contestacao_decisao/contestacao_decisao_tela.dart';
import 'package:trato/telas/contestacao_decisao/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/lgpd/excluir_conta_tela.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/perfil_cliente/extrato_tratinhos_tela.dart';
import 'package:trato/telas/recorrencias/modelos.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

typedef _Resposta = (int, Object) Function(http.Request r);

ClienteApi _api(_Resposta responder, [List<String>? chamadas]) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        chamadas?.add('${r.method} ${r.url.path}');
        final (status, corpo) = responder(r);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
            headers: const {'content-type': 'application/json'});
      }),
    );

void _janela(WidgetTester t, [Size tamanho = const Size(390, 2200)]) {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

const _pendencias = [
  'Valor retido ou a liberar em 1 pedido(s)',
  '2 reembolso(s) ainda não enviado(s)',
];

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('exclusão: pendências, guarda dos Tratinhos e o 409 do servidor', (t) async {
    final servico = ServicoPrivacidadeApi(_api((r) {
      if (r.url.path == '/v1/me/moedas') return (200, {'saldo': 80});
      if (r.method == 'GET') {
        return (
          200,
          {
            'pendencias': _pendencias,
            'tratinhos_a_perder': 0,
            'tratinhos_guardados_ate': '2027-02-20T15:00:00Z',
          }
        );
      }
      return r.body.contains('token_confirmacao')
          ? (409, {'detail': 'Há pendências na conta.'})
          : (200, {'token_confirmacao': 'tk', 'pendencias': _pendencias});
    }));
    _janela(t);
    await t
        .pumpWidget(MaterialApp(theme: TemaTrato.claro, home: ExcluirContaTela(servico: servico)));
    await t.pumpAndSettle();
    for (final p in _pendencias) {
      expect(find.text('• $p'), findsOneWidget);
    }
    expect(find.text('Seus Tratinhos ficam guardados até 20/02/2027.'), findsOneWidget);
    expect(find.textContaining('perde', skipOffstage: false),
        findsOneWidget); // só "Você perde o acesso"
    await _tocar(t, find.text('Continuar'));
    await t.enterText(find.byType(TextField), ExcluirContaTela.palavraConfirmacao);
    await t.pump();
    await _tocar(t, find.text('Excluir minha conta').last);
    expect(find.text('Há pendências na conta.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('cancelar a exclusão já encerrada: a mensagem do servidor chega', () async {
    final servico = ServicoPrivacidadeApi(
        _api((r) => (409, {'detail': 'Este pedido de exclusão já foi encerrado.'})));
    await expectLater(
      servico.cancelarExclusao(),
      throwsA(isA<ErroTrato>()
          .having((e) => e.mensagem, 'mensagem', 'Este pedido de exclusão já foi encerrado.')),
    );
  });

  test('extrato: restauração em português e tipo desconhecido não quebra', () {
    expect(ExtratoTratinhosTela.rotuloTipo('restauracao'), 'Devolução ao restabelecer a conta');
    expect(ExtratoTratinhosTela.rotuloTipo('algo_novo'), isNotEmpty);
    expect(ExtratoTratinhosTela.rotuloTipo(''), 'Movimentação de Tratinhos');
  });

  test('recorrência remota: propor, aceitar e retomar trazem a mensagem do servidor', () async {
    final servico = ServicoRecorrenciasApi(_api((r) => (
          r.url.path == '/v1/recorrencias' ? 422 : 409,
          {'detail': 'Serviço remoto não pode ser repetido.'}
        )));
    final comMensagem = throwsA(isA<ErroTrato>()
        .having((e) => e.mensagem, 'mensagem', 'Serviço remoto não pode ser repetido.'));
    await expectLater(
      servico.propor(
        'p1',
        (
          frequencia: FrequenciaRecorrencia.values.first,
          proximaVisita: DateTime(2027),
          valorCentavos: null,
        ),
      ),
      comMensagem,
    );
    await expectLater(servico.aceitar('r1'), comMensagem);
    await expectLater(servico.retomar('r1'), comMensagem);
  });

  testWidgets('pagamento sem contrato (404): para de consultar e orienta', (t) async {
    final chamadas = <String>[];
    final repo = RepositorioPagamentoApi(
        _api((r) => (404, {'detail': 'Contrato não encontrado.'}), chamadas));
    _janela(t, const Size(320, 640));
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: AguardandoPagamentoTela(
        consultar: () => repo.status('p1'),
        aoConfirmar: () => fail('não confirma'),
      ),
    ));
    await t.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text('Este pagamento não está mais em andamento'), findsOneWidget);
    expect(find.textContaining('peça um orçamento novo'), findsOneWidget);
    expect(chamadas, hasLength(1));
    expect(await _statusDe({'pago': false, 'estado_pagamento': 'sem_cobranca'}),
        StatusPagamento.aguardando);
  });

  for (final (estado, rota, secao) in [
    ('agendado', 'GET /v1/pedidos/p1/ausencia', SecaoAusencia),
    ('concluido', 'GET /v1/pedidos/p1/disputa/contestacoes', SecaoContestacaoDecisao),
  ]) {
    testWidgets('bloqueado, pedido $estado: a ação não fica escondida', (t) async {
      final antes = RotasTrato.repos;
      addTearDown(() {
        RotasTrato.repos = antes;
        RotasTrato.esquecerBloqueio();
      });
      final chamadas = <String>[];
      final api = _api((r) {
        final pedido = {'id': 'p1', 'estado': estado, 'estado_nome': estado};
        if (r.url.path == '/v1/pedidos') return (200, [pedido]);
        if (r.url.path == '/v1/pedidos/p1') return (200, pedido);
        return (404, {'detail': 'Nada aqui.'});
      }, chamadas);
      RotasTrato.repos = repositoriosDemo(
        pedidos: RepositorioPedidosApi(api),
        contestacaoDecisao: ServicoContestacaoDecisaoApi(api),
      );
      _janela(t);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
          MaterialApp(theme: TemaTrato.claro, navigatorKey: nav, home: const Scaffold()));
      RotasTrato.contaFoiBloqueada(() => nav.currentState, 'Conta bloqueada.');
      await t.pumpAndSettle();
      RotasTrato.abrirPedidoContratado(nav.currentState!.overlay!.context, 'p1');
      await t.pumpAndSettle();
      expect(find.byType(PedidoContratadoTela), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w.runtimeType == secao, skipOffstage: false),
          findsOneWidget);
      expect(chamadas, contains(rota));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('bloqueado: o relato leva as fotos tiradas', (t) async {
    final enviados = <Map<String, dynamic>>[];
    final repo = _RepoComFotos(_api((r) {
      return (
        200,
        {
          'id': 'p1',
          'estado': 'em_confirmacao',
          'estado_nome': 'x',
          'acoes_permitidas': ['abrir_disputa']
        }
      );
    }), enviados);
    _janela(t);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PedidoContratadoTela(
        servico: repo,
        pedidoId: 'p1',
        aoFalar: (_, __) {},
        capturarFoto: () async => 'foto.jpg',
      ),
    ));
    await t.pumpAndSettle();
    await _tocar(t, find.byKey(const ValueKey('contratado-relatar')));
    await _tocar(t, find.byKey(const ValueKey('relato-motivo')));
    await _tocar(t, find.text('Dano no local').last);
    await _tocar(t, find.byKey(const ValueKey('relato-solucao')));
    await _tocar(t, find.text('Reembolso parcial').last);
    await t.enterText(find.byKey(const ValueKey('relato-descricao')), 'Quebrou.');
    await _tocar(t, find.byKey(const ValueKey('relato-foto')));
    expect(find.text('1 foto anexada'), findsOneWidget);
    await _tocar(t, find.byKey(const ValueKey('relato-enviar')));
    expect(enviados.single['fotos'], ['foto.jpg']);
  });
}

Future<StatusPagamento> _statusDe(Map<String, Object> corpo) =>
    RepositorioPagamentoApi(_api((r) => (200, corpo))).status('p1');

class _RepoComFotos extends RepositorioPedidosApi {
  _RepoComFotos(super.api, this.enviados);

  final List<Map<String, dynamic>> enviados;

  @override
  Future<void> relatarPedidoContratado(
    String pedidoId, {
    required String motivo,
    required String descricao,
    List<String> fotos = const [],
    String? resultadoEsperado,
  }) async {
    enviados.add({'motivo': motivo, 'fotos': fotos});
  }
}
