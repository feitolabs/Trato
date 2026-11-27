// APP-127-REVISAO: quem foi avaliado pede a revisão da avaliação (cláusula 12.7).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/perfil_publico/avaliacoes_recebidas_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/telas/perfil_publico/revisao_avaliacao.dart';

import 'apoio/fontes.dart';

/// Serviço real das rotas de revisão; só a lista de avaliações é de mentira.
class _Servico extends ServicoPerfilPublicoApi {
  _Servico(super.api);

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => const [
        Avaliacao(
          id: 'av-1',
          cliente: 'Maria Souza',
          servico: 'Elétrica',
          nota: 2,
          comentario: 'Chegou atrasado.',
          detalhes: '',
        ),
      ];
}

class _Servidor {
  (int, Object) lista = (200, _pagina(const []));
  (int, Object) envio = (201, _pedido('aberta'));
  final chamadas = <http.Request>[];

  Iterable<http.Request> get envios => chamadas.where((r) => r.method == 'POST');

  late final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      chamadas.add(r);
      final (status, corpo) = r.method == 'POST' ? envio : lista;
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  );
}

Map<String, Object?> _pedido(String status, {String? resposta, String tipo = 'revisao'}) => {
      'id': 'rev-1',
      'protocolo': 'REV-2026-000001',
      'avaliacao_id': 'av-1',
      'tipo': tipo,
      'status': status,
      'aberta_em': '2026-11-20T12:00:00Z',
      'responder_ate': '2026-11-27T12:00:00Z',
      'resposta': resposta,
    };

Map<String, Object> _pagina(List<Object> itens, [int? total]) =>
    {'itens': itens, 'total': total ?? itens.length, 'limite': 100, 'deslocamento': 0};

