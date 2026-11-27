import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/onboarding/onboarding_tela.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/endereco_pedido.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: tela,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ServicoAuthPadrao.atual = ServicoAuthFake();
    RotasTrato.rascunhoPendente = null;
    RotasTrato.modoVisitante = false;
  });

  group('F6 — Entrada leve do Cliente', () {
    testWidgets('botão Pular no onboarding abre o início do cliente sem exigir login',
        (tester) async {
      await _abrir(tester, const OnboardingTela());

      expect(find.text('Pular'), findsOneWidget);
      await tester.tap(find.text('Pular'));
      await tester.pumpAndSettle();

      expect(find.byType(CascaClienteTela), findsOneWidget);
      expect(ServicoAuthPadrao.atual.sessaoAtual, isNull);
      expect(find.text('O que você precisa hoje?'), findsOneWidget);
    });

    testWidgets('início sem sessão carrega categorias e aba Pedidos convida a entrar',
        (tester) async {
      RotasTrato.modoVisitante = true;
      await _abrir(tester, const CascaClienteTela());

      expect(find.text('Olá'), findsOneWidget);
      expect(find.text('O que você precisa hoje?'), findsOneWidget);

      await tester.tap(find.text('Pedidos').last);
      await tester.pumpAndSettle();

      expect(find.text('Seus pedidos'), findsOneWidget);
      expect(find.text('Criar conta'), findsOneWidget);
      expect(find.text('Já tenho conta'), findsOneWidget);
    });

    testWidgets('enviar pedido sem sessão redireciona para cadastro/login preservando rascunho',
        (tester) async {
      final categoria = (await RotasTrato.repos.catalogo.categorias()).first;
      await _abrir(
        tester,
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => RotasTrato.abrirNovoPedido(
                ctx,
                categoria: categoria,
              ),
              child: const Text('Abrir pedido'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir pedido'));
      await tester.pumpAndSettle();
      expect(find.byType(NovoPedidoTela), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Trocar duas tomadas na sala');
      await preencherEnderecoDoPedido(tester);
      final enviar = find.text('Enviar pedido');
      await tester.ensureVisible(enviar.last);
      await tester.tap(enviar.last);
      await tester.pumpAndSettle();

      expect(find.text('Falta pouco para enviar seu pedido'), findsOneWidget);
      expect(RotasTrato.rascunhoPendente, isNotNull);
      expect(RotasTrato.rascunhoPendente!.descricao, 'Trocar duas tomadas na sala');

      await tester.tap(find.text('Criar conta').last);
      await tester.pumpAndSettle();

      expect(find.byType(CriarContaTela), findsOneWidget);
    });

    testWidgets('cadastro leve não exige CPF; pede a data de nascimento', (tester) async {
      final auth = ServicoAuthFake();
      await _abrir(tester, CriarContaTela(servico: auth));

      expect(find.text('CPF'), findsNothing);
      expect(find.text('Data de nascimento'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Ana Souza');
      await tester.enterText(find.byType(TextField).at(1), '15031992');
      await tester.enterText(find.byType(TextField).at(2), '31999998888');
      await tester.enterText(find.byType(TextField).at(3), 'ana@teste.com');
      await tester.enterText(find.byType(TextField).at(4), 'segredo123');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      await tester.tap(find.text('Criar conta').last);
      await tester.pumpAndSettle();

      expect(auth.sessaoAtual?.email, 'ana@teste.com');
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('pagamento pede CPF e nascimento quando cpfCadastrado == false', (tester) async {
      String? cpfSalvo;
      String? nascSalvo;
      var pagou = false;

      await _abrir(
        tester,
        PagamentoTela(
          dados: const DadosPagamento(
            subtitulo: 'Pedido #AB12',
            valorAgoraCentavos: 15000,
            cpfCadastrado: false,
            opcoes: [
              OpcaoPagamento(
                metodo: MetodoPagamento.pix,
                titulo: 'Pix',
                descricao: 'Pague via Pix',
              ),
            ],
          ),
          aoCadastrarCpf: (cpf, nasc) async {
            cpfSalvo = cpf;
            nascSalvo = nasc;
          },
          aoPagarDetalhado: (_, __, ___) async {
            pagou = true;
          },
        ),
      );

      await tester.tap(find.textContaining('Pagar R\$ 150,00'));
      await tester.pumpAndSettle();

      expect(find.text('Informe seu CPF para pagar'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '12345678909');
      await tester.enterText(find.byType(TextField).at(1), '15031990');
      await tester.tap(find.text('Continuar pagamento'));
      await tester.pumpAndSettle();

      expect(cpfSalvo, '12345678909');
      expect(nascSalvo, '1990-03-15');
      expect(pagou, isTrue);
    });

    testWidgets('pagamento pede CPF quando API retorna 422 cpf_obrigatorio', (tester) async {
      var tentativas = 0;
      String? cpfSalvo;

      await _abrir(
        tester,
        PagamentoTela(
          dados: const DadosPagamento(
            subtitulo: 'Pedido #AB12',
            valorAgoraCentavos: 15000,
            cpfCadastrado: true,
            opcoes: [
              OpcaoPagamento(
                metodo: MetodoPagamento.pix,
                titulo: 'Pix',
                descricao: 'Pague via Pix',
              ),
            ],
          ),
          aoCadastrarCpf: (cpf, _) async {
            cpfSalvo = cpf;
          },
          aoPagarDetalhado: (_, __, ___) async {
            tentativas++;
            if (tentativas == 1) {
              throw const ErroTrato(
                TipoErro.recusado,
                'CPF obrigatório',
                codigoHttp: 422,
                codigo: 'cpf_obrigatorio',
              );
            }
          },
        ),
      );

      await tester.tap(find.textContaining('Pagar R\$ 150,00'));
      await tester.pumpAndSettle();

      expect(find.text('Informe seu CPF para pagar'), findsOneWidget);
      expect(
        find.textContaining('Pedimos só uma vez, para emitir o recibo e proteger seu pagamento'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).at(0), '12345678909');
      await tester.enterText(find.byType(TextField).at(1), '15031990');
      await tester.tap(find.text('Continuar pagamento'));
      await tester.pumpAndSettle();

      expect(cpfSalvo, '12345678909');
      expect(tentativas, 2);
    });
  });
}
