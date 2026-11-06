import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_catalogo.dart';
import 'apoio/exemplos/dados/repositorios_catalogo_fake.dart';
import 'package:trato/telas/agenda/agenda_tela.dart';
import 'package:trato/telas/agenda/modelos.dart';
import 'package:trato/telas/catalogo/categoria_tela.dart';
import 'package:trato/telas/catalogo/todas_categorias_tela.dart';
import 'package:trato/telas/legal/texto_legal_tela.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/telas/profissional_inicio/filtros_pedidos_tela.dart';
import 'package:trato/telas/servicos/detalhe_servico_tela.dart';
import 'package:trato/telas/servicos/modelos.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  final catalogo = RepositorioCatalogoFake();

  group('catálogo (fake)', () {
    test('filtra por bairro, preço, nota e disponibilidade', () async {
      final todos = await catalogo.profissionais('hidraulica', const FiltroProfissionais());
      expect(todos.length, greaterThan(2));
      final hoje = await catalogo.profissionais(
        'hidraulica',
        const FiltroProfissionais(soDisponiveisHoje: true),
      );
      expect(hoje.every((p) => p.atendeHoje), isTrue);
      final nota = await catalogo.profissionais(
        'hidraulica',
        const FiltroProfissionais(notaMinima: 4.8),
      );
      expect(nota.every((p) => p.nota >= 4.8), isTrue);
      final bairro = await catalogo.profissionais(
        'hidraulica',
        const FiltroProfissionais(bairro: 'savassi'),
      );
      expect(bairro.map((p) => p.nome), contains('Sérgio Almeida'));
      final barato = await catalogo.profissionais(
        'hidraulica',
        const FiltroProfissionais(precoMaxCentavos: 7000),
      );
      expect(barato.every((p) => p.precoAPartirCentavos! <= 7000), isTrue);
    });

    test('busca por nome, serviço e categoria, sem depender de acento', () async {
      expect((await catalogo.buscar('eletrica')).map((p) => p.nome), contains('Carlos Mendes'));
      expect((await catalogo.buscar('desentupimento')).map((p) => p.nome),
          contains('Sérgio Almeida'));
      expect(await catalogo.buscar('zzzz'), isEmpty);
    });

    test('só traz categorias ativas, com as sete do protótipo', () async {
      final nomes = (await catalogo.categorias()).map((c) => c.nome);
      for (final n in ['Elétrica', 'Hidráulica', 'Pintura', 'Montagem', 'Limpeza', 'Ar-cond.', 'Chaveiro']) {
        expect(nomes, contains(n));
      }
    });

    test('perfil traz detalhe completo', () async {
      final p = await catalogo.perfil('prof-carlos');
      expect(p.detalhe?.bio, isNotEmpty);
      expect(p.detalhe!.avaliacoes, isNotEmpty);
    });
  });

  group('todas as categorias', () {
    testWidgets('mostra a grade, filtra pela busca e devolve a escolhida', (tester) async {
      CategoriaServicoEscolhida? escolhida;
      await _abrir(
        tester,
        TodasCategoriasTela(
          carregar: catalogo.categorias,
          aoEscolher: (c) => escolhida = c.nome,
        ),
      );
      expect(find.text('Elétrica'), findsOneWidget);
      expect(find.text('Jardinagem'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'chave');
      await tester.pump();
      expect(find.text('Chaveiro'), findsOneWidget);
      expect(find.text('Elétrica'), findsNothing);

      await tester.tap(find.text('Chaveiro'));
      expect(escolhida, 'Chaveiro');

      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump();
      expect(find.text('Nenhuma categoria encontrada'), findsOneWidget);
    });

    testWidgets('mostra erro com "Tentar de novo" e o estado vazio', (tester) async {
      await _abrir(
        tester,
        TodasCategoriasTela(carregar: () async => throw StateError('x'), aoEscolher: (_) {}),
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('mostra o estado vazio', (tester) async {
      await _abrir(
        tester,
        TodasCategoriasTela(carregar: () async => const [], aoEscolher: (_) {}),
      );
      expect(find.text('Nenhuma categoria por enquanto'), findsOneWidget);
    });
  });

  group('categoria', () {
    testWidgets('lista profissionais, aplica filtro e pede orçamento', (tester) async {
      final categoria = (await catalogo.categorias()).firstWhere((c) => c.id == 'eletrica');
      var pediu = 0;
      await _abrir(
        tester,
        CategoriaTela(
          categoria: categoria,
          carregar: (f) => catalogo.profissionais('eletrica', f),
          aoPedirOrcamento: (_) => pediu++,
        ),
      );
      expect(find.text('Carlos Mendes'), findsOneWidget);
      expect(find.text('André Lopes'), findsOneWidget);
      expect(find.text('A partir de R\$ 90,00'), findsOneWidget);

      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4,8 ou mais'));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Carlos Mendes'), findsOneWidget);
      expect(find.text('André Lopes'), findsNothing);
      expect(find.text('Filtros (2)'), findsOneWidget);

      await tester.tap(find.text('Pedir orçamento a Carlos'));
      await tester.tap(find.text('Pedir orçamento em Elétrica'));
      expect(pediu, 2);
    });

    testWidgets('sem resultado, explica e permite mudar os filtros', (tester) async {
      final categoria = (await catalogo.categorias()).firstWhere((c) => c.id == 'jardinagem');
      await _abrir(
        tester,
        CategoriaTela(
          categoria: categoria,
          carregar: (f) => catalogo.profissionais('jardinagem', const FiltroProfissionais(notaMinima: 4.9)),
        ),
      );
      expect(find.text('Nenhum profissional encontrado'), findsOneWidget);
    });
  });

  group('detalhe do serviço', () {
    final repo = RepositorioServicosClienteFake();

    test('ações por estado', () async {
      Future<List<AcaoServico>> acoes(String id) async => (await repo.detalhe(id)).acoes;
      expect(await acoes(ServicosExemplo.orcamentos), [AcaoServico.verOrcamentos]);
      expect(await acoes(ServicosExemplo.tomadasEmPagamento), contains(AcaoServico.pagar));
      expect(await acoes(ServicosExemplo.tomadas), contains(AcaoServico.acompanhar));
      expect(await acoes(ServicosExemplo.pintura), contains(AcaoServico.avaliar));
      expect(await acoes(ServicosExemplo.pintura), contains(AcaoServico.abrirProblema));
    });

    testWidgets('mostra linha do tempo, profissional, valores e dispara a ação', (tester) async {
      final dados = await repo.detalhe(ServicosExemplo.tomadas);
      AcaoServico? tocada;
      await _abrir(tester, DetalheServicoTela(dados: dados, aoAcao: (a) => tocada = a));

      expect(find.text('Troca de tomadas e chuveiro'), findsOneWidget);
      expect(find.text('Carlos Mendes'), findsOneWidget);
      expect(find.text('Em execução'), findsOneWidget);
      expect(find.text('R\$ 425,00'), findsOneWidget);
      await tester.ensureVisible(find.text('Acompanhar o serviço'));
      await tester.tap(find.text('Acompanhar o serviço'));
      expect(tocada, AcaoServico.acompanhar);
    });
  });

  group('agenda', () {
    testWidgets('agrupa por dia e oferece check-in só no que não terminou', (tester) async {
      final hoje = DateTime(2026, 10, 30);
      Agendamento? checkIn;
      await _abrir(
        tester,
        AgendaTela(
          hoje: hoje,
          carregar: RepositorioAgendaFake(hoje: hoje).listar,
          aoFazerCheckIn: (a) => checkIn = a,
        ),
      );
      expect(find.text('HOJE'), findsOneWidget);
      expect(find.text('AMANHÃ'), findsOneWidget);
      expect(find.text('Concluído'), findsOneWidget);
      // O atendimento já em andamento oferece "Concluir serviço"; os outros, o check-in.
      expect(find.text('Fazer check-in'), findsNWidgets(3));
      expect(find.text('Concluir serviço'), findsOneWidget);
      await tester.tap(find.text('Fazer check-in').first);
      expect(checkIn?.id, 'ag-2');
      await tester.tap(find.text('Concluir serviço'));
      expect(checkIn?.id, 'ag-1');
    });

    testWidgets('agenda vazia explica', (tester) async {
      await _abrir(tester, AgendaTela(carregar: () async => const []));
      expect(find.text('Nada agendado'), findsOneWidget);
    });

    test('rótulos do dia', () {
      final h = DateTime(2026, 10, 30);
      expect(rotuloDoDia(DateTime(2026, 10, 31), h), 'Amanhã');
      expect(rotuloDoDia(DateTime(2026, 11, 3), h), 'Ter, 03/11');
    });
  });

  group('filtros dos pedidos abertos', () {
    testWidgets('devolve o filtro escolhido', (tester) async {
      FiltroPedidosAbertos? saida;
      final categorias = await catalogo.categorias();
      await _abrir(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => saida = await Navigator.of(context).push(
                MaterialPageRoute<FiltroPedidosAbertos>(
                  builder: (_) => FiltrosPedidosAbertosTela(categorias: categorias),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hidráulica'));
      await tester.enterText(find.byType(TextField), 'Savassi');
      await tester.tap(find.text('R\$ 200 a R\$ 500'));
      await tester.tap(find.text('Urgentes primeiro'));
      await tester.pump();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(saida?.categoriaId, 'hidraulica');
      expect(saida?.bairro, 'Savassi');
      expect(saida?.precoMinCentavos, 20000);
      expect(saida?.precoMaxCentavos, 50000);
      expect(saida?.ordenar, 'urgentes');
    });
  });

  group('notificações', () {
    test('tipo do backend vira tipo de tela', () {
      expect(tipoDaNotificacao('orcamento.recebido'), TipoNotificacao.orcamento);
      expect(tipoDaNotificacao('pagamento.confirmado'), TipoNotificacao.pagamento);
      expect(tipoDaNotificacao('disputa.aberta'), TipoNotificacao.disputa);
      expect(tipoDaNotificacao('garantia.retrabalho'), TipoNotificacao.retrabalho);
      expect(tipoDaNotificacao('agenda.lembrete'), TipoNotificacao.pedido);
      expect(tipoDaNotificacao('mensagem'), TipoNotificacao.mensagem);
      expect(tipoDaNotificacao(null), TipoNotificacao.sistema);
    });
  });

  group('termos e política', () {
    test('as cópias do app são iguais aos textos de docs/juridico', () {
      for (final (copia, original) in [
        ('assets/legal/termos-de-uso.md', '../docs/juridico/termos-de-uso.md'),
        ('assets/legal/politica-de-privacidade.md', '../docs/juridico/politica-de-privacidade.md'),
      ]) {
        final a = File(copia).readAsStringSync().replaceAll('\r\n', '\n');
        final b = File(original).readAsStringSync().replaceAll('\r\n', '\n');
        expect(a, b, reason: '$copia está diferente de $original');
      }
    });

    testWidgets('mostra o texto com o aviso legal', (tester) async {
      await _abrir(tester, TextoLegalTela.de(TextoLegal.termos));
      expect(find.text('Termos de uso'), findsOneWidget);
      expect(find.textContaining('Belo Horizonte/MG'), findsWidgets);
      expect(find.textContaining('Quem somos'), findsOneWidget);
    });

    testWidgets('o índice abre cada texto', (tester) async {
      TextoLegal? aberto;
      await _abrir(tester, TermosEPoliticaTela(aoAbrir: (t) => aberto = t));
      await tester.tap(find.text('Política de privacidade'));
      expect(aberto, TextoLegal.privacidade);
    });
  });
}

typedef CategoriaServicoEscolhida = String;
