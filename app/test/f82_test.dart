import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/imagem_trato.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pecas.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/telas/recorrencias/modelos.dart';
import 'package:trato/telas/recorrencias/servico_fake.dart';
import 'package:trato/telas/recorrencias/servicos_recorrentes_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';
import 'apoio/fontes.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

Future<void> _montar(WidgetTester t, Widget tela, {double fonte = 1}) async {
  t.view.physicalSize = const Size(390, 2400);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
}

PerfilPublico _perfil({List<String> fotos = const [], int quantidade = 0}) => PerfilPublico(
      nome: 'Carlos Lima',
      iniciais: 'CL',
      categoria: 'Eletricista',
      verificacao: 'Identidade conferida',
      noTratoDesde: 2026,
      nota: 4.8,
      totalAvaliacoes: 0,
      servicosConcluidos: 4,
      sobre: 'Instalações residenciais.',
      cidade: 'Belo Horizonte',
      fotosPortfolio: quantidade,
      ultimasAvaliacoes: const [],
      listaFotosPortfolio: fotos,
    );

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);

  testWidgets('cartão de aditivo não mostra caixa de foto vazia', (t) async {
    await _montar(
      t,
      Scaffold(
        body: CartaoAditivo(
          aditivo: const Aditivo(
              titulo: 'Aditivo proposto', valorCentavos: 4500, descricao: 'Cabo novo.'),
          aoRecusar: () {},
          aoAprovar: () {},
        ),
      ),
    );
    expect(find.byType(EspacoFoto), findsNothing);
    expect(find.textContaining('[Foto'), findsNothing);
    expect(find.text('Aditivo proposto · R\$ 45,00'), findsOneWidget);
    expect(find.text('Cabo novo.'), findsOneWidget);
    expect(find.text('Aprovar aditivo'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final fonte in [1.0, 1.3]) {
    testWidgets('perfil público: nada escrito sobre as fotos de trabalhos (x$fonte)', (t) async {
      registrarImagemEmMemoria('f82-a', bytes: _png);
      registrarImagemEmMemoria('f82-b', bytes: _png);
      await _montar(
        t,
        PerfilPublicoTela(
            servico: ServicoPerfilPublicoFake(perfil: _perfil(fotos: ['f82-a', 'f82-b']))),
        fonte: fonte,
      );
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.textContaining('[Foto'), findsNothing);
      expect(find.text('Foto anexada'), findsNothing);
      expect(find.textContaining('Trabalho '), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('perfil público: trabalho sem imagem mostra "Trabalho N"', (t) async {
    await _montar(
        t, PerfilPublicoTela(servico: ServicoPerfilPublicoFake(perfil: _perfil(quantidade: 2))));
    expect(find.text('Trabalho 1'), findsOneWidget);
    expect(find.text('Trabalho 2'), findsOneWidget);
    expect(find.textContaining('[Foto'), findsNothing);
  });

  testWidgets('lista de recorrentes: uma seta só por cartão', (t) async {
    final series = [
      for (final id in ['r1', 'r2'])
        Recorrencia(
          id: id,
          status: id == 'r1' ? 'ativa' : 'cancelada',
          frequencia: 'semanal',
          valorCentavos: 18000,
          proximaVisita: DateTime.utc(2030, 12, 5, 17),
          meuPapel: 'cliente',
          propostoPorMim: false,
          outraParteNome: 'Carlos M.',
          pedidoOrigemId: 'p',
          visitas: const [],
        ),
    ];
    await _montar(t, ServicosRecorrentesTela(servico: ServicoRecorrenciasFake(series: series)));
    for (final id in ['r1', 'r2']) {
      expect(
        find.descendant(
            of: find.byKey(ValueKey('serie-$id')), matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
    }
    await t.tap(find.byKey(const ValueKey('serie-r1')));
    await t.pumpAndSettle();
    expect(find.byType(DetalheRecorrenciaTela), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