Future<void> _abrir(WidgetTester t, _Servidor s,
    {Size tamanho = const Size(390, 1200), double fonte = 1}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: AvaliacoesRecebidasTela(servico: _Servico(s.api)),
  ));
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, String chave) async {
  final alvo = find.byKey(ValueKey(chave));
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

const _campo = ValueKey('campo-revisao-avaliacao');
const _botao = ValueKey('pedir-revisao-av-1');

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('pede a revisão: valida o mínimo, envia só os campos da API e mostra o estado',
      (t) async {
    final s = _Servidor();
    await _abrir(t, s);
    await _tocar(t, 'pedir-revisao-av-1');
    await t.enterText(find.byKey(_campo), '  curto   ');
    await _tocar(t, 'botao-enviar-revisao');
    expect(find.text('Explique o motivo com pelo menos 10 caracteres.'), findsOneWidget);
    expect(s.envios, isEmpty);
    expect(t.widget<TextField>(find.byKey(_campo)).maxLength, 2000);

    await t.enterText(find.byKey(_campo), 'O comentário é de outro serviço.');
    s.lista = (200, _pagina([_pedido('aberta')]));
    await _tocar(t, 'botao-enviar-revisao');
    expect(s.envios.single.url.path, '/v1/avaliacoes/av-1/revisoes');
    expect(jsonDecode(s.envios.single.body),
        {'justificativa': 'O comentário é de outro serviço.', 'tipo': 'revisao'});
    expect(find.text('Pedido de revisão: Enviado'), findsOneWidget);
    expect(find.text('Protocolo REV-2026-000001'), findsOneWidget);
    expect(find.textContaining('Resposta prevista até 27/11/2026'), findsOneWidget);
    expect(find.byKey(_botao), findsNothing);
  });

  for (final (status, rotulo, temBotao) in [
    ('em_analise', 'Em análise', false),
    ('aceita', 'Aceito', true),
    ('recusada', 'Recusado', true),
  ]) {
    testWidgets('situação $status', (t) async {
      final s = _Servidor()
        ..lista = (200, _pagina([_pedido(status, resposta: temBotao ? 'Analisado.' : null)]));
      await _abrir(t, s);
      expect(find.text('Pedido de revisão: $rotulo'), findsOneWidget);
      expect(find.byKey(_botao), temBotao ? findsOneWidget : findsNothing);
      expect(find.text('Resposta do Trato: Analisado.'), temBotao ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('contestação de ocultação não aparece como pedido de revisão', (t) async {
    final s = _Servidor()
      ..lista = (200, _pagina([_pedido('aberta', tipo: 'contestacao_ocultacao')]));
    await _abrir(t, s);
    expect(find.textContaining('Pedido de revisão:'), findsNothing);
    expect(find.byKey(_botao), findsOneWidget);
  });

  for (final status in [404, 503]) {
    testWidgets('consulta $status: a tela segue normal e sem a função', (t) async {
      final s = _Servidor()..lista = (status, {'detail': 'Not Found'});
      await _abrir(t, s);
      expect(find.text('Chegou atrasado.'), findsOneWidget);
      expect(find.byKey(_botao), findsNothing);
      expect(find.byKey(const ValueKey('revisoes-falha')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('resposta fora do formato: sem a função', (t) async {
    final s = _Servidor()..lista = (200, <String, Object>{});
    await _abrir(t, s);
    expect(find.byKey(_botao), findsNothing);
    expect(find.text('Chegou atrasado.'), findsOneWidget);
  });

  testWidgets('falha na consulta: avisa, mantém as avaliações e tenta de novo', (t) async {
    final s = _Servidor()..lista = (500, {'detail': 'x'});
    await _abrir(t, s);
    expect(find.text('Chegou atrasado.'), findsOneWidget);
    expect(find.byKey(const ValueKey('revisoes-falha')), findsOneWidget);
    expect(find.byKey(_botao), findsNothing);
    s.lista = (200, _pagina(const []));
    await t.tap(find.text('Tentar de novo'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('revisoes-falha')), findsNothing);
    expect(find.byKey(_botao), findsOneWidget);
  });

  for (final (status, detalhe, aviso) in [
    (
      403,
      'Só quem foi avaliado pode pedir revisão da avaliação.',
      'Só quem foi avaliado pode pedir revisão da avaliação.'
    ),
    (404, 'Avaliação não encontrada.', 'Avaliação não encontrada.'),
    (409, 'Não foi possível registrar o pedido de revisão.', null),
    (503, 'x', 'indisponível agora'),
    (404, 'Not Found', 'indisponível agora'),
  ]) {
    testWidgets('envio $status ($detalhe): erro junto do botão, sem apagar o texto', (t) async {
      final s = _Servidor()..envio = (status, {'detail': detalhe});
      await _abrir(t, s, tamanho: const Size(320, 640), fonte: 1.3);
      await _tocar(t, 'pedir-revisao-av-1');
      await t.enterText(find.byKey(_campo), 'Motivo com mais de dez letras.');
      await _tocar(t, 'botao-enviar-revisao');
      expect(find.textContaining(aviso ?? detalhe), findsOneWidget);
      expect(find.text('Motivo com mais de dez letras.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  test('lê todas as páginas de pedidos', () async {
    final s = _Servidor()..lista = (200, _pagina([_pedido('aberta')], 2));
    final pedidos = await ServicoPerfilPublicoApi(s.api).pedidosDeRevisao();
    expect(pedidos, hasLength(2));
    expect(s.chamadas.map((r) => r.url.queryParameters['deslocamento']), ['0', '1']);
  });

  test('o pedido em andamento vale mais que o já decidido', () {
    final pedidos = [
      PedidoRevisaoAvaliacao.deJson(_pedido('recusada'))!,
      PedidoRevisaoAvaliacao.deJson(_pedido('em_analise'))!,
    ];
    expect(pedidoDaAvaliacao(pedidos, 'av-1')!.status, 'em_analise');
    expect(pedidoDaAvaliacao(pedidos, 'outra'), isNull);
  });
}
