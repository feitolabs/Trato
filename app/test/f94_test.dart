import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/tela_nao_encontrada.dart';
import 'package:trato/dispositivo/toque_push.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/navegacao_casca.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';
import 'apoio/fontes.dart';

const _uuid = '3f2b8c1e-9a4d-4e7b-8c55-0d6f1a2b3c4d';

class _Memoria implements RegistroDeConsumo {
  final ids = <String>{};
  @override
  Future<bool> jaConsumido(String id) async => ids.contains(id);
  @override
  Future<void> marcar(String id) async => ids.add(id);
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() {
    ligarDemoNosTestes();
    DeepLinks.reiniciarParaTeste();
    ControladorCasca.aoCascaPronta = DeepLinks.aoCascaPronta;
  });
  tearDown(() {
    DeepLinks.reiniciarParaTeste();
    DeepLinks.navegador = () => null;
    RotasTrato.repos = repositoriosDemo();
  });

  ServicoPerfilPublicoFake perfilFake() =>
      RotasTrato.repos.perfilPublico! as ServicoPerfilPublicoFake;

  group('papel e tabela de telas (dados)', () {
    test('papel: profissional, cliente, ausente ou inválido', () {
      Map<String, dynamic> d(Object? papel) => {
            'tela': 'pedido',
            'pedido_id': _uuid,
            if (papel != null) 'papel': papel,
          };
      expect(resultadoDoPush(d('profissional')).papel, 'profissional');
      expect(resultadoDoPush(d('cliente')).papel, 'cliente');
      expect(resultadoDoPush(d(null)).papel, isNull,
          reason: 'ausente = modo atual');
      expect(resultadoDoPush(d('admin')).papel, isNull);
      expect(resultadoDoPush(d(5)).papel, isNull);
    });

    test(
        'pedido_aberto abre o pedido aberto, avaliacao a avaliação, mensagens o chat',
        () {
      expect(
          resultadoDoPush({'tela': 'pedido_aberto', 'pedido_id': _uuid})
              .destino,
          DestinoApp.pedidoAberto);
      expect(resultadoDoPush({'tela': 'avaliacao', 'pedido_id': _uuid}).destino,
          DestinoApp.avaliacao);
      expect(resultadoDoPush({'tela': 'mensagens', 'pedido_id': _uuid}).destino,
          DestinoApp.chat);
      expect(resultadoDoPush({'tela': 'indique-e-ganhe'}).destino,
          DestinoApp.indicacoes);
    });

    Notificacao caixa(
            {String? tela,
            String? tipoApi,
            String? papel,
            TipoNotificacao? tipo}) =>
        Notificacao(
          id: 'n1',
          tipo: tipo ?? TipoNotificacao.pedido,
          titulo: 't',
          texto: 'x',
          quando: 'agora',
          destinoId: _uuid,
          tela: tela,
          tipoApi: tipoApi,
          papel: papel,
        );

    test('caixa: usa data.tela; sem ela, deduz do tipo do evento', () {
      ResultadoLink? r(Notificacao n) =>
          RotasTrato.destinoDaCaixa(n, modoAtualProfissional: true);
      expect(r(caixa(tela: 'pedido_aberto'))!.destino, DestinoApp.pedidoAberto);
      expect(r(caixa(tipoApi: 'pedido.direcionado'))!.destino,
          DestinoApp.pedidoAberto);
      expect(r(caixa(tipoApi: 'pedido.urgente'))!.destino,
          DestinoApp.pedidoAberto);
      expect(r(caixa(tipoApi: 'avaliacao.recebida'))!.destino,
          DestinoApp.avaliacao);
      expect(
          r(caixa(tela: 'pedido', tipoApi: 'execucao.cliente_confirmou'))!
              .destino,
          DestinoApp.pedido);
      expect(r(caixa(tela: 'pedido', papel: 'profissional'))!.papel,
          'profissional');
      // O retrabalho continua abrindo a tela própria dele.
      expect(
        r(caixa(
                tela: 'pedido',
                tipo: TipoNotificacao.retrabalho,
                tipoApi: 'garantia.retrabalho'))!
            .destino,
        DestinoApp.retrabalho,
      );
    });
  });

  group('navegação com o papel', () {
    Future<GlobalKey<NavigatorState>> abrir(WidgetTester t,
        {bool profissional = false, bool temPerfil = true}) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final auth = ServicoAuthFake();
      await entrarNaContaDeTeste(auth, email: 'ana@exemplo.com');
      ServicoAuthPadrao.atual = auth;
      perfilFake().definirTemPerfil(temPerfil);
      final chave = GlobalKey<NavigatorState>();
      DeepLinks.navegador = () => chave.currentState;
      DeepLinks.ligar();
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        navigatorKey: chave,
        home: Builder(builder: (c) {
          if (profissional) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => RotasTrato.irParaProfissional(c));
          }
          return profissional ? const SizedBox() : const CascaClienteTela();
        }),
      ));
      await t.pumpAndSettle();
      expect(ControladorCasca.ativa, isTrue);
      expect(ControladorCasca.souProfissional, profissional);
      return chave;
    }

    testWidgets(
        'papel profissional, app em modo cliente: troca de modo e abre o pedido aberto',
        (t) async {
      await abrir(t);
      DeepLinks.receberPush({
        'tela': 'pedido_aberto',
        'pedido_id': 'ped-1',
        'papel': 'profissional'
      });
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isTrue);
      expect(find.byType(DetalhePedidoTela), findsOneWidget,
          reason: 'o pedido aberto para orçar');
      expect(find.byType(ChatPedidoTela), findsNothing, reason: 'não o chat');
      expect(LinkPendente.atual, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'usuário SEM perfil de profissional: ignora e não abre tela de profissional',
        (t) async {
      await abrir(t, temPerfil: false);
      DeepLinks.receberPush({
        'tela': 'pedido_aberto',
        'pedido_id': 'ped-1',
        'papel': 'profissional'
      });
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isFalse);
      expect(find.byType(DetalhePedidoTela), findsNothing);
      expect(LinkPendente.atual, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'papel cliente, app em modo profissional: troca para cliente e abre o pedido',
        (t) async {
      await abrir(t, profissional: true);
      DeepLinks.receberPush(
          {'tela': 'pedido', 'pedido_id': 'srv-pintura', 'papel': 'cliente'});
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isFalse);
      expect(find.byType(PedidoExecucaoTela), findsOneWidget);
      expect(find.byType(TelaNaoEncontrada), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'SEM papel: mantém o modo atual (profissional) e abre o lado dele (P08/P12)',
        (t) async {
      await abrir(t, profissional: true);
      DeepLinks.receberPush({'tela': 'pedido_aberto', 'pedido_id': 'ped-1'});
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isTrue);
      expect(find.byType(DetalhePedidoTela), findsOneWidget);
      expect(find.byType(ChatPedidoTela), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'SEM papel, profissional: "pedido" abre o pedido dele, não o chat (P08)',
        (t) async {
      await abrir(t, profissional: true);
      DeepLinks.receberPush({'tela': 'pedido', 'pedido_id': 'srv-pintura'});
      await t.pumpAndSettle();
      expect(find.byType(PedidoExecucaoTela), findsOneWidget);
      expect(find.byType(ChatPedidoTela), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('só "mensagens" abre o chat (profissional)', (t) async {
      await abrir(t, profissional: true);
      DeepLinks.receberPush({'tela': 'mensagens', 'pedido_id': 'srv-pintura'});
      await t.pumpAndSettle();
      expect(find.byType(ChatPedidoTela), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'SEM papel, modo cliente: abre o pedido do cliente (nada de tela de profissional)',
        (t) async {
      await abrir(t);
      DeepLinks.receberPush(
          {'tela': 'pedido_aberto', 'pedido_id': 'srv-pintura'});
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isFalse);
      expect(find.byType(DetalhePedidoTela), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'toque em segundo plano (profissional em modo cliente) navega (P10)',
        (t) async {
      await abrir(t);
      final aberta = StreamController<MensagemPush>.broadcast();
      final servico = ServicoToquePush(
        garantirFirebase: () async => true,
        mensagemInicial: () async => null,
        aoAbrirPeloToque: () => aberta.stream,
        aoChegarComAppAberto: () => const Stream.empty(),
        consumo: _Memoria(),
      );
      await servico.ligar(
          aoToque: (m) => DeepLinks.receberPush(m.dados), aoChegar: (_) {});
      aberta.add(const MensagemPush(
        id: 'm9',
        dados: {
          'tela': 'pedido_aberto',
          'pedido_id': 'ped-1',
          'papel': 'profissional'
        },
      ));
      await t.pumpAndSettle();
      expect(find.byType(DetalhePedidoTela), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'caixa de notificações com papel de outro modo também troca de modo',
        (t) async {
      await abrir(t);
      final r = resultadoDoPush({
        'tela': 'pedido_aberto',
        'pedido_id': 'ped-1',
        'papel': 'profissional'
      });
      final ctx = t.element(find.byType(CascaClienteTela));
      DeepLinks.abrirDaCaixa(ctx, r, profissional: false);
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isTrue);
      expect(find.byType(DetalhePedidoTela), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('consumo único (P11: cold start com tela "Ops" de rota velha)', () {
    test('a mensagem inicial do push navega uma vez, mesmo entregue de novo',
        () async {
      final memoria = _Memoria();
      var toques = 0;
      ServicoToquePush novo() => ServicoToquePush(
            garantirFirebase: () async => true,
            mensagemInicial: () async => const MensagemPush(
                id: 'm1', dados: {'tela': 'pedido', 'pedido_id': 'a'}),
            aoAbrirPeloToque: () => const Stream.empty(),
            aoChegarComAppAberto: () => const Stream.empty(),
            consumo: memoria,
          );
      await novo().ligar(aoToque: (_) => toques++, aoChegar: (_) {});
      expect(toques, 1);
      // App reaberto pelos recentes: o sistema devolve a mesma mensagem.
      await novo().ligar(aoToque: (_) => toques++, aoChegar: (_) {});
      expect(toques, 1, reason: 'já consumida');
      expect(memoria.ids, {'m1'});
    });

    test('mensagem sem id sempre é tratada; um id novo também', () async {
      final memoria = _Memoria()..ids.add('velha');
      var toques = 0;
      for (final m in [
        const MensagemPush(dados: {'tela': 'pedido'}),
        const MensagemPush(id: 'nova', dados: {'tela': 'pedido'}),
      ]) {
        await ServicoToquePush(
          garantirFirebase: () async => true,
          mensagemInicial: () async => m,
          aoAbrirPeloToque: () => const Stream.empty(),
          aoChegarComAppAberto: () => const Stream.empty(),
          consumo: memoria,
        ).ligar(aoToque: (_) => toques++, aoChegar: (_) {});
      }
      expect(toques, 2);
    });

    testWidgets('o link inicial do app é lido uma vez por processo', (t) async {
      t.platformDispatcher.defaultRouteNameTestValue =
          'br.com.feitolabs.trato://pedido/$_uuid';
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      DeepLinks.navegador =
          () => null; // sem navegador: o destino fica guardado
      DeepLinks.ligar();
      expect(LinkPendente.atual, isNotNull, reason: 'tratado na partida');
      LinkPendente.limpar(); // abriu e foi consumido
      DeepLinks.ligar(); // não lê o mesmo endereço de novo
      expect(LinkPendente.atual, isNull);
    });
  });
}
