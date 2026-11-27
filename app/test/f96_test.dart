import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/linha_do_tempo.dart';
import 'package:trato/componentes/tela_nao_encontrada.dart';
import 'package:trato/dispositivo/toque_push.dart';
import 'package:trato/main.dart' show TratoApp;
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/comuns/aviso_push.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/navegacao_casca.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';
import 'apoio/fontes.dart';

const _link =
    'br.com.feitolabs.trato://recorrencia/00000000-0000-0000-0000-000000000000';

/// Um pedido aguardando o cliente confirmar, com os textos que a API monta para o CLIENTE.
class _PedidoEmConfirmacao extends RepositorioPedidosFake {
  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async =>
      const PedidoEmExecucao(
        numero: '#F40A',
        titulo: 'Confirme o serviço',
        etapas: [
          EtapaLinhaDoTempo(
              titulo: 'Contratado', detalhe: '', estado: EstadoEtapa.feita),
          EtapaLinhaDoTempo(
              titulo: 'Aguardando sua confirmação',
              detalhe: '',
              estado: EstadoEtapa.atual),
          EtapaLinhaDoTempo(
              titulo: 'Finalizado', detalhe: '', estado: EstadoEtapa.futura),
        ],
        fotos: [],
        estadoApi: 'em_confirmacao',
        podeVerConclusao: true,
      );
}

