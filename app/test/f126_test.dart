// APP-2AC: conta bloqueada confirma a conclusão ou relata problema nos pedidos contratados.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/conta_bloqueada/pedidos_contratados.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

/// As únicas chamadas que o servidor abre a quem está bloqueado.
final _abertas = RegExp(r'^(GET /v1/pedidos(/p1(/disputa|/cobrancas)?)?|'
    r'POST /v1/pedidos/p1/(acoes/confirmar_conclusao|disputa))$');

Map<String, Object?> _pedido({
  String estado = 'em_confirmacao',
  List<String> acoes = const ['confirmar_conclusao', 'abrir_disputa'],
}) =>
    {
      'id': 'p1',
      'estado': estado,
      'estado_nome': 'Situação $estado',
      'titulo': 'Troca de tomadas',
      'profissional_nome': 'Carlos M.',
      'codigo_inicio': '1111',
      'codigo_conclusao': '2222',
      'acoes_permitidas': acoes,
    };

class _Servidor {
  var pedido = _pedido();
  (int, Object)? lista;
  (int, Object)? confirmar;
  (int, Object)? relatar;
  (int, Object) relato = (
    200,
    {
      'motivo': 'dano',
      'descricao': 'Quebrou o piso.',
      'aberta_em': '2026-11-20T12:00:00Z',
      'resposta_ate': '2026-11-22T12:00:00Z',
      'decisao_ate': '2026-11-27T12:00:00Z',
    }
  );
  final chamadas = <http.Request>[];

  List<String> get rotas => [for (final r in chamadas) '${r.method} ${r.url.path}'];

  late final repo = RepositorioPedidosApi(ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((r) async {
      chamadas.add(r);
      final (status, corpo) = switch ('${r.method} ${r.url.path}') {
        'GET /v1/pedidos' => lista ?? (200, [pedido]),
        'GET /v1/pedidos/p1' => (200, pedido),
        'GET /v1/pedidos/p1/disputa' => relato,
        'POST /v1/pedidos/p1/acoes/confirmar_conclusao' => confirmar ?? (200, pedido),
        'POST /v1/pedidos/p1/disputa' => relatar ?? (201, <String, Object>{}),
        _ => (403, {'detail': 'Bloqueada.', 'codigo': 'conta_bloqueada'}),
      };
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json'});
    }),
  ));
}

Future<GlobalKey<NavigatorState>> _bloquear(WidgetTester t, _Servidor s,
    {Size tamanho = const Size(390, 1400), double fonte = 1}) async {
  final antes = RotasTrato.repos;
  addTearDown(() {
    RotasTrato.repos = antes;
    RotasTrato.esquecerBloqueio();
    LinkPendente.limpar();
  });
  RotasTrato.repos = repositoriosDemo(pedidos: s.repo);
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final nav = GlobalKey<NavigatorState>();
  await t
      .pumpWidget(MaterialApp(theme: TemaTrato.claro, navigatorKey: nav, home: const Scaffold()));
  RotasTrato.contaFoiBloqueada(() => nav.currentState, 'Sua conta está bloqueada.');
  await t.pumpAndSettle();
  return nav;
}

