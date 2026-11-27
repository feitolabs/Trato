import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'apoio/exemplos/telas/cliente/dados_exemplo.dart' as excli;
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'apoio/exemplos/telas/ajuda/servico_fake.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'apoio/exemplos/telas/busca/servico_fake.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/lgpd/central_privacidade_tela.dart';
import 'package:trato/telas/lgpd/excluir_conta_tela.dart';
import 'apoio/exemplos/telas/lgpd/servico_fake.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'apoio/exemplos/telas/mensagens/servico_fake.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'apoio/exemplos/telas/notificacoes/servico_fake.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/componentes/componentes.dart';

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
    testWidgets('abrir a lista marca tudo como lido e tocar num aviso abre o destino',
        (tester) async {
      final servico = ServicoNotificacoesFake();
      final contagens = <int>[];
      Notificacao? aberta;
      await _abrir(
        tester,
        NotificacoesTela(
          servico: servico,
          aoAbrirDestino: (n) => aberta = n,
          aoContarNaoLidas: contagens.add,
        ),
      );
      // SINO-1: ao abrir, os 2 avisos não lidos passam a lidos, o sino zera e o backend é avisado.
      expect(find.text('Tudo lido'), findsOneWidget);
      expect(find.textContaining('não lida'), findsNothing);
      expect(find.text('Marcar todas como lidas'), findsNothing);
      expect(servico.marcadas, ['todas']);
      expect(contagens.last, 0);

      await tester.tap(find.text('Novo orçamento recebido'));
      await tester.pump();
      expect(aberta?.destinoId, 'pedido-1');
      expect(find.text('Tudo lido'), findsOneWidget);
    });

    testWidgets('aviso novo com a lista aberta: tocar marca como lido e abre o destino',
        (tester) async {
      final servico = _ServicoComAvisoNovo();
      final recarregar = ValueNotifier<int>(0);
      final contagens = <int>[];
      Notificacao? aberta;
      await _abrir(
        tester,
        NotificacoesTela(
          servico: servico,
          atualizarQuando: recarregar,
          aoAbrirDestino: (n) => aberta = n,
          aoContarNaoLidas: contagens.add,
        ),
      );
      expect(find.text('Tudo lido'), findsOneWidget);

      recarregar.value++; // chega um aviso novo
      await tester.pumpAndSettle();
      expect(find.text('1 não lida'), findsOneWidget);
      expect(contagens.last, 1);

      await tester.tap(find.text('Aviso novo'));
      await tester.pump();
      expect(aberta?.destinoId, 'pedido-9');
      expect(servico.marcadas, ['novo']); // nada a marcar ao abrir: já estava tudo lido
      expect(find.text('Tudo lido'), findsOneWidget);
      expect(contagens.last, 0);
    });

    testWidgets('marcar todas como lidas: o botão aparece quando chega aviso novo', (tester) async {
      final servico = _ServicoComAvisoNovo();
      final recarregar = ValueNotifier<int>(0);
      await _abrir(
        tester,
        NotificacoesTela(servico: servico, atualizarQuando: recarregar),
      );
      expect(find.text('Marcar todas como lidas'), findsNothing);

      recarregar.value++;
      await tester.pumpAndSettle();
      expect(find.text('1 não lida'), findsOneWidget);
      await tester.tap(find.text('Marcar todas como lidas'));
      await tester.pump();
      expect(find.text('Tudo lido'), findsOneWidget);
      expect(servico.marcadas, ['todas']);
    });

    testWidgets('vazio, carregando e erro com nova tentativa', (tester) async {
      await _abrir(tester, NotificacoesTela(servico: ServicoNotificacoesFake(itens: const [])));
      expect(find.text('Nada por aqui'), findsOneWidget);
      await _abrir(tester, NotificacoesTela(servico: ServicoNotificacoesFake(travar: true)));
      expect(find.byType(EsqueletoLista), findsOneWidget);
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
      expect(find.textContaining('Cópia dos seus dados'), findsWidgets);
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

      // O aviso dos Tratinhos alonga a tela: rola até o botão.
      await tester.scrollUntilVisible(find.text('Continuar'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.text('Continuar'));
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(find.text('PASSO 2 DE 2'), findsOneWidget);
      final botao = find.widgetWithText(FilledButton, 'Excluir minha conta');
      await tester.scrollUntilVisible(botao, 200, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<FilledButton>(botao).onPressed, isNull);

      await tester.enterText(find.byType(TextField), ExcluirContaTela.palavraConfirmacao);
      await tester.pump();
      await tester.ensureVisible(botao);
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
      // O aviso dos Tratinhos alonga a tela: rola até o botão.
      await tester.scrollUntilVisible(find.text('Continuar'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.text('Continuar'));
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'excluir');
      await tester.pump();
      await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Excluir minha conta'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Excluir minha conta'));
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

    testWidgets('sem destino, os botões de suporte e de relato não aparecem', (tester) async {
      await _abrir(tester, const AjudaTela(servico: ServicoAjudaFake()));
      expect(find.text('Falar com o suporte'), findsNothing);
      expect(find.text('Relatar um problema'), findsNothing);
      expect(find.text('Como peço um serviço?'), findsOneWidget);
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
          sugestoes: excli.categorias,
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
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(falhar: true), termoInicial: 'ab'),
      );
      await tester.pump();
      expect(find.text('Tentar de novo'), findsOneWidget);
      await _abrir(
        tester,
        const BuscaProfissionaisTela(servico: ServicoBuscaFake(travar: true), termoInicial: 'ab'),
      );
      expect(find.byType(EsqueletoLista), findsOneWidget);
    });
  });
}

/// Na 1ª leitura não há nada novo; depois que a tela é recarregada chega um aviso não lido.
class _ServicoComAvisoNovo implements ServicoNotificacoes {
  final marcadas = <String>[];
  var _leituras = 0;

  @override
  Future<List<Notificacao>> listar() async {
    _leituras++;
    return [
      const Notificacao(
        id: 'velho',
        tipo: TipoNotificacao.pagamento,
        titulo: 'Aviso antigo',
        texto: 't',
        quando: 'ontem',
        lida: true,
      ),
      if (_leituras > 1)
        const Notificacao(
          id: 'novo',
          tipo: TipoNotificacao.pedido,
          titulo: 'Aviso novo',
          texto: 't',
          quando: 'agora',
          destinoId: 'pedido-9',
        ),
    ];
  }

  @override
  Future<void> marcarLida(String id) async => marcadas.add(id);

  @override
  Future<void> marcarTodasLidas() async => marcadas.add('todas');
}
