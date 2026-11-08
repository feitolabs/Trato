import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/componentes/base.dart';
import 'package:trato_admin/dados/modelos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Correções do módulo Operação: fila paginada, lista leve de disputas, assumir, decisão obsoleta
/// e atualização sem perder filtro nem seleção.
List<Verificacao> _muitas(int n) => [
      for (var i = 0; i < n; i++)
        Verificacao(
          id: 'v-$i',
          profissional: 'Profissional ${i.toString().padLeft(3, '0')}',
          cidade: 'Belo Horizonte - MG',
          enviadaEm: DateTime(2026, 10, 1).add(Duration(minutes: i)),
          documentos: const ['Selfie'],
        ),
    ];

/// Rola a FILA (lista da esquerda), não o detalhe.
Future<void> _rolarFilaAte(WidgetTester tester, Finder alvo) async {
  final fila = find.ancestor(of: find.byType(CartaoLista).first, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(alvo, 400, scrollable: fila);
  await tester.pumpAndSettle();
}

/// Como [confirmarMotivo], mas só o campo do modal (o detalhe do Risco tem outro "Motivo").
Future<void> _motivoNoModal(WidgetTester tester, String botao, String motivo) async {
  final modal = find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet);
  await tester.enterText(find.descendant(of: modal, matching: find.byType(TextField)), motivo);
  await tester.pump();
  await tester.tap(find.descendant(of: modal, matching: find.text(botao)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fila com mais de 100 cadastros mostra o total real e carrega mais', (tester) async {
    final api = ApiFake()..verificacoes = _muitas(130);
    await abrirPainel(tester, papel: 'cadastro', api: api);

    expect(find.text('Pendentes 130'), findsOneWidget);
    expect(find.textContaining('130 cadastros aguardando'), findsOneWidget);
    await _rolarFilaAte(tester, find.text('Mostrando 50 de 130 cadastros'));
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();
    await _rolarFilaAte(tester, find.text('Mostrando 100 de 130 cadastros'));
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();
    await _rolarFilaAte(tester, find.text('Todos os 130 cadastros'));
    expect(find.text('Profissional 129'), findsOneWidget);
    expect(find.text('Carregar mais'), findsNothing);
  });

  testWidgets('busca de cadastro vai ao servidor e acha quem não estava na primeira página', (tester) async {
    final api = ApiFake()..verificacoes = _muitas(130);
    await abrirPainel(tester, papel: 'cadastro', api: api);
    expect(find.text('Profissional 120'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Buscar cadastro'), 'profissional 120');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Profissional 120'), findsWidgets);
    expect(find.text('Todos os 1 cadastros'), findsOneWidget);
  });

  testWidgets('assumir a análise e ver quem está analisando', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    await tester.tap(find.text('Ana Ribeiro').first);
    await tester.pumpAndSettle();
    await rolarListaAte(tester, find.text('Assumir análise'));
    await tester.tap(find.text('Assumir análise'));
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Assumir análise', motivo: 'Vou analisar este cadastro');

    expect(find.text('Análise assumida.'), findsOneWidget);
    expect(find.text('Você está analisando este cadastro.'), findsOneWidget);
    // A seleção continua na mesma pessoa depois de atualizar.
    expect(find.text('Ana Ribeiro'), findsWidgets);
  });

  testWidgets('cadastro assumido por outra pessoa esconde aprovar e oferece assumir no lugar', (tester) async {
    final api = ApiFake()
      ..verificacoes = [
        _muitas(1).single.assumidaPor('eq-outra', 'Bruna Cadastro'),
      ];
    await abrirPainel(tester, papel: 'cadastro', api: api);
    await tester.tap(find.text('Profissional 000').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Bruna Cadastro está analisando este cadastro.', findRichText: true), findsOneWidget);
    expect(find.text('Aprovar profissional'), findsNothing);
    await tester.tap(find.text('Assumir no lugar'));
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Assumir no lugar', motivo: 'Bruna saiu de férias hoje');

    expect(find.text('Você está analisando este cadastro.'), findsOneWidget);
    await rolarListaAte(tester, find.text('Aprovar profissional'));
    expect(find.text('Aprovar profissional'), findsOneWidget);
  });

  testWidgets('disputas: a lista é uma chamada só e o detalhe vem ao abrir', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas');

    expect(api.chamadasListaDisputas, 1);
    // Só a disputa aberta no detalhe (a primeira) é buscada inteira.
    expect(api.chamadasDetalheDisputa, 1);
    expect(find.text('Linha do tempo'), findsOneWidget);
  });

  testWidgets('decisão sobre disputa que mudou é recusada e a tela se atualiza', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'administrador', api: api, secao: 'disputas');
    final primeira = (await tester.runAsync(() => api.listarDisputas()))!.itens.first;
    // Outra pessoa decidiu enquanto a tela estava aberta.
    api.mudarEstadoDisputa(primeira.id, StatusDisputa.decidida);

    await rolarListaAte(tester, find.text('Liberar ao profissional'));
    await tester.tap(find.text('Liberar ao profissional'));
    await tester.enterText(find.widgetWithText(TextField, 'Motivo'), 'Fotos mostram o serviço feito');
    await tester.pump();
    await rolarListaAte(tester, find.widgetWithText(FilledButton, 'Liberar ao profissional'));
    await tester.tap(find.widgetWithText(FilledButton, 'Liberar ao profissional'));
    await tester.pumpAndSettle();

    expect(find.textContaining('A disputa mudou desde que você abriu'), findsOneWidget);
  });

  testWidgets('risco: depois de uma ação, o filtro e o alerta selecionado continuam', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'risco');
    await tester.tap(find.textContaining(RegExp(r'^Todos \d+$')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Troca de chave PIX').first);
    await tester.pumpAndSettle();

    await rolarListaAte(tester, find.text('Assumir alerta'));
    await tester.tap(find.text('Assumir alerta'));
    await tester.pumpAndSettle();
    await _motivoNoModal(tester, 'Assumir alerta', 'Vou olhar este alerta agora');

    final filtro = tester.widget<FiltroStatus>(find.byType(FiltroStatus));
    expect(filtro.selecionado, 'todos');
    // O título do detalhe segue no mesmo alerta.
    expect(
      find.descendant(of: find.byType(ListView).last, matching: find.text('Troca de chave PIX')),
      findsOneWidget,
    );
  });

  testWidgets('a fila se atualiza sozinha sem perder a seleção', (tester) async {
    final antes = intervaloAtualizacao;
    intervaloAtualizacao = const Duration(seconds: 30);
    addTearDown(() => intervaloAtualizacao = antes);
    final api = ApiFake()..verificacoes = _muitas(3);
    await abrirPainel(tester, papel: 'cadastro', api: api);
    await tester.tap(find.text('Profissional 002').first);
    await tester.pumpAndSettle();

    // Chega um cadastro mais antigo que todos: a ordem muda.
    api.verificacoes = [
      Verificacao(
        id: 'v-novo',
        profissional: 'Chegou Agora',
        cidade: 'Belo Horizonte - MG',
        enviadaEm: DateTime(2026, 9, 1),
        documentos: const ['Selfie'],
      ),
      ..._muitas(3),
    ];
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(find.text('Chegou Agora'), findsOneWidget);
    expect(find.text('Pendentes 4'), findsOneWidget);
    // O detalhe continua no mesmo cadastro, não no que ocupou a posição dele.
    expect(find.descendant(of: find.byType(ListView).last, matching: find.text('Profissional 002')), findsOneWidget);
  });

  testWidgets('assumir disputa mostra quem está analisando', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'disputas');
    await tester.tap(find.text('Assumir disputa'));
    await tester.pumpAndSettle();
    await _motivoNoModal(tester, 'Assumir disputa', 'Vou analisar este caso agora');

    expect(find.text('Disputa assumida.'), findsOneWidget);
    expect(find.text('Você está analisando esta disputa.'), findsOneWidget);
    expect(find.textContaining('Com '), findsWidgets);
  });

  testWidgets('disputa assumida por outra pessoa esconde a decisão e oferece assumir no lugar', (tester) async {
    final api = ApiFake();
    final primeira = (await tester.runAsync(() => api.listarDisputas()))!.itens.first;
    api.assumirDisputaComo(primeira.id, 'eq-outra', 'Marta Mediadora');
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas');

    expect(find.textContaining('Marta Mediadora está analisando esta disputa.', findRichText: true), findsOneWidget);
    expect(find.text('Registrar decisão'), findsNothing);
    await tester.tap(find.text('Assumir no lugar'));
    await tester.pumpAndSettle();
    await _motivoNoModal(tester, 'Assumir no lugar', 'Marta está de folga hoje');

    expect(find.text('Você está analisando esta disputa.'), findsOneWidget);
    await rolarListaAte(tester, find.text('Registrar decisão'));
    expect(find.text('Registrar decisão'), findsOneWidget);
  });
}