Future<void> _tocar(WidgetTester t, Key chave) async {
  final alvo = find.byKey(chave);
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

Future<void> _abrirPedido(WidgetTester t) async {
  await _tocar(t, const Key('bloqueio-pedidos'));
  await _tocar(t, const ValueKey('contratado-p1'));
}

const _confirmar = ValueKey('contratado-confirmar');
const _relatar = ValueKey('contratado-relatar');

Future<void> _escolher(WidgetTester t, String chave, String opcao) async {
  await _tocar(t, ValueKey(chave));
  await t.tap(find.text(opcao).last);
  await t.pumpAndSettle();
}

Future<void> _preencherRelato(WidgetTester t) async {
  await _tocar(t, _relatar);
  await _escolher(t, 'relato-motivo', 'Dano no local');
  await _escolher(t, 'relato-solucao', 'Reembolso parcial');
  await t.enterText(find.byKey(const ValueKey('relato-descricao')), 'Quebrou o piso.');
  await t.pump();
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('chega ao pedido e confirma sem corpo, só pelas rotas abertas', (t) async {
    final s = _Servidor();
    await _bloquear(t, s);
    await _abrirPedido(t);
    expect(find.text('Troca de tomadas'), findsOneWidget);
    expect(find.textContaining('1111'), findsNothing); // fase de confirmação
    await _tocar(t, _confirmar);
    expect(s.chamadas.where((r) => r.method == 'POST'), isEmpty);
    s.pedido = _pedido(estado: 'concluido', acoes: const []);
    await _tocar(t, const ValueKey('contratado-confirmar-sim'));
    final envio = s.chamadas.singleWhere((r) => r.method == 'POST');
    expect(envio.url.path, '/v1/pedidos/p1/acoes/confirmar_conclusao');
    expect(envio.body, isEmpty);
    expect(find.byKey(_confirmar), findsNothing);
    expect(find.byKey(_relatar), findsNothing);
    expect(find.text('Não há ação disponível neste pedido agora.'), findsOneWidget);
    expect(s.rotas.where((r) => !_abertas.hasMatch(r)), isEmpty);
    expect(s.chamadas.where((r) => r.url.path == '/v1/pedidos').map((r) => r.url.query).toSet(),
        {'como=cliente'});
  });

  testWidgets('botões seguem as ações do servidor; códigos aparecem na fase certa', (t) async {
    final s = _Servidor()..pedido = _pedido(estado: 'em_andamento', acoes: ['abrir_disputa']);
    await _bloquear(t, s);
    await _abrirPedido(t);
    expect(find.byKey(_confirmar), findsNothing);
    expect(find.byKey(_relatar), findsOneWidget);
    expect(find.text('Código de conclusão: 2222'), findsOneWidget);
    expect(find.textContaining('1111'), findsNothing);
  });

  testWidgets('relato sem foto: oferece tirar fotos e envia só o texto', (t) async {
    final s = _Servidor();
    await _bloquear(t, s);
    await _abrirPedido(t);
    await _tocar(t, _relatar);
    expect(find.byKey(const ValueKey('relato-foto')), findsOneWidget);
    await _tocar(t, const ValueKey('relato-enviar'));
    expect(find.text('Escolha o que aconteceu.'), findsOneWidget);
    expect(find.text('Conte o problema.'), findsOneWidget);
    expect(s.chamadas.where((r) => r.method == 'POST'), isEmpty);
    await _escolher(t, 'relato-motivo', 'Dano no local');
    await _escolher(t, 'relato-solucao', 'Reembolso parcial');
    await t.enterText(find.byKey(const ValueKey('relato-descricao')), 'Quebrou o piso.');
    s.pedido = _pedido(estado: 'em_disputa', acoes: const []);
    await _tocar(t, const ValueKey('relato-enviar'));
    final envio = s.chamadas.singleWhere((r) => r.method == 'POST');
    expect(jsonDecode(envio.body), {
      'motivo': 'dano',
      'descricao': 'Quebrou o piso.\n\nSolução que o cliente prefere: Reembolso parcial',
      'resultado_esperado': 'reembolso_parcial',
    });
    expect(find.byKey(const ValueKey('contratado-relato')), findsOneWidget);
    expect(s.rotas.where((r) => !_abertas.hasMatch(r)), isEmpty);
  });

  testWidgets('409 no relato: motivo junto do botão, texto mantido (320 px, 1,3x)', (t) async {
    final s = _Servidor()..relatar = (409, {'detail': 'Este pedido já tem relato.'});
    await _bloquear(t, s, tamanho: const Size(320, 640), fonte: 1.3);
    await _abrirPedido(t);
    await _preencherRelato(t);
    await _tocar(t, const ValueKey('relato-enviar'));
    expect(find.text('Este pedido já tem relato.'), findsOneWidget);
    expect(find.text('Quebrou o piso.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('erro ao confirmar aparece junto do botão', (t) async {
    final s = _Servidor()..confirmar = (409, {'detail': 'O pedido mudou.'});
    await _bloquear(t, s, tamanho: const Size(320, 640), fonte: 1.3);
    await _abrirPedido(t);
    await _tocar(t, _confirmar);
    await _tocar(t, const ValueKey('contratado-confirmar-sim'));
    expect(find.text('O pedido mudou.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('pedido sem relato gravado (404) não quebra', (t) async {
    final s = _Servidor()
      ..pedido = _pedido(estado: 'retrabalho', acoes: const [])
      ..relato = (404, {'detail': 'Este pedido não tem disputa.'});
    await _bloquear(t, s);
    await _abrirPedido(t);
    expect(find.byKey(const ValueKey('contratado-relato')), findsNothing);
    expect(find.text('Não foi possível abrir o relato agora.'), findsNothing);
  });

  for (final (nome, resposta) in [
    ('403', (403, {'detail': 'Bloqueada.', 'codigo': 'conta_bloqueada'})),
    ('vazia', (200, <Object>[])),
  ]) {
    testWidgets('lista $nome: a entrada não aparece', (t) async {
      final s = _Servidor()..lista = resposta;
      await _bloquear(t, s);
      expect(find.byKey(const Key('bloqueio-falar')), findsOneWidget);
      expect(find.byKey(const Key('bloqueio-pedidos')), findsNothing);
    });
  }

  testWidgets('falha passageira: a entrada fica e a lista deixa tentar de novo', (t) async {
    final s = _Servidor()..lista = (500, {'detail': 'x'});
    await _bloquear(t, s);
    await _tocar(t, const Key('bloqueio-pedidos'));
    expect(find.byType(PedidosContratadosTela), findsOneWidget);
    expect(find.textContaining('Tentar'), findsOneWidget);
  });

  testWidgets('aviso de pedido tocado abre o pedido reduzido', (t) async {
    final s = _Servidor();
    final navegadorAntes = DeepLinks.navegador;
    final authAntes = ServicoAuthPadrao.atual;
    addTearDown(() {
      DeepLinks.navegador = navegadorAntes;
      ServicoAuthPadrao.atual = authAntes;
    });
    ServicoAuthPadrao.atual = ServicoAuthFake();
    await entrarNaContaDeTeste(ServicoAuthPadrao.atual);
    final nav = await _bloquear(t, s);
    DeepLinks.navegador = () => nav.currentState;
    LinkPendente.guardar(const ResultadoLink.valido(DestinoApp.pedido, 'p1'));
    DeepLinks.processar();
    await t.pumpAndSettle();
    expect(find.byType(PedidoContratadoTela), findsOneWidget);
    expect(s.rotas.where((r) => !_abertas.hasMatch(r)), isEmpty);
  });
}
