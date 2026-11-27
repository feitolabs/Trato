// APP-LGPD1410: pedidos do titular e revisão de decisão automatizada (Termos 14.9 e 14.10).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/lgpd/central_privacidade_tela.dart';
import 'package:trato/telas/lgpd/modelos.dart';
import 'package:trato/telas/lgpd/pedidos_lgpd_tela.dart';

import 'apoio/exemplos/telas/lgpd/servico_fake.dart';
import 'apoio/fontes.dart';

const _pedido = {
  'id': 'p1',
  'protocolo': 'LGPD-0001',
  'tipo': 'revisao_decisao_automatizada',
  'decisao_automatizada': 'alerta_fraude',
  'descricao': 'Minha conta foi limitada.',
  'status': 'atendido_parcial',
  'aberto_em': '2026-11-20T12:00:00Z',
  'responder_ate': '2026-12-05T15:00:00Z',
  'resposta': 'Uma pessoa revisou o alerta.',
  'motivo_nao_atendido': 'Parte é segredo comercial.',
  'criterios_informados': 'Muitas tentativas em pouco tempo.',
  'respondido_em': '2026-11-25T15:00:00Z',
};

Map<String, Object> _pagina(List<Object> itens, [int? total]) =>
    {'itens': itens, 'total': total ?? itens.length, 'limite': 20, 'deslocamento': 0};

/// Servidor de mentira: [responder] devolve (status, corpo) para cada chamada.
ServicoPrivacidadeApi _api(
  (int, Object) Function(http.Request) responder, [
  List<http.Request>? pedidos,
]) =>
    ServicoPrivacidadeApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((r) async {
        pedidos?.add(r);
        final (status, corpo) = responder(r);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
            headers: const {'content-type': 'application/json'});
      }),
    ));

