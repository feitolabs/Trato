import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/detalhe_valores_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/nota_material/nota_material.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/notificacoes/servico_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

class _CheckInOffline extends ServicoCheckInFake {
  @override
  Future<ResultadoInicio> iniciarServico(
    String codigo, {
    bool semCodigo = false,
    String? justificativa,
  }) async =>
      ResultadoInicio.guardadoOffline;
}

const _dadosPagamento = DadosPagamento(
  subtitulo: 'Pedido #1',
  valorAgoraCentavos: 10000,
  opcoes: [
    OpcaoPagamento(metodo: MetodoPagamento.pix, titulo: 'Pix', descricao: 'No banco'),
    OpcaoPagamento(metodo: MetodoPagamento.cartao, titulo: 'Cartão', descricao: 'Visa'),
  ],
);

void main() {
  group('AV-1: Sem internet do check-in', () {
    Future<void> deixarOffline(WidgetTester tester) async {
      await _abrir(
        tester,
        CheckInTela(
          servico: _CheckInOffline(),
          tituloBarra: 'Mariana',
          fotoInicial: const FotoChegada(hora: '14h00'),
          distanciaInicialMetros: 20,
        ),
      );
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sem internet.'), findsOneWidget);
    }

    testWidgets('some ao voltar ao primeiro plano', (tester) async {
      await deixarOffline(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sem internet.'), findsNothing);
    });

    testWidgets('some ao tocar em outro botão', (tester) async {
      await deixarOffline(tester);
      await tester.tap(find.text('Refazer').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sem internet.'), findsNothing);
    });
  });

  group('SINO-1: abrir a lista marca tudo como lido', () {
    testWidgets('contador zera e o backend é avisado', (tester) async {
      final servico = ServicoNotificacoesFake();
      final contagens = <int>[];
      await _abrir(
        tester,
        NotificacoesTela(servico: servico, aoContarNaoLidas: contagens.add),
      );
      expect(find.text('Tudo lido'), findsOneWidget);
      expect(find.textContaining('não lida'), findsNothing);
      expect(contagens.last, 0);
    });
  });

  group('CPF-1 e B7: pagamento', () {
    testWidgets('o cartão vem selecionado, não o Pix', (tester) async {
      await _abrir(tester, const PagamentoTela(dados: _dadosPagamento));
      expect(find.textContaining('com cartão'), findsOneWidget);
    });

    testWidgets('cancelar a folha do CPF mostra a mensagem', (tester) async {
      const dados = DadosPagamento(
        subtitulo: 'Pedido #1',
        valorAgoraCentavos: 10000,
        opcoes: [
          OpcaoPagamento(metodo: MetodoPagamento.cartao, titulo: 'Cartão', descricao: 'Visa'),
        ],
        cpfCadastrado: false,
      );
      await _abrir(
        tester,
        PagamentoTela(dados: dados, aoCadastrarCpf: (cpf, nasc) async {}, aoPagar: (_) {}),
      );
      await tester.tap(find.textContaining('Pagar R'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // fecha a folha sem salvar
      await tester.pumpAndSettle();
      expect(find.text('Precisamos do seu CPF para concluir o pagamento.'), findsOneWidget);
    });

    testWidgets('o erro do cupom some ao editar o texto', (tester) async {
      await _abrir(
        tester,
        PagamentoTela(
          dados: _dadosPagamento,
          aoAplicarCupom: (c) async =>
              throw const ErroTrato(TipoErro.recusado, 'Cupom não encontrado ou inválido.'),
        ),
      );
      await tester.enterText(find.byKey(const Key('campo-cupom')), 'xx');
      await tester.tap(find.byKey(const Key('botao-aplicar-cupom')));
      await tester.pumpAndSettle();
      expect(find.text('Cupom não encontrado ou inválido.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('campo-cupom')), 'xxy');
      await tester.pumpAndSettle();
      expect(find.text('Cupom não encontrado ou inválido.'), findsNothing);
    });
  });

  group('GAN-1: regra de liberação', () {
    test('texto com e sem data', () {
      expect(
        textoRegraLiberacao(DateTime(2026, 11, 27)),
        allOf(startsWith('Libera em '), contains('48 horas para o cliente confirmar')),
      );
      expect(textoRegraLiberacao(null), startsWith('Libera após 48 horas'));
    });

    testWidgets('Carteira mostra a regra e os Tratinhos pendentes', (tester) async {
      await _abrir(
        tester,
        const CarteiraTela(
          dados: DadosCarteira(
            tratinhosPendentesTexto: 'Você tem 100 Tratinhos a liberar em 27/11',
          ),
        ),
      );
      expect(find.byKey(const Key('regra-liberacao')), findsOneWidget);
      expect(find.text('Você tem 100 Tratinhos a liberar em 27/11'), findsOneWidget);
    });

    testWidgets('Valores do pedido mostra a regra', (tester) async {
      await _abrir(
        tester,
        DetalheValoresTela(
          carregar: () async => const DetalheValoresPedido(
            pedidoNumero: '#AB12',
            pagoPeloClienteCentavos: 10000,
            voceRecebeCentavos: 10000,
            situacao: 'Retido até o cliente confirmar o serviço.',
          ),
        ),
      );
      expect(find.byKey(const ValueKey('regra-liberacao')), findsOneWidget);
    });
  });

  group('REM-3', () {
    testWidgets('lista do cliente mostra o selo Remoto só no remoto', (tester) async {
      await _abrir(
        tester,
        const SeusPedidosTela(
          emAndamento: [
            PedidoResumo(
              titulo: 'Aula',
              subtitulo: 'Pedido #1',
              statusTexto: 'Agendado',
              statusTipo: TipoStatus.info,
              remoto: true,
            ),
            PedidoResumo(
              titulo: 'Reparo',
              subtitulo: 'Pedido #2',
              statusTexto: 'Agendado',
              statusTipo: TipoStatus.info,
            ),
          ],
          finalizados: [],
        ),
      );
      expect(find.byKey(const ValueKey('selo-remoto')), findsOneWidget);
    });

    testWidgets('orçamento remoto abre em Valor fechado, sem deslocamento nem material',
        (tester) async {
      await _abrir(
        tester,
        CalculadoraOrcamentoTela(
          servico: ServicoOrcamentoFake(),
          tituloPedido: 'Aula',
          remoto: true,
        ),
      );
      expect(find.text('Valor fechado / diária'), findsOneWidget);
      expect(find.text('Por hora + deslocamento'), findsNothing);
      expect(find.text('Adicionar material'), findsNothing);
    });
  });

  group('P2', () {
    test('nota de material mostra quantidade x unitário', () {
      const item = ItemNota(descricao: 'Parafuso', quantidade: 2, valorUnitarioCentavos: 1000);
      expect(
        item.rotuloComConta((c) => 'R\$ ${c ~/ 100},00'),
        'Parafuso — 2 × R\$ 10,00 =',
      );
      const um = ItemNota(descricao: 'Cano', valorUnitarioCentavos: 500);
      expect(um.rotuloComConta((c) => '$c'), 'Cano');
    });
  });
}
