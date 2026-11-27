// TERMOS-APP19 (8.2): o cliente aceita a proposta de devolução; os dois veem o acordo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/disputa_acordo/acordo.dart';
import 'package:trato/telas/disputa_acordo/secao_acordo.dart';
import 'package:trato/telas/disputa_profissional/responder_disputa_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/fontes.dart';

const _proposta = {
  'solucao': 'reembolso_parcial',
  'reembolso_centavos': 3050,
  'respondida_em': '2026-11-26T10:00:00Z',
};
const _acordo = {
  'solucao': 'reembolso_parcial',
  'reembolso_centavos': 3050,
  'liberado_centavos': 6950,
};

http.Response _json(Object corpo, [int codigo = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(corpo)), codigo,
    headers: const {'content-type': 'application/json'});

ClienteApi _api(Future<http.Response> Function(http.Request) responder) => ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient(responder));

Future<void> _montar(WidgetTester t, Widget tela, {Size tamanho = const Size(390, 844)}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

Widget _secao(ClienteApi api, {bool profissional = false, VoidCallback? aoMudar}) => Scaffold(
      body: SingleChildScrollView(
        child: SecaoAcordoDisputa(
          servico: ServicoAcordoDisputaApi(api),
          pedidoId: 'p1',
          profissional: profissional,
          aoMudar: aoMudar,
        ),
      ),
    );

final _botao = find.byKey(const Key('aceitar-proposta'));

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('cliente: vê a proposta, confirma e o corpo vai como veio', (t) async {
    final envios = <http.Request>[];
    var mudou = 0;
    await _montar(
      t,
      _secao(_api((r) async {
        if (r.method == 'POST') {
          envios.add(r);
          return _json({'estado': 'acordo', 'proposta': _proposta, 'acordo': _acordo});
        }
        return _json({'estado': 'em_analise', 'proposta': _proposta, 'acordo': null});
      }), aoMudar: () => mudou++),
      tamanho: const Size(320, 640),
    );
    expect(find.textContaining('30,50'), findsOneWidget);

    await t.tap(_botao);
    await t.pumpAndSettle();
    final texto = (t.widget<AlertDialog>(find.byType(AlertDialog)).content! as Text).data!;
    expect(texto, contains('30,50'));
    expect(texto, contains('o acordo encerra a disputa'));
    expect(texto, isNot(matches(RegExp('dia|prazo|estorno'))));
    await t.tap(find.text('Voltar'));
    await t.pumpAndSettle();
    expect(envios, isEmpty);

    await t.tap(_botao);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmar-acordo')));
    await t.pumpAndSettle();
    expect(envios.single.url.path, '/v1/pedidos/p1/disputa/aceitar-proposta');
    expect(jsonDecode(envios.single.body),
        {'solucao': 'reembolso_parcial', 'reembolso_centavos': 3050});
    expect(find.text('Disputa encerrada por acordo'), findsOneWidget);
    expect(find.textContaining('30,50'), findsOneWidget);
    expect(find.textContaining('69,50'), findsOneWidget);
    expect(_botao, findsNothing);
    expect(mudou, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('409: mostra o erro do servidor e recarrega a proposta nova', (t) async {
    var valor = 3050;
    var leituras = 0;
    await _montar(t, _secao(_api((r) async {
      if (r.method == 'POST') {
        valor = 4000;
        return _json({'detail': 'A proposta mudou.'}, 409);
      }
      leituras++;
      return _json({
        'estado': 'em_analise',
        'proposta': {..._proposta, 'reembolso_centavos': valor},
      });
    })));
    await t.tap(_botao);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmar-acordo')));
    await t.pumpAndSettle();
    expect(find.text('A proposta mudou.'), findsOneWidget);
    expect(find.textContaining('40,00'), findsOneWidget);
    expect(leituras, 2);
    expect(_botao, findsOneWidget);
  });

  testWidgets('profissional: vê a proposta sem botão e depois os valores do acordo', (t) async {
    await _montar(t, _secao(_api((_) async => _json({'estado': 'em_analise', 'proposta': _proposta})),
        profissional: true));
    expect(find.textContaining('30,50'), findsOneWidget);
    expect(_botao, findsNothing);

    await t.pumpWidget(const SizedBox());
    await _montar(t, _secao(_api((_) async => _json({'estado': 'acordo', 'acordo': _acordo})),
        profissional: true));
    expect(find.textContaining('30,50'), findsOneWidget);
    expect(find.textContaining('69,50'), findsOneWidget);
  });

  for (final (nome, resposta) in <(String, http.Response Function())>[
    ('servidor antigo (sem os campos)', () => _json({'estado': 'aberta'})),
    ('proposta que não é de devolução', () => _json({
          'estado': 'em_analise',
          'proposta': {'solucao': 'retrabalho', 'reembolso_centavos': null},
        })),
    ('solução desconhecida e tipos errados', () => _json({
          'estado': 7,
          'proposta': {'solucao': 'outra_coisa', 'reembolso_centavos': '10'},
          'acordo': 'x',
        })),
    ('disputa já decidida', () => _json({'estado': 'decidida', 'proposta': _proposta})),
    ('sem disputa (404)', () => _json({'detail': 'Sem disputa.'}, 404)),
    ('indisponível (503)', () => _json({'detail': 'Fora.'}, 503)),
  ]) {
    testWidgets('$nome: a seção não aparece', (t) async {
      await _montar(t, _secao(_api((_) async => resposta())));
      expect(find.byKey(const Key('secao-acordo-disputa')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('falha ao ler: aviso com "Tentar de novo"', (t) async {
    var falhar = true;
    await _montar(t, _secao(_api((_) async => falhar
        ? _json({'detail': 'x'}, 500)
        : _json({'estado': 'em_analise', 'proposta': _proposta}))));
    expect(find.text('Não deu para conferir a disputa agora.'), findsOneWidget);
    falhar = false;
    await t.tap(find.text('Tentar de novo'));
    await t.pumpAndSettle();
    expect(_botao, findsOneWidget);
  });

  testWidgets('tela de disputa do profissional mostra os valores do acordo', (t) async {
    final servico = ServicoDisputaProfissionalApi(_api((r) async => _json(
        r.url.path.endsWith('/disputa')
            ? {'estado': 'acordo', 'motivo': 'servico_incompleto', 'acordo': _acordo}
            : {'nome': 'Ana'})));
    await _montar(t, ResponderDisputaTela(servico: servico, disputaId: 'ab12cd34'));
    expect(find.text('Encerrada por acordo'), findsOneWidget);
    expect(find.textContaining('30,50'), findsOneWidget);
    expect(find.textContaining('69,50'), findsOneWidget);
    expect(find.text('Enviar resposta'), findsNothing);
  });
}