Future<void> _abrir(WidgetTester t, Widget tela, [Size tamanho = const Size(390, 1800)]) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, String chave) async {
  final alvo = find.byKey(ValueKey(chave));
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('central abre os pedidos e mostra protocolo, situação, prazo e resposta', (t) async {
    final chamadas = <http.Request>[];
    final servico = _api(
      (r) => r.url.path == '/v1/me/lgpd/pedidos'
          ? (200, _pagina([_pedido]))
          : (200, <String, Object>{}),
      chamadas,
    );
    await _abrir(t, CentralPrivacidadeTela(servico: servico));
    await _tocar(t, 'botao-pedidos-lgpd');

    for (final texto in [
      'Atendido em parte',
      'Revisão por uma pessoa de decisão automática',
      'Decisão: Alerta de fraude',
      'Prazo para resposta: até 05/12/2026',
      'Uma pessoa revisou o alerta.',
      'Parte é segredo comercial.',
      'Muitas tentativas em pouco tempo.',
    ]) {
      expect(find.text(texto), findsOneWidget, reason: texto);
    }
    expect(find.text('Protocolo: LGPD-0001', findRichText: true), findsOneWidget);
    expect(find.text('Ver mais'), findsNothing);
    expect(chamadas.last.url.queryParameters, {'limite': '20', 'deslocamento': '0'});
  });

  testWidgets('servidor sem a lista de pedidos: central sem o botão', (t) async {
    await _abrir(t, CentralPrivacidadeTela(servico: ServicoPrivacidadeFake()));
    expect(find.byKey(const ValueKey('botao-pedidos-lgpd')), findsNothing);
  });

  for (final status in [404, 503]) {
    testWidgets('servidor antigo ($status): aviso claro, sem quebrar', (t) async {
      await _abrir(t, PedidosLgpdTela(servico: _api((_) => (status, {'detail': 'x'}))));
      expect(find.text('Ainda não disponível'), findsOneWidget);
      expect(find.byKey(const ValueKey('botao-novo-pedido-lgpd')), findsNothing);
    });
  }

  testWidgets('erro ao carregar permite tentar de novo; depois, vazio', (t) async {
    var falhar = true;
    await _abrir(
      t,
      PedidosLgpdTela(
        servico: _api((_) => falhar ? (500, {'detail': 'x'}) : (200, _pagina([]))),
      ),
    );
    expect(find.text('Tentar de novo'), findsOneWidget);
    falhar = false;
    await t.tap(find.text('Tentar de novo'));
    await t.pumpAndSettle();
    expect(find.text('Você ainda não fez nenhum pedido.'), findsOneWidget);
  });

  testWidgets('campos ausentes usam texto padrão', (t) async {
    await _abrir(
      t,
      PedidosLgpdTela(
        servico: _api((_) => (
              200,
              {
                'itens': [<String, Object>{}]
              }
            )),
      ),
    );
    expect(find.text('Pedido sobre seus dados'), findsOneWidget);
    expect(find.text('Situação não informada'), findsOneWidget);
    expect(find.text('Prazo para resposta não informado.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Ver mais busca a próxima página', (t) async {
    await _abrir(
      t,
      PedidosLgpdTela(
        servico: _api((r) {
          final n = r.url.queryParameters['deslocamento'] == '0' ? 1 : 2;
          return (
            200,
            _pagina([
              {'id': 'p$n', 'protocolo': 'LGPD-$n'}
            ], 2)
          );
        }),
      ),
    );
    await t.tap(find.text('Ver mais'));
    await t.pumpAndSettle();
    expect(find.text('Protocolo: LGPD-2', findRichText: true), findsOneWidget);
    expect(find.text('Ver mais'), findsNothing);
  });

  testWidgets('revisão exige a decisão, envia o contrato e atualiza a lista', (t) async {
    final chamadas = <http.Request>[];
    var criado = false;
    final servico = _api((r) {
      if (r.method == 'POST') {
        criado = true;
        return (201, _pedido);
      }
      return (200, _pagina(criado ? [_pedido] : []));
    }, chamadas);
    await _abrir(t, PedidosLgpdTela(servico: servico), const Size(320, 640));
    await _tocar(t, 'botao-novo-pedido-lgpd');

    await _tocar(t, 'botao-enviar-pedido-lgpd');
    expect(find.text('Escolha o que você quer pedir.'), findsOneWidget);
    await _tocar(t, 'tipo-revisao_decisao_automatizada');
    await _tocar(t, 'botao-enviar-pedido-lgpd');
    expect(find.text('Escolha qual decisão você quer que uma pessoa revise.'), findsOneWidget);
    expect(chamadas.where((r) => r.method == 'POST'), isEmpty);

    await _tocar(t, 'decisao-alerta_fraude');
    await t.enterText(find.byType(TextField), '  Minha conta foi limitada.  ');
    await _tocar(t, 'botao-enviar-pedido-lgpd');

    expect(jsonDecode(chamadas.singleWhere((r) => r.method == 'POST').body), {
      'tipo': tipoRevisaoAutomatizada,
      'descricao': 'Minha conta foi limitada.',
      'decisao_automatizada': 'alerta_fraude',
    });
    expect(find.text('Pedido registrado. Protocolo LGPD-0001.'), findsOneWidget);
    expect(find.text('Atendido em parte'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('pedido igual em aberto (200) avisa que já existia', (t) async {
    final servico = _api((r) => r.method == 'POST' ? (200, _pedido) : (200, _pagina([_pedido])));
    await _abrir(t, PedidosLgpdTela(servico: servico));
    await _tocar(t, 'botao-novo-pedido-lgpd');
    await _tocar(t, 'tipo-acesso');
    await _tocar(t, 'botao-enviar-pedido-lgpd');
    expect(
      find.text('Você já tinha um pedido igual em aberto. Protocolo LGPD-0001.'),
      findsOneWidget,
    );
  });

  for (final (status, detalhe, esperado) in [
    (422, 'Descrição recusada pelo servidor.', 'Descrição recusada pelo servidor.'),
    (503, 'tabela', 'Os pedidos pelo app ainda não estão disponíveis.'),
  ]) {
    testWidgets('erro $status no envio aparece junto do botão e mantém o texto', (t) async {
      final servico = _api(
        (r) => r.method == 'POST' ? (status, {'detail': detalhe}) : (200, _pagina([])),
      );
      await _abrir(t, PedidosLgpdTela(servico: servico));
      await _tocar(t, 'botao-novo-pedido-lgpd');
      await _tocar(t, 'tipo-correcao');
      await t.enterText(find.byType(TextField), 'Meu nome está errado');
      await _tocar(t, 'botao-enviar-pedido-lgpd');

      expect(find.textContaining(esperado), findsOneWidget);
      expect(find.text('Meu nome está errado'), findsOneWidget);
      expect(find.byKey(const ValueKey('botao-enviar-pedido-lgpd')), findsOneWidget);
    });
  }
}
