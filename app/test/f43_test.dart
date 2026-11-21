import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pedido_novo/checklists_categoria.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

FormularioPedido _formulario({
  required String categoria,
  List<String> servicos = const ['Serviço geral'],
  Set<String> servicosIniciais = const {'Serviço geral'},
  List<PerguntaPedido> perguntas = const [],
  String descricaoInicial = '',
}) =>
    FormularioPedido(
      categoria: categoria,
      servicos: servicos,
      servicosIniciais: servicosIniciais,
      perguntaQuantidade: 'Quantidade',
      dicaQuantidade: 'Aproximado',
      quantidadeInicial: 1,
      perguntaVoltagem: '',
      voltagens: const [],
      voltagemInicial: '',
      descricaoInicial: descricaoInicial,
      fotos: const [],
      prazos: const ['Flexível'],
      faixas: const [FaixaPreco(minimoCentavos: 10000, maximoCentavos: 20000)],
      endereco: '',
      avisoEndereco: '',
      avisoPrazo: '',
      aceitaRemoto: true,
      perguntas: perguntas,
    );

Future<void> _abrir(
  WidgetTester tester, {
  required FormularioPedido formulario,
  void Function(RascunhoPedido)? aoEnviar,
}) async {
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: NovoPedidoTela(
        formulario: formulario,
        aoEnviar: aoEnviar,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _marcarRemotoEEnviar(WidgetTester tester) async {
  await tester.tap(find.text('Remoto'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enviar pedido'));
  await tester.pumpAndSettle();
}

void main() {
  group('F43 · mapa de checklists por categoria', () {
    test('cobre todas as categorias principais com normalização de acentos e maiúsculas', () {
      const categorias = [
        'Eletricista',
        'ELÉTRICA · Tomadas',
        'Encanador',
        'Diarista',
        'Limpeza residencial',
        'Pintor',
        'Ar-condicionado',
        'Montador de móveis',
        'Marido de aluguel',
        'Chaveiro',
        'Dedetização',
        'Jardinagem',
      ];
      for (final cat in categorias) {
        final itens = itensChecklistCategoria(cat);
        expect(itens.length, inInclusiveRange(3, 5), reason: 'Categoria: $cat');
      }
    });

    test('categoria fora do mapa devolve lista vazia sem quebrar', () {
      expect(itensChecklistCategoria('Aulas de violão'), isEmpty);
      expect(itensChecklistCategoria(''), isEmpty);
    });

    test('remove itens já presentes nos chips genéricos para não duplicar', () {
      final itens = itensChecklistCategoria(
        'Eletricista',
        excluir: const ['disjuntor desarmando'],
      );
      expect(itens, isNot(contains('Disjuntor desarmando')));
      expect(itens.length, 3);
    });

    test('montarDescricaoComChecklist combina sem duplicar', () {
      expect(
        montarDescricaoComChecklist(
          textoLivre: '  Chuveiro queimou ontem  ',
          itensMarcados: const [
            'Disjuntor desarmando',
            'disjuntor desarmando',
            'Instalar ou trocar chuveiro'
          ],
        ),
        'Chuveiro queimou ontem\n\nItens selecionados: Disjuntor desarmando, Instalar ou trocar chuveiro.',
      );
      expect(
        montarDescricaoComChecklist(
          textoLivre: '',
          itensMarcados: const ['Cópia de chave'],
        ),
        'Itens selecionados: Cópia de chave.',
      );
      expect(
        montarDescricaoComChecklist(
          textoLivre: 'Só texto livre',
          itensMarcados: const [],
        ),
        'Só texto livre',
      );
    });
  });

  group('F43 · NovoPedidoTela com checklist', () {
    testWidgets('exibe chips da categoria e omite quando categoria não está no mapa',
        (tester) async {
      await _abrir(tester, formulario: _formulario(categoria: 'Encanador'));
      expect(find.byKey(const Key('checklist-categoria')), findsOneWidget);
      expect(find.text('Vazamento em cano ou registro'), findsOneWidget);
      expect(find.text('Torneira ou pia pingando'), findsOneWidget);

      await _abrir(tester, formulario: _formulario(categoria: 'Aulas de piano'));
      expect(find.byKey(const Key('checklist-categoria')), findsNothing);
    });

    testWidgets('não exibe checklist quando a categoria já tem pergunta multipla do backend',
        (tester) async {
      await _abrir(
        tester,
        formulario: _formulario(
          categoria: 'Eletricista',
          perguntas: const [
            PerguntaPedido(
              id: 'q1',
              texto: 'O que precisa?',
              tipo: 'multipla',
              opcoes: ['Tomada', 'Chuveiro'],
            ),
          ],
        ),
      );
      expect(find.byKey(const Key('checklist-categoria')), findsNothing);
    });

    testWidgets('marcar e desmarcar preserva texto livre e envia sem duplicar ao reenviar',
        (tester) async {
      final enviados = <RascunhoPedido>[];
      await _abrir(
        tester,
        formulario: _formulario(categoria: 'Chaveiro'),
        aoEnviar: enviados.add,
      );

      final campo = find.byType(TextField).first;
      await tester.enterText(campo, 'Porta da sala travou por dentro');
      await tester.pumpAndSettle();

      // Marca dois chips e desmarca um.
      await tester.tap(find.text('Abertura de porta trancada'));
      await tester.tap(find.text('Cópia de chave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cópia de chave'));
      await tester.pumpAndSettle();

      // Texto livre permanece intacto no campo.
      expect(find.text('Porta da sala travou por dentro'), findsOneWidget);

      await _marcarRemotoEEnviar(tester);
      // Reenvio não duplica os itens.
      await tester.tap(find.text('Enviar pedido'));
      await tester.pumpAndSettle();

      expect(enviados, hasLength(2));
      const esperado =
          'Porta da sala travou por dentro\n\nItens selecionados: Abertura de porta trancada.';
      expect(enviados[0].descricao, esperado);
      expect(enviados[1].descricao, esperado);
    });

    testWidgets('permite enviar marcando apenas itens do checklist sem digitar texto livre',
        (tester) async {
      RascunhoPedido? enviado;
      await _abrir(
        tester,
        formulario: _formulario(categoria: 'Jardinagem'),
        aoEnviar: (r) => enviado = r,
      );
      await tester.tap(find.text('Corte de grama e limpeza'));
      await tester.pumpAndSettle();

      await _marcarRemotoEEnviar(tester);
      expect(enviado, isNotNull);
      expect(enviado!.descricao, 'Itens selecionados: Corte de grama e limpeza.');
    });
  });
}
