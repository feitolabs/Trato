import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/servico_fake.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/busca/servico_fake.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/lgpd/central_privacidade_tela.dart';
import 'package:trato/telas/lgpd/excluir_conta_tela.dart';
import 'package:trato/telas/lgpd/servico_fake.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'package:trato/telas/mensagens/servico_fake.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/notificacoes/servico_fake.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 1200),
  double escala = 1.0,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: KeyedSubtree(key: UniqueKey(), child: tela),
    ),
  );
  await tester.pump();
}

void main() {
  group('Notificações', () {
    testWidgets('lista, marca como lida e abre o destino', (tester) async {
      final servico = ServicoNotificacoesFake();
      Notificacao? aberta;
      await _abrir(tester, NotificacoesTela(servico: servico, aoAbrirDestino: (n) => aberta = n));
      expect(find.text('2 não lidas'), findsOneWidget);
      await tester.tap(find.text('Novo orçamento recebido'));
      await tester.pump();
      expect(aberta?.destinoId, 'pedido-1');
      expect(servico.marcadas, ['n1']);
      expect(find.text('1 não lida'), findsOneWidget);
    });

    testWidgets('marcar todas como lidas', (tester) async {
      final servico = ServicoNotificacoesFake();
      await _abrir(tester, NotificacoesTela(servico: servico));
      await tester.tap(find.text('Marcar todas como lidas'));
      await tester.pump();
      expect(find.text('Tudo lido'), findsOneWidget);
      expect(servico.marcadas, ['todas']);
    });

    testWidgets('vazio, carregando e erro com nova tentativa', (tester) async {
      await _abrir(tester, NotificacoesTela(servico: ServicoNotificacoesFake(itens: const [])));
      expect(find.text('Nada por aqui'), findsOneWidget);
      await _abrir(tester, NotificacoesTela(servico: ServicoNotificacoesFake(travar: true)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _abrir(tester, NotificacoesTela(servico: ServicoNotificacoesFake(falhar: true)));
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('fonte grande no celular pequeno não estoura', (tester) async {
      await _abrir(
        tester,
        NotificacoesTela(servico: ServicoNotificacoesFake()),
        tamanho: const Size(320, 640),
        escala: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Mensagens', () {
    testWidgets('lista e abre a conversa do pedido', (tester) async {
      ConversaResumo? aberta;
      await _abrir(
        tester,
        MensagensTela(servico: const ServicoMensagensFake(), aoAbrirConversa: (c) => aberta = c),
      );
      expect(find.text('Carlos Menezes'), findsOneWidget);
      await tester.tap(find.text('Carlos Menezes'));
      expect(aberta?.pedidoId, 'pedido-1');
    });

    testWidgets('vazio e erro', (tester) async {
      await _abrir(tester, const MensagensTela(servico: ServicoMensagensFake(itens: [])));
      expect(find.text('Nenhuma conversa ainda'), findsOneWidget);
      await _abrir(tester, const MensagensTela(servico: ServicoMensagensFake(falhar: true)));
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  });

  group('Privacidade (LGPD)', () {
    testWidgets('consentimento obrigatório não desliga; opcional salva', (tester) async {
      final servico = ServicoPrivacidadeFake();
      await _abrir(tester, CentralPrivacidadeTela(servico: servico));
      final chaves = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
      expect(chaves.first.onChanged, isNull);
      await tester.tap(find.text('Avisos e novidades'));
      await tester.pump();
      expect(servico.alteracoes['avisos'], isTrue);
    });

    testWidgets('exportar meus dados pede ao serviço', (tester) async {
      final servico = ServicoPrivacidadeFake();
      await _abrir(tester, CentralPrivacidadeTela(servico: servico));
      await tester.tap(find.text('Exportar meus dados'));
      await tester.pump();
      expect(servico.exportacoes, 1);
      expect(find.textContaining('Pedido registrado'), findsOneWidget);
    });

    testWidgets('excluir conta só chama o serviço depois dos 2 passos', (tester) async {
      final servico = ServicoPrivacidadeFake();
      var excluida = false;
      await _abrir(
        tester,
        CentralPrivacidadeTela(servico: servico, aoContaExcluida: () => excluida = true),
      );
      await tester.scrollUntilVisible(find.text('Excluir minha conta'), 100);
      await tester.tap(find.text('Excluir minha conta'));
      await tester.pumpAndSettle();
      expect(find.text('PASSO 1 DE 2'), findsOneWidget);
      expect(find.textContaining('obrigação legal'), findsOneWidget);
      expect(servico.exclusoes, 0);

      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(find.text('PASSO 2 DE 2'), findsOneWidget);
      final botao = find.widgetWithText(FilledButton, 'Excluir minha conta');
      expect(tester.widget<FilledButton>(botao).onPressed, isNull);

      await tester.enterText(find.byType(TextField), ExcluirContaTela.palavraConfirmacao);
      await tester.pump();
      await tester.tap(botao);
      await tester.pump();
      expect(servico.exclusoes, 1);
      expect(excluida, isTrue);
    });

    testWidgets('falha ao excluir mostra o erro e não sai', (tester) async {
      final servico = ServicoPrivacidadeFake(falharAcao: true);
      var excluida = false;
      await _abrir(
        tester,
        ExcluirContaTela(servico: servico, aoContaExcluida: () => excluida = true),
      );
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'excluir');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir minha conta'));
      await tester.pump();
      expect(find.textContaining('Não foi possível'), findsOneWidget);
      expect(excluida, isFalse);
    });

    testWidgets('erro ao carregar e fonte grande', (tester) async {
      await _abrir(tester, CentralPrivacidadeTela(servico: ServicoPrivacidadeFake(falhar: true)));
      expect(find.text('Tentar de novo'), findsOneWidget);
      await _abrir(
        tester,
        CentralPrivacidadeTela(servico: ServicoPrivacidadeFake()),
        tamanho: const Size(320, 640),
        escala: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Ajuda', () {
    testWidgets('abre a resposta e chama suporte e relato', (tester) async {
      var suporte = false;
      var problema = false;
      await _abrir(
        tester,
        AjudaTela(
          servico: const ServicoAjudaFake(),
          aoFalarComSuporte: () => suporte = true,
          aoRelatarProblema: () => problema = true,
        ),
        tamanho: const Size(390, 1400),
      );
      await tester.tap(find.text('Como peço um serviço?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('receba orçamentos'), findsOneWidget);
      await tester.tap(find.text('Falar com o suporte'));
      await tester.tap(find.text('Relatar um problema'));
      expect(suporte, isTrue);
      expect(problema, isTrue);
    });

    testWidgets('textos sem promessas proibidas', (tester) async {
      await _abrir(
        tester,
        const AjudaTela(servico: ServicoAjudaFake()),
        tamanho: const Size(390, 1400),
      );
      final textos = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ');
      for (final proibido in ['garantia total', 'escrow', '24/7', '24 horas']) {
        expect(textos.toLowerCase().contains(proibido), isFalse, reason: proibido);
      }
    });

    testWidgets('erro e vazio', (tester) async {
      await _abrir(tester, const AjudaTela(servico: ServicoAjudaFake(falhar: true)));
      expect(find.text('Tentar de novo'), findsOneWidget);
      await _abrir(tester, const AjudaTela(servico: ServicoAjudaFake(itens: [])));
      expect(find.textContaining('Ainda não há perguntas'), findsOneWidget);
    });
  });

  group('Busca', () {
    testWidgets('mostra categorias, busca e abre o profissional', (tester) async {
      Profissional? aberto;
      await _abrir(
        tester,
        BuscaProfissionaisTela(
          servico: const ServicoBuscaFake(),
          aoAbrirProfissional: (p) => aberto = p,
        ),
      );
      expect(find.text('CATEGORIAS'), findsOneWidget);
      await tester.tap(find.text('Elétrica'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Carlos Mendes'), findsOneWidget);
      await tester.tap(find.text('Carlos Mendes'));
      expect(aberto?.nome, 'Carlos Mendes');
    });

    testWidgets('estado vazio, erro e carregando', (tester) async {
      await _abrir(
        tester,
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(), termoInicial: 'zzzz'),
      );
      await tester.pump();
      expect(find.text('Nada encontrado'), findsOneWidget);
      await _abrir(
        tester,
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(falhar: true), termoInicial: 'a'),
      );
      await tester.pump();
      expect(find.text('Tentar de novo'), findsOneWidget);
      await _abrir(
        tester,
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(travar: true), termoInicial: 'a'),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
