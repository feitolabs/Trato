// Termos 3.6: listas `incluido` e `nao_incluido` da categoria de serviço.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/catalogo/categoria_tela.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester t, CategoriaServico categoria,
    {Size? tamanho, double fonte = 1}) async {
  t.view.physicalSize = tamanho ?? const Size(390, 844);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: CategoriaTela(
      categoria: categoria,
      carregar: (_) async => const [],
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('RepositorioCatalogoApi lê incluido e nao_incluido e aceita ausência ou nulo', () async {
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato(),
      cliente: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode([
              {
                'id': 'cat-1',
                'nome': 'Eletricista',
                'slug': 'eletricista',
                'incluido': ['Troca de disjuntor', '  Instalação de tomada  ', '', 123],
                'nao_incluido': ['Compra de cabos', null],
              },
              {
                'id': 'cat-2',
                'nome': 'Encanador',
                'slug': 'encanador',
                'incluido': null,
              },
            ])),
            200,
            headers: const {'content-type': 'application/json'},
          )),
    );
    final lista = await RepositorioCatalogoApi(api).categorias();
    expect(lista, hasLength(2));

    final eletricista = lista.firstWhere((c) => c.id == 'cat-1');
    expect(eletricista.incluido, ['Troca de disjuntor', 'Instalação de tomada']);
    expect(eletricista.naoIncluido, ['Compra de cabos']);

    final encanador = lista.firstWhere((c) => c.id == 'cat-2');
    expect(encanador.incluido, isEmpty);
    expect(encanador.naoIncluido, isEmpty);
  });

  testWidgets('CategoriaTela mostra incluído e não incluído quando preenchidos, sem estouro',
      (t) async {
    await _abrir(
      t,
      const CategoriaServico(
        'Eletricista',
        Icons.bolt,
        id: 'cat-1',
        incluido: ['Troca de disjuntor', 'Instalação de tomada'],
        naoIncluido: ['Compra de cabos', 'Obra em alvenaria'],
      ),
      tamanho: const Size(320, 568),
      fonte: 1.3,
    );
    expect(find.byKey(const ValueKey('categoria-escopo')), findsOneWidget);
    expect(find.text('O que está incluído'), findsOneWidget);
    expect(find.text('• Troca de disjuntor'), findsOneWidget);
    expect(find.text('• Instalação de tomada'), findsOneWidget);
    expect(find.text('O que não está incluído'), findsOneWidget);
    expect(find.text('• Compra de cabos'), findsOneWidget);
    expect(find.text('• Obra em alvenaria'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('CategoriaTela omite cada bloco quando a lista correspondente está vazia', (t) async {
    await _abrir(
      t,
      const CategoriaServico(
        'Eletricista',
        Icons.bolt,
        incluido: ['Troca de disjuntor'],
      ),
    );
    expect(find.text('O que está incluído'), findsOneWidget);
    expect(find.text('O que não está incluído'), findsNothing);

    await _abrir(
      t,
      const CategoriaServico(
        'Eletricista',
        Icons.bolt,
        naoIncluido: ['Compra de cabos'],
      ),
    );
    expect(find.text('O que está incluído'), findsNothing);
    expect(find.text('O que não está incluído'), findsOneWidget);
  });

  testWidgets('CategoriaTela omite o bloco inteiro quando listas estão vazias ou ausentes',
      (t) async {
    await _abrir(t, const CategoriaServico('Encanador', Icons.water_drop_outlined));
    expect(find.byKey(const ValueKey('categoria-escopo')), findsNothing);
    expect(find.text('O que está incluído'), findsNothing);
    expect(find.text('O que não está incluído'), findsNothing);
  });
}