class _Rotas extends NavigatorObserver {
  final nomes = <String?>[];
  var empilhadas = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    empilhadas++;
    nomes.add(route.settings.name);
  }
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() {
    ligarDemoNosTestes();
    DeepLinks.reiniciarParaTeste();
    ControladorCasca.aoCascaPronta = DeepLinks.aoCascaPronta;
    DeepLinks.esperaDaTroca = const Duration(seconds: 6);
  });
  tearDown(() {
    DeepLinks.reiniciarParaTeste();
    DeepLinks.navegador = () => null;
    AvisoPush.esconder();
    RotasTrato.repos = repositoriosDemo();
  });

  Future<(GlobalKey<NavigatorState>, _Rotas)> abrir(WidgetTester t,
      {bool profissional = false, bool antesDoApp = false}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final auth = ServicoAuthFake();
    await entrarNaContaDeTeste(auth, email: 'ana@exemplo.com');
    ServicoAuthPadrao.atual = auth;
    (RotasTrato.repos.perfilPublico! as ServicoPerfilPublicoFake)
        .definirTemPerfil(true);
    final chave = GlobalKey<NavigatorState>();
    final obs = _Rotas();
    DeepLinks.navegador = () => chave.currentState;
    DeepLinks.ligar();
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      navigatorKey: chave,
      navigatorObservers: [obs],
      home: Builder(builder: (c) {
        if (profissional) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => RotasTrato.irParaProfissional(c));
        }
        return profissional ? const SizedBox() : const CascaClienteTela();
      }),
    ));
    await t.pumpAndSettle();
    expect(ControladorCasca.souProfissional, profissional);
    return (chave, obs);
  }

  group('P12: o `papel` decide a tela (cadeia real do push e do sino)', () {
    testWidgets(
        'casca em modo CLIENTE + papel=profissional + tela=pedido: tela do PROFISSIONAL',
        (t) async {
      RotasTrato.repos = repositoriosDemo(pedidos: _PedidoEmConfirmacao());
      await abrir(t);
      DeepLinks.receberPush(
          {'tela': 'pedido', 'pedido_id': 'ped-1', 'papel': 'profissional'});
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isTrue,
          reason: 'a casca foi sincronizada');
      expect(find.byType(PedidoExecucaoTela), findsOneWidget);
      // Texto exclusivo do profissional; nada de "sua confirmação" nem "Confirme o serviço".
      expect(find.text('Aguardando a confirmação do cliente'), findsOneWidget);
      expect(find.text('Aguardando sua confirmação'), findsNothing);
      expect(find.text('Confirme o serviço'), findsNothing);
      expect(find.text('Confirmar serviço'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('o mesmo pelo SINO (caixa de notificações, dados.papel)',
        (t) async {
      RotasTrato.repos = repositoriosDemo(pedidos: _PedidoEmConfirmacao());
      await abrir(t);
      const n = Notificacao(
        id: 'n1',
        tipo: TipoNotificacao.pedido,
        titulo: 'Orçamento aceito',
        texto: 'x',
        quando: 'agora',
        destinoId: 'ped-1',
        tela: 'pedido',
        papel: 'profissional',
        tipoApi: 'orcamento.aceito',
      );
      final r = RotasTrato.destinoDaCaixa(n, modoAtualProfissional: false)!;
      expect(r.papel, 'profissional');
      DeepLinks.abrirDaCaixa(t.element(find.byType(CascaClienteTela)), r,
          profissional: false);
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isTrue);
      expect(find.text('Aguardando a confirmação do cliente'), findsOneWidget);
      expect(find.text('Aguardando sua confirmação'), findsNothing);
    });

    testWidgets(
        'casca já PROFISSIONAL + papel=profissional: abre direto, sem trocar',
        (t) async {
      RotasTrato.repos = repositoriosDemo(pedidos: _PedidoEmConfirmacao());
      await abrir(t, profissional: true);
      DeepLinks.receberPush(
          {'tela': 'pedido', 'pedido_id': 'ped-1', 'papel': 'profissional'});
      await t.pumpAndSettle();
      expect(find.text('Aguardando a confirmação do cliente'), findsOneWidget);
    });

    testWidgets(
        'papel=cliente (casca profissional): tela do cliente, com o texto dele',
        (t) async {
      RotasTrato.repos = repositoriosDemo(pedidos: _PedidoEmConfirmacao());
      await abrir(t, profissional: true);
      DeepLinks.receberPush(
          {'tela': 'pedido', 'pedido_id': 'ped-1', 'papel': 'cliente'});
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isFalse);
      expect(find.text('Aguardando sua confirmação'), findsOneWidget);
      expect(find.text('Aguardando a confirmação do cliente'), findsNothing);
    });

    testWidgets(
        'a casca do outro modo não aparece: abre no modo do papel mesmo assim (limite)',
        (t) async {
      RotasTrato.repos = repositoriosDemo(pedidos: _PedidoEmConfirmacao());
      await abrir(t);
      DeepLinks.esperaDaTroca = const Duration(milliseconds: 200);
      // Simula a casca nova que nunca avisa que ficou pronta.
      ControladorCasca.aoCascaPronta = null;
      DeepLinks.receberPush(
          {'tela': 'pedido', 'pedido_id': 'ped-1', 'papel': 'profissional'});
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text('Aguardando a confirmação do cliente'), findsOneWidget,
          reason: 'o papel manda, não o estado da casca');
      expect(LinkPendente.atual, isNull);
    });

    testWidgets(
        'pedido direto (pedido_aberto, papel=profissional) já é tratado',
        (t) async {
      await abrir(t);
      DeepLinks.receberPush({
        'tela': 'pedido_aberto',
        'pedido_id': 'ped-1',
        'papel': 'profissional'
      });
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isTrue);
      expect(find.byType(ChatPedidoTela), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('P11: link velho não volta; push inicial vence; Home como fallback',
      () {
    testWidgets(
        'o destino do push que abriu o app tem prioridade sobre o link da partida',
        (t) async {
      t.platformDispatcher.defaultRouteNameTestValue = _link;
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      // Partida: o endereço velho fica esperando a casca…
      DeepLinks.navegador = () => null;
      DeepLinks.ligar();
      expect(LinkPendente.atual?.destino, DestinoApp.recorrencia);
      // …e a mensagem que abriu o app chega primeiro como inicial.
      final servico = ServicoToquePush(
        garantirFirebase: () async => true,
        mensagemInicial: () async => const MensagemPush(
            id: 'm1', dados: {'tela': 'mensagens', 'pedido_id': 'srv-pintura'}),
        aoAbrirPeloToque: () => const Stream.empty(),
        aoChegarComAppAberto: () => const Stream.empty(),
        consumo: _Memoria(),
      );
      await servico.ligar(
        aoToque: (m) => DeepLinks.receberPush(m.dados),
        aoChegar: (_) {},
        aoInicial: (m) => DeepLinks.receberPush(m.dados, inicial: true),
      );
      expect(LinkPendente.atual?.destino, DestinoApp.chat,
          reason: 'o push substituiu o link');

      final auth = ServicoAuthFake();
      await entrarNaContaDeTeste(auth, email: 'ana@exemplo.com');
      ServicoAuthPadrao.atual = auth;
      final chave = GlobalKey<NavigatorState>();
      DeepLinks.navegador = () => chave.currentState;
      await t.pumpWidget(MaterialApp(
          theme: TemaTrato.claro,
          navigatorKey: chave,
          home: const CascaClienteTela()));
      await t.pumpAndSettle();
      expect(find.byType(ChatPedidoTela), findsOneWidget);
      expect(find.byType(TelaNaoEncontrada), findsNothing,
          reason: 'nada de "Ops" de rota velha');
    });

    testWidgets(
        'link inexistente: a tela de erro não é restaurável (rota sem nome)',
        (t) async {
      final (_, obs) = await abrir(t);
      DeepLinks.receber(Uri.parse(_link));
      await t.pumpAndSettle();
      // O destino abriu por um push de rota ANÔNIMA: nada para o Android/Flutter restaurar.
      expect(obs.nomes.last, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'o app não liga restauração de estado (restorationScopeId nulo)',
        (t) async {
      await t.pumpWidget(const TratoApp());
      final app = t.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.restorationScopeId, isNull);
      expect(app.onGenerateInitialRoutes, isNotNull,
          reason:
              'a rota inicial do engine (o link) nunca vira tela por conta própria');
    });

    testWidgets('"Voltar ao início" na tela de erro leva à Home', (t) async {
      await abrir(t);
      DeepLinks.receber(Uri.parse(_link));
      await t.pumpAndSettle();
      expect(find.byType(TelaNaoEncontrada), findsOneWidget);
      await t.tap(find.text('Voltar ao início'));
      await t.pumpAndSettle();
      expect(find.byType(TelaNaoEncontrada), findsNothing);
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets(
        'consumo único: o endereço da partida é lido uma vez por processo',
        (t) async {
      t.platformDispatcher.defaultRouteNameTestValue = _link;
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      DeepLinks.navegador = () => null;
      DeepLinks.ligar();
      expect(LinkPendente.atual, isNotNull);
      LinkPendente.limpar();
      DeepLinks.ligar();
      expect(LinkPendente.atual, isNull);
    });
  });

  group('aviso em primeiro plano (overlay)', () {
    testWidgets(
        'no modo PROFISSIONAL fica ~5 s mesmo com a casca recarregando, e "Abrir" toca',
        (t) async {
      final (chave, obs) = await abrir(t, profissional: true);
      AvisoPush.mostrar(
        const MensagemPush(
            titulo: 'Novo pedido',
            corpo: 'Perto de você',
            dados: {
              'tela': 'pedido_aberto',
              'pedido_id': 'ped-1',
              'papel': 'profissional'
            }),
        navegador: () => chave.currentState,
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Novo pedido'), findsOneWidget);
      // A casca se refaz várias vezes (o início recarrega sozinho).
      for (var i = 0; i < 4; i++) {
        RotasTrato.pedidosMudaram.value++;
        await t.pump(const Duration(seconds: 1));
        expect(find.text('Novo pedido'), findsOneWidget,
            reason: 'segundo ${i + 1}');
      }
      final antes = obs.empilhadas;
      await t.tap(find.byKey(const Key('aviso-push-abrir')));
      await t.pumpAndSettle();
      expect(obs.empilhadas, greaterThan(antes),
          reason: 'o botão Abrir navega');
      expect(find.text('Novo pedido'), findsNothing);
    });

    testWidgets('some sozinho depois de 5 s', (t) async {
      final (chave, _) = await abrir(t, profissional: true);
      AvisoPush.mostrar(
          const MensagemPush(
              titulo: 'Oi', dados: {'tela': 'pedido', 'pedido_id': 'a'}),
          navegador: () => chave.currentState);
      await t.pump();
      await t.pump(const Duration(seconds: 4));
      expect(find.text('Oi'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('Oi'), findsNothing);
    });
  });
}

class _Memoria implements RegistroDeConsumo {
  final ids = <String>{};
  @override
  Future<bool> jaConsumido(String id) async => ids.contains(id);
  @override
  Future<void> marcar(String id) async => ids.add(id);
}
