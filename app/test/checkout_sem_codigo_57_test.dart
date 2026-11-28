// Termos 5.7: notificação `pagamento.checkout_sem_codigo` (push e caixa) abre o detalhe do pedido
// no modo cliente, inclusive a partir do modo profissional ou quando chega só `pedido_id`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/linha_do_tempo.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/comuns/aviso_push.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/navegacao_casca.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';
import 'apoio/fontes.dart';

const _esperado = ResultadoLink.valido(DestinoApp.pedido, 'ped-57', papel: 'cliente');

class _PedidoEmConfirmacao extends RepositorioPedidosFake {
  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => const PedidoEmExecucao(
        numero: '#C57',
        titulo: 'Troca de torneira',
        etapas: [
          EtapaLinhaDoTempo(titulo: 'Contratado', detalhe: '', estado: EstadoEtapa.feita),
          EtapaLinhaDoTempo(
            titulo: 'Aguardando sua confirmação',
            detalhe: '',
            estado: EstadoEtapa.atual,
          ),
          EtapaLinhaDoTempo(titulo: 'Finalizado', detalhe: '', estado: EstadoEtapa.futura),
        ],
        fotos: [],
        estadoApi: 'em_confirmacao',
        podeVerConclusao: true,
      );
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

  Future<GlobalKey<NavigatorState>> abrirApp(
    WidgetTester t, {
    required bool profissional,
  }) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    RotasTrato.repos = repositoriosDemo(pedidos: _PedidoEmConfirmacao());
    final auth = ServicoAuthFake();
    await entrarNaContaDeTeste(auth, email: 'ana@exemplo.com');
    ServicoAuthPadrao.atual = auth;
    (RotasTrato.repos.perfilPublico! as ServicoPerfilPublicoFake).definirTemPerfil(true);
    final chave = GlobalKey<NavigatorState>();
    DeepLinks.navegador = () => chave.currentState;
    DeepLinks.ligar();
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      navigatorKey: chave,
      home: Builder(builder: (c) {
        if (profissional) {
          WidgetsBinding.instance.addPostFrameCallback((_) => RotasTrato.irParaProfissional(c));
        }
        return profissional ? const SizedBox() : const CascaClienteTela();
      }),
    ));
    await t.pumpAndSettle();
    expect(ControladorCasca.souProfissional, profissional);
    return chave;
  }

  test('push pagamento.checkout_sem_codigo: completo, só pedido_id, inválido e sem id', () {
    expect(
      resultadoDoPush({
        'evento': 'pagamento.checkout_sem_codigo',
        'tela': 'pedido',
        'link': 'trato://pedido/ped-57',
        'papel': 'cliente',
        'pedido_id': 'ped-57',
      }),
      _esperado,
    );
    expect(
      resultadoDoPush({
        'evento': 'pagamento.checkout_sem_codigo',
        'pedido_id': 'ped-57',
      }),
      _esperado,
    );
    expect(
      resultadoDoPush({
        'evento': 'pagamento.checkout_sem_codigo',
        'pedido_id': '../invalido',
      }),
      const ResultadoLink.invalido(DestinoApp.pedido, papel: 'cliente'),
    );
    expect(
      resultadoDoPush({'evento': 'pagamento.checkout_sem_codigo'}),
      ResultadoLink.ignorado,
    );
  });

  for (final profissional in [false, true]) {
    test('caixa pagamento.checkout_sem_codigo: completo e só pedido_id (prof: $profissional)', () {
      final completo = Notificacao(
        id: 'n1',
        tipo: tipoDaNotificacao('pagamento.checkout_sem_codigo'),
        tipoApi: 'pagamento.checkout_sem_codigo',
        destinoId: 'ped-57',
        tela: 'pedido',
        papel: 'cliente',
        titulo: 'Confirme a conclusão',
        texto: 'Check-out sem Código Final.',
        quando: 'agora',
      );
      final soPedidoId = Notificacao(
        id: 'n2',
        tipo: tipoDaNotificacao('pagamento.checkout_sem_codigo'),
        tipoApi: 'pagamento.checkout_sem_codigo',
        destinoId: 'ped-57',
        titulo: 'Confirme a conclusão',
        texto: 'Check-out sem Código Final.',
        quando: 'agora',
      );
      expect(RotasTrato.destinoDaCaixa(completo, modoAtualProfissional: profissional), _esperado);
      expect(RotasTrato.destinoDaCaixa(soPedidoId, modoAtualProfissional: profissional), _esperado);
    });
  }

  testWidgets('push no modo cliente abre detalhe do pedido no modo cliente', (t) async {
    await abrirApp(t, profissional: false);
    DeepLinks.receberPush({
      'evento': 'pagamento.checkout_sem_codigo',
      'tela': 'pedido',
      'link': 'trato://pedido/ped-57',
      'papel': 'cliente',
      'pedido_id': 'ped-57',
    });
    await t.pumpAndSettle();
    expect(ControladorCasca.souProfissional, isFalse);
    final tela = t.widget<PedidoExecucaoTela>(find.byType(PedidoExecucaoTela));
    expect(tela.comoProfissional, isFalse);
    expect(find.text('Troca de torneira'), findsOneWidget);
  });

  testWidgets('push no modo profissional (completo) troca para cliente e abre o pedido', (t) async {
    await abrirApp(t, profissional: true);
    DeepLinks.receberPush({
      'evento': 'pagamento.checkout_sem_codigo',
      'tela': 'pedido',
      'link': 'trato://pedido/ped-57',
      'papel': 'cliente',
      'pedido_id': 'ped-57',
    });
    await t.pumpAndSettle();
    expect(ControladorCasca.souProfissional, isFalse);
    final tela = t.widget<PedidoExecucaoTela>(find.byType(PedidoExecucaoTela));
    expect(tela.comoProfissional, isFalse);
    expect(find.text('Troca de torneira'), findsOneWidget);
  });

  testWidgets('push no modo profissional só com pedido_id troca para cliente e abre o pedido',
      (t) async {
    await abrirApp(t, profissional: true);
    DeepLinks.receberPush({
      'evento': 'pagamento.checkout_sem_codigo',
      'pedido_id': 'ped-57',
    });
    await t.pumpAndSettle();
    expect(ControladorCasca.souProfissional, isFalse);
    final tela = t.widget<PedidoExecucaoTela>(find.byType(PedidoExecucaoTela));
    expect(tela.comoProfissional, isFalse);
    expect(find.text('Troca de torneira'), findsOneWidget);
  });

  for (final (rotulo, aviso) in [
    (
      'completo',
      Notificacao(
        id: 'n1',
        tipo: tipoDaNotificacao('pagamento.checkout_sem_codigo'),
        tipoApi: 'pagamento.checkout_sem_codigo',
        destinoId: 'ped-57',
        tela: 'pedido',
        papel: 'cliente',
        titulo: 'Confirme a conclusão',
        texto: 'Check-out sem Código Final.',
        quando: 'agora',
      ),
    ),
    (
      'só pedido_id',
      Notificacao(
        id: 'n2',
        tipo: tipoDaNotificacao('pagamento.checkout_sem_codigo'),
        tipoApi: 'pagamento.checkout_sem_codigo',
        destinoId: 'ped-57',
        titulo: 'Confirme a conclusão',
        texto: 'Check-out sem Código Final.',
        quando: 'agora',
      ),
    ),
  ]) {
    testWidgets('caixa no modo profissional ($rotulo) troca para cliente e abre o pedido',
        (t) async {
      final chave = await abrirApp(t, profissional: true);
      final r = RotasTrato.destinoDaCaixa(aviso, modoAtualProfissional: true);
      expect(r, _esperado);
      DeepLinks.abrirDaCaixa(chave.currentContext!, r!, profissional: true);
      await t.pumpAndSettle();
      expect(ControladorCasca.souProfissional, isFalse);
      final tela = t.widget<PedidoExecucaoTela>(find.byType(PedidoExecucaoTela));
      expect(tela.comoProfissional, isFalse);
      expect(find.text('Troca de torneira'), findsOneWidget);
    });
  }
}
