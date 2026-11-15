// Perguntas que o admin configura por categoria aparecem no Novo pedido (v0.1.25).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/endereco_pedido.dart';
import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';

const _tipo = PerguntaPedido(
  id: 'q-tipo',
  texto: 'Qual é o tipo de imóvel?',
  tipo: 'escolha_unica',
  opcoes: ['Apartamento', 'Casa', 'Outro'],
  obrigatoria: true,
);
const _comodos =
    PerguntaPedido(id: 'q-comodos', texto: 'Quantos cômodos?', tipo: 'numero', obrigatoria: true);
const _pets = PerguntaPedido(id: 'q-pets', texto: 'Há animais?', tipo: 'sim_nao');
const _extras = PerguntaPedido(
  id: 'q-extras',
  texto: 'O que mais?',
  tipo: 'multipla',
  opcoes: ['Janelas', 'Forno'],
);
const _obs = PerguntaPedido(id: 'q-obs', texto: 'Algo mais?', tipo: 'texto');

Future<void> _abrir(WidgetTester t, Widget tela) async {
  t.view.physicalSize = const Size(390, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.tap(alvo);
  await t.pumpAndSettle();
}

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  final formulario = formularioExemplo.comPerguntas(const [_tipo, _comodos, _pets, _extras, _obs]);

  testWidgets('as perguntas da categoria substituem as genéricas', (t) async {
    await _abrir(t, NovoPedidoTela(formulario: formulario));
    expect(find.text('Qual é o tipo de imóvel?'), findsOneWidget);
    expect(find.text('Há animais? (opcional)'), findsOneWidget);
    expect(find.text('O que precisa ser feito?'), findsNothing);
    expect(find.text(formularioExemplo.perguntaQuantidade), findsNothing);
  });

  testWidgets('obrigatória sem resposta mostra erro e não envia', (t) async {
    RascunhoPedido? enviado;
    await _abrir(t, NovoPedidoTela(formulario: formulario, aoEnviar: (r) => enviado = r));
    await preencherEnderecoDoPedido(t);
    // o 1º campo de texto é a pergunta "Algo mais?"; o 2º é a descrição
    await t.enterText(find.byType(TextField).at(1), 'Limpeza completa do apartamento.');
    await _tocar(t, find.text('Próximo'));
    expect(enviado, isNull);
    expect(find.text('Responda esta pergunta.'), findsOneWidget); // só o tipo de imóvel
  });

  testWidgets('responde e envia as respostas com o id de cada pergunta', (t) async {
    RascunhoPedido? enviado;
    await _abrir(t, NovoPedidoTela(formulario: formulario, aoEnviar: (r) => enviado = r));
    await preencherEnderecoDoPedido(t);
    // o 1º campo de texto é a pergunta "Algo mais?"; o 2º é a descrição
    await t.enterText(find.byType(TextField).at(1), 'Limpeza completa do apartamento.');
    await _tocar(t, find.text('Casa'));
    await _tocar(t, find.text('Sim'));
    await _tocar(t, find.text('Forno'));
    await _tocar(t, find.text('Janelas'));
    await _tocar(t, find.byTooltip('Aumentar').first);
    await _tocar(t, find.text('Próximo'));
    expect(enviado, isNotNull);
    expect(enviado!.respostas, {
      'q-tipo': 'Casa',
      'q-comodos': 2,
      'q-pets': true,
      'q-extras': ['Janelas', 'Forno'], // na ordem das opções
    });
    expect(enviado!.servicos, [formularioExemplo.categoria]);
  });

  test('o catálogo traz as perguntas e o pedido envia as respostas', () async {
    final chamadas = <http.Request>[];
    final api = ClienteApi(
      urlBase: 'https://api.teste/',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((r) async {
        chamadas.add(r);
        switch (r.url.path) {
          case '/v1/catalogo/categorias':
            return _json([
              {'id': 'c1', 'nome': 'Limpeza residencial', 'slug': 'limpeza'},
            ]);
          case '/v1/catalogo/cidades':
            return _json([
              {'id': 'cid-1', 'nome': 'Divinopolis', 'uf': 'MG'},
            ]);
          case '/v1/catalogo/categorias/c1/perguntas':
            return _json([
              {
                'id': 'q-tipo',
                'texto': 'Qual é o tipo de imóvel?',
                'tipo': 'escolha_unica',
                'opcoes': ['Apartamento', 'Casa'],
                'obrigatoria': true,
              },
            ]);
        }
        return _json({
          'id': 'ab12cd34',
          'estado': 'aberto',
          'estado_nome': 'aberto',
          'cliente_id': 'c',
          'profissional_id': null,
          'aberto_em': '2026-11-15T12:00:00Z',
          'concluido_em': null,
          'acoes_permitidas': <String>[],
          'codigo_inicio': null,
          'codigo_conclusao': null,
        }, 201);
      }),
    );
    final f = await RepositorioCatalogoApi(api).formulario('c1');
    expect(f.perguntas.single.opcoes, ['Apartamento', 'Casa']);
    expect(f.perguntas.single.obrigatoria, isTrue);

    await RepositorioPedidosApi(api).criar(
      const RascunhoPedido(
        servicos: ['Limpeza residencial'],
        quantidade: 1,
        voltagem: '',
        descricao: 'Limpeza.',
        prazo: 'Sem pressa',
        faixa: FaixaPreco(minimoCentavos: 10000, maximoCentavos: 20000),
        categoriaId: 'c1',
        cidadeId: 'cid-1',
        modalidade: Modalidade.remoto,
        respostas: {'q-tipo': 'Casa'},
      ),
    );
    final corpo = jsonDecode(chamadas.last.body) as Map<String, dynamic>;
    expect(
      corpo['respostas'],
      anyElement(equals({'pergunta_id': 'q-tipo', 'resposta': 'Casa'})),
    );
    expect(corpo['titulo'], 'Limpeza residencial');
  });

  test('texto das respostas para o profissional', () {
    expect(textoDaResposta(true), 'Sim');
    expect(textoDaResposta(false), 'Não');
    expect(textoDaResposta(['Janelas', 'Forno']), 'Janelas, Forno');
    expect(textoDaResposta(3), '3');
    expect(textoDaResposta(null), '—');
  });
}
