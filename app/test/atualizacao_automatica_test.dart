import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/carregador.dart';
import 'package:trato/telas/comuns/estados.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/profissional_inicio/pedidos_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

// As telas se atualizam sozinhas: orçamento novo, mensagem nova e pedido aceito aparecem sem
// fechar e abrir o app.

Widget _app(Widget filho) => MaterialApp(theme: TemaTrato.claro, home: Scaffold(body: filho));

class _ServicoQueMuda implements ServicoMensagens {
  int chamadas = 0;

  @override
  Future<List<ConversaResumo>> listar() async {
    chamadas++;
    return [
      ConversaResumo(
        pedidoId: 'p1',
        tituloPedido: 'Trocar chuveiro',
        interlocutor: 'Ana S.',
        iniciais: 'AS',
        ultimaMensagem: chamadas == 1 ? 'Oi' : 'Cheguei amanhã cedo',
        quando: '10:00',
        naoLidas: chamadas == 1 ? 0 : 1,
      ),
    ];
  }
}

void main() {
  testWidgets('Carregador: atualiza em silêncio, sem tela de carregando', (tester) async {
    var valor = 1;
    await tester.pumpWidget(
      _app(
        Carregador<int>(
          carregar: () async => valor,
          atualizarACada: const Duration(seconds: 10),
          construir: (_, v) => Text('valor $v'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('valor 1'), findsOneWidget);

    valor = 2;
    await tester.pump(const Duration(seconds: 10));
    // Nem um quadro de "carregando": o dado antigo fica até o novo chegar.
    expect(find.byType(EstadoTela), findsNothing);
    await tester.pump();
    expect(find.text('valor 2'), findsOneWidget);
    expect(find.text('valor 1'), findsNothing);
  });

  testWidgets('Carregador: falha de rede na atualização mantém o que está na tela', (tester) async {
    var falhar = false;
    await tester.pumpWidget(
      _app(
        Carregador<int>(
          carregar: () async {
            if (falhar) throw Exception('sem rede');
            return 7;
          },
          atualizarACada: const Duration(seconds: 10),
          construir: (_, v) => Text('valor $v'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    falhar = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('valor 7'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsNothing);
  });

  testWidgets('Carregador sem atualizarACada carrega só uma vez', (tester) async {
    var chamadas = 0;
    await tester.pumpWidget(
      _app(
        Carregador<int>(
          carregar: () async => ++chamadas,
          construir: (_, v) => Text('valor $v'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 5));
    expect(chamadas, 1);
  });

  testWidgets('lista de conversas mostra a mensagem nova sem reabrir a tela', (tester) async {
    final servico = _ServicoQueMuda();
    await tester.pumpWidget(
      _app(
        ListaConversas(servico: servico, atualizarACada: const Duration(seconds: 12)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Oi'), findsOneWidget);
    expect(find.text('Ana S.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    expect(find.text('Cheguei amanhã cedo'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // contador de não lidas
  });

  testWidgets('notificações novas aparecem sozinhas e o que já li continua lido', (tester) async {
    var rodada = 0;
    final servico = _ServicoNotificacoes(() {
      rodada++;
      return [
        const Notificacao(
          id: 'a',
          tipo: TipoNotificacao.mensagem,
          titulo: 'Nova mensagem',
          texto: 't',
          quando: 'agora',
        ),
        if (rodada > 1)
          const Notificacao(
            id: 'b',
            tipo: TipoNotificacao.orcamento,
            titulo: 'Novo orçamento',
            texto: 't',
            quando: 'agora',
          ),
      ];
    });
    await tester.pumpWidget(
      _app(
        NotificacoesTela(servico: servico, atualizarACada: const Duration(seconds: 12)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Novo orçamento'), findsNothing);
    expect(find.text('1 não lida'), findsOneWidget);

    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    expect(find.text('Novo orçamento'), findsOneWidget);
    expect(find.text('2 não lidas'), findsOneWidget);
  });

  testWidgets('aba Pedidos do profissional mostra o pedido aceito antes do pagamento',
      (tester) async {
    PedidoContratado? tocado;
    await tester.pumpWidget(
      _app(
        PedidosProfissionalTela(
          pedidos: const [],
          conversas: const SizedBox.shrink(),
          contratados: const [
            PedidoContratado(
              pedidoId: 'p1',
              titulo: 'Pedido #AAAA',
              situacao: 'Orçamento aceito · aguardando o pagamento do cliente',
              estadoApi: 'orcamento_aceito',
            ),
          ],
          aoAbrirContratado: (c) => tocado = c,
        ),
      ),
    );
    expect(find.text('Em andamento (1)'), findsOneWidget);

    await tester.tap(find.text('Em andamento (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido #AAAA'), findsOneWidget);
    expect(find.textContaining('aguardando o pagamento do cliente'), findsOneWidget);

    await tester.tap(find.text('Pedido #AAAA'));
    expect(tocado?.pedidoId, 'p1');
  });

  testWidgets('sem pedido aceito, a aba explica quando ele aparece', (tester) async {
    await tester.pumpWidget(
      _app(PedidosProfissionalTela(pedidos: const [], conversas: const SizedBox.shrink())),
    );
    await tester.tap(find.text('Em andamento'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum pedido em andamento'), findsOneWidget);
  });
}

class _ServicoNotificacoes implements ServicoNotificacoes {
  _ServicoNotificacoes(this._lista);

  final List<Notificacao> Function() _lista;

  @override
  Future<List<Notificacao>> listar() async => _lista();

  @override
  Future<void> marcarLida(String id) async {}

  @override
  Future<void> marcarTodasLidas() async {}
}
