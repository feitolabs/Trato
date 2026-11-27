// APP-95: "pessoa diferente" usa a rota que pode cancelar o pedido (cláusula 9.5).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/atendimento/atendimento_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _rota = '/v1/pedidos/p1/seguranca/pessoa-diferente';

class _Servidor {
  (int, Object) relato = (
    200,
    {
      'protocolo': 'SEG-1',
      'cancelado': true,
      'estado_pedido': 'cancelado',
      'mensagem': 'Pedido cancelado: o valor pago volta por inteiro.',
    }
  );
  var semRede = false;
  final chamadas = <http.Request>[];

  Iterable<http.Request> get posts => chamadas.where((r) => r.method == 'POST');
  Iterable<String> get envios => posts.map((r) => r.url.path);

  late final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      chamadas.add(r);
      if (semRede && r.url.path == _rota) throw http.ClientException('sem rede');
      const pedido = {'id': 'p1', 'estado': 'agendado', 'estado_nome': 'Agendado'};
      final (int, Object) resposta = switch (r.url.path) {
        _rota => relato,
        '/v1/sac/chamados' => (
            201,
            {'id': 'c1', 'protocolo': 'SAC-1', 'assunto': 'Segurança', 'status': 'aberto'}
          ),
        '/v1/pedidos' => (200, [pedido]),
        '/v1/pedidos/p1' => (200, pedido),
        _ => (404, {'detail': 'Not Found'}),
      };
      return http.Response.bytes(utf8.encode(jsonEncode(resposta.$2)), resposta.$1,
          headers: const {'content-type': 'application/json'});
    }),
  );

  late final sac = ServicoSacApi(api);
}

void _janela(WidgetTester t) {
  t.view.physicalSize = const Size(320, 2400);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _tocar(WidgetTester t, Key chave) async {
  await t.ensureVisible(find.byKey(chave));
  await t.pumpAndSettle();
  await t.tap(find.byKey(chave));
  await t.pumpAndSettle();
}

Future<List<int>> _formulario(WidgetTester t, _Servidor s, {bool cliente = true}) async {
  final avisos = <int>[];
  _janela(t);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: NovoChamadoTela(
      servico: s.sac,
      pedidoInicial: 'p1',
      seguranca: true,
      orientarChegada: cliente,
      pessoaDiferente: cliente ? s.sac : null,
      aoRelatarPessoaDiferente: () => avisos.add(1),
    ),
  ));
  await t.pumpAndSettle();
  await _tocar(t, const ValueKey('caso-seguranca-3'));
  return avisos;
}

const _relatar = Key('relatar-pessoa-diferente');
const _confirmar = Key('confirmar-pessoa-diferente');

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('confirma antes, usa a rota e mostra mensagem e protocolo', (t) async {
    final s = _Servidor();
    final avisos = await _formulario(t, s);
    expect(find.textContaining('190 (Polícia)'), findsOneWidget);
    expect(find.text(orientacaoPessoaDiferente), findsOneWidget);
    expect(find.byKey(const Key('enviar-chamado')), findsNothing);
    await _tocar(t, _relatar);
    expect(find.textContaining('cancelado na hora, com reembolso integral'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Voltar'));
    await t.pumpAndSettle();
    expect(s.envios, isEmpty);
    await _tocar(t, _relatar);
    await _tocar(t, _confirmar);
    expect(s.envios, [_rota]);
    expect(jsonDecode(s.posts.single.body), isEmpty);
    expect(find.text('Pedido cancelado'), findsOneWidget);
    expect(find.text('Pedido cancelado: o valor pago volta por inteiro.'), findsOneWidget);
    expect(find.text('Protocolo SEG-1'), findsOneWidget);
    expect(avisos, hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('cancelado=false não promete cancelamento', (t) async {
    final s = _Servidor()
      ..relato = (
        200,
        {'protocolo': 'SEG-2', 'cancelado': false, 'mensagem': 'A equipe vai analisar o caso.'}
      );
    await _formulario(t, s);
    await _tocar(t, _relatar);
    await _tocar(t, _confirmar);
    expect(find.text('Relato registrado'), findsOneWidget);
    expect(find.text('Protocolo SEG-2'), findsOneWidget);
    expect(find.textContaining('cancelado'), findsNothing);
  });

  const proprio = 'Não foi possível enviar este relato pelo app agora.';
  const semContrato = 'Este pedido não tem serviço contratado em aberto.';
  for (final (nome, status, detalhe, aviso) in [
    ('503', 503, 'x', proprio),
    ('404 antigo', 404, 'Not Found', proprio),
    ('409', 409, semContrato, semContrato),
    ('sem rede', 0, '', ''),
  ]) {
    testWidgets('rota falhou ($nome): oferece o chamado, sem prometer', (t) async {
      final s = _Servidor()
        ..relato = (status, {'detail': detalhe})
        ..semRede = status == 0;
      await _formulario(t, s);
      await _tocar(t, _relatar);
      await _tocar(t, _confirmar);
      if (aviso.isNotEmpty) expect(find.text(aviso), findsOneWidget);
      expect(find.byKey(const Key('alternativa-chamado')), findsOneWidget);
      expect(find.textContaining('reembolso'), findsNothing);
      await t.enterText(find.byKey(const Key('texto-chamado')), 'Não é a pessoa da foto.');
      await _tocar(t, const Key('enviar-chamado'));
      expect(s.envios.last, '/v1/sac/chamados');
      expect(find.textContaining('SAC-1'), findsWidgets);
    });
  }

  testWidgets('profissional continua no chamado comum', (t) async {
    await _formulario(t, _Servidor(), cliente: false);
    expect(find.byKey(_relatar), findsNothing);
    expect(find.byKey(const Key('enviar-chamado')), findsOneWidget);
  });

  testWidgets('conta bloqueada chega ao relato pelo pedido', (t) async {
    final antes = RotasTrato.repos;
    addTearDown(() {
      RotasTrato.repos = antes;
      RotasTrato.esquecerBloqueio();
    });
    final s = _Servidor();
    RotasTrato.repos = repositoriosDemo(pedidos: RepositorioPedidosApi(s.api), sac: s.sac);
    _janela(t);
    final nav = GlobalKey<NavigatorState>();
    await t
        .pumpWidget(MaterialApp(theme: TemaTrato.claro, navigatorKey: nav, home: const Scaffold()));
    RotasTrato.contaFoiBloqueada(() => nav.currentState, 'Conta bloqueada.');
    await t.pumpAndSettle();
    RotasTrato.abrirPedidoContratado(nav.currentState!.overlay!.context, 'p1');
    await t.pumpAndSettle();
    await _tocar(t, const ValueKey('contratado-pessoa-diferente'));
    expect(find.text(orientacaoPessoaDiferente), findsOneWidget);
    await _tocar(t, _relatar);
    await _tocar(t, _confirmar);
    expect(s.envios, [_rota]);
    expect(find.text('Protocolo SEG-1'), findsOneWidget);
  });

  test('o aviso pagamento.cancelado_seguranca abre o pedido e não quebra', () {
    expect(
      resultadoDoPush(
          {'evento': 'pagamento.cancelado_seguranca', 'tela': 'pedido', 'pedido_id': 'ped-1'}),
      const ResultadoLink.valido(DestinoApp.pedido, 'ped-1'),
    );
    for (final dados in <Map<String, dynamic>>[
      {'evento': 'pagamento.cancelado_seguranca'},
      {'evento': 'pagamento.cancelado_seguranca', 'tela': 'pedido'},
    ]) {
      expect(() => resultadoDoPush(dados), returnsNormally);
    }
  });
}
