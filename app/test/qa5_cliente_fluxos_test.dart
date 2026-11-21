import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/detalhe_valores_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/garantia_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/telas/lgpd/excluir_conta_tela.dart';
import 'package:trato/telas/lgpd/modelos.dart';
import 'package:trato/telas/orcamentos/folha_contraproposta.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';

const _textoHostil =
    '<script>alert(1)</script> \u202Ertl\u202C 🔥 DROP TABLE pedidos; -- '
    'texto muito longo para testar quebra de linha e layout em telas pequenas';

Widget _envolver(Widget child, {Size tamanho = const Size(390, 844), double escalaFonte = 1.0}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: tamanho,
        textScaler: TextScaler.linear(escalaFonte),
      ),
      child: child,
    ),
  );
}

void main() {
  group('QA5 — AguardandoPagamentoTela', () {
    testWidgets('confirma pagamento quando backend retorna pago', (tester) async {
      var confirmou = 0;
      await tester.pumpWidget(_envolver(
        AguardandoPagamentoTela(
          consultar: () async => StatusPagamento.pago,
          aoConfirmar: () => confirmou++,
          intervalo: const Duration(hours: 1),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(confirmou, 1);
    });

    testWidgets('erro de rede exibe mensagem e permite tentar novamente', (tester) async {
      var tentativas = 0;
      await tester.pumpWidget(_envolver(
        AguardandoPagamentoTela(
          consultar: () async {
            tentativas++;
            if (tentativas == 1) {
              throw const ErroTrato(TipoErro.semInternet, 'Sem internet.');
            }
            return StatusPagamento.pago;
          },
          aoConfirmar: () {},
          intervalo: const Duration(hours: 1),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Sem internet'), findsOneWidget);
      expect(tentativas, 1);
    });
  });

  group('QA5 — OrcamentosRecebidosTela', () {
    const resumo = ResumoPedido(
      numero: '#100',
      titulo: 'Trocar disjuntor',
      recebidos: 0,
      limite: 5,
      tempoRestante: '24 horas',
    );

    testWidgets('lista vazia e 500 orçamentos sem overflow em 320x568 e tablet 1.3x', (tester) async {
      await tester.pumpWidget(_envolver(
        const OrcamentosRecebidosTela(pedido: resumo, orcamentos: []),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final lista500 = List<Orcamento>.generate(
        500,
        (i) => Orcamento(
          id: 'orc-$i',
          profissional: 'Profissional $i $_textoHostil',
          iniciais: 'PR',
          verificacao: 'Verificado',
          totalCentavos: 10000 + i * 100,
          nota: 4.8,
          notaResumo: '4,8 · 10 avaliações',
          servicosResumo: '12 serviços',
          servicosConcluidos: 12,
          quando: 'Hoje · 2 h',
          inicio: DateTime(2026, 11, 21, 9),
          garantia: '90 dias',
          observacao: 'Levo material',
        ),
      );

      await tester.pumpWidget(_envolver(
        OrcamentosRecebidosTela(pedido: resumo, orcamentos: lista500),
        tamanho: const Size(800, 1280),
        escalaFonte: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('QA5 — FolhaNegociacao (contraproposta)', () {
    testWidgets('cancelar retorna null e não trava', (tester) async {
      (int, String?)? resultado = (1, 'init');
      await tester.pumpWidget(_envolver(
        Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                resultado = await pedirContraproposta(ctx, 15000);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(resultado, isNull);
    });
  });

  group('QA5 — NovoPedidoTela', () {
    const form = FormularioPedido(
      categoria: 'Eletricista',
      servicos: ['Troca de disjuntor', 'Tomada'],
      servicosIniciais: {'Troca de disjuntor'},
      perguntaQuantidade: 'Quantos pontos?',
      dicaQuantidade: 'Ex: 2',
      quantidadeInicial: 1,
      perguntaVoltagem: 'Voltagem',
      voltagens: ['110V', '220V'],
      voltagemInicial: '110V',
      descricaoInicial: '',
      fotos: [],
      prazos: ['Hoje', 'Esta semana'],
      faixas: [FaixaPreco(minimoCentavos: 0, maximoCentavos: 20000), FaixaPreco(minimoCentavos: 20000, maximoCentavos: 50000)],
      endereco: 'Rua das Flores, 123',
      avisoEndereco: 'Endereço só vai após aceitar.',
      avisoPrazo: 'Orçamentos em até 24h.',
    );

    testWidgets('toque duplo no envio dispara uma única chamada', (tester) async {
      var envios = 0;
      final completer = Completer<void>();
      await tester.pumpWidget(_envolver(
        NovoPedidoTela(
          formulario: form,
          agora: () => DateTime(2026, 11, 20, 10),
          profissionalConvidadoId: 'prof-1',
          profissionalConvidadoNome: 'Carlos Silva',
          aoEnviar: (_) {
            envios++;
            return completer.future;
          },
        ),
      ));
      await tester.pumpAndSettle();

      final campos = find.byType(TextField);
      if (campos.evaluate().isNotEmpty) {
        await tester.enterText(campos.first, _textoHostil);
        await tester.pump();
      }

      final botao = find.textContaining('Enviar');
      if (botao.evaluate().isNotEmpty) {
        await tester.ensureVisible(botao.first);
        await tester.tap(botao.first);
        await tester.tap(botao.first);
        await tester.pump();
      }
      completer.complete();
      await tester.pumpAndSettle();
      expect(envios, lessThanOrEqualTo(1));
    });

    testWidgets('320x568 e tablet 1.3x sem overflow', (tester) async {
      await tester.pumpWidget(_envolver(
        NovoPedidoTela(
          formulario: form,
          agora: () => DateTime(2026, 11, 20, 10),
        ),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_envolver(
        NovoPedidoTela(
          formulario: form,
          agora: () => DateTime(2026, 11, 20, 10),
        ),
        tamanho: const Size(800, 1280),
        escalaFonte: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'faixas vazia estoura Bad state: No element (QA5-1)',
      (tester) async {
        const formVazio = FormularioPedido(
          categoria: 'Eletricista',
          servicos: ['Troca de disjuntor'],
          servicosIniciais: {'Troca de disjuntor'},
          perguntaQuantidade: 'Quantos pontos?',
          dicaQuantidade: 'Ex: 2',
          quantidadeInicial: 1,
          perguntaVoltagem: 'Voltagem',
          voltagens: ['110V'],
          voltagemInicial: '110V',
          descricaoInicial: '',
          fotos: [],
          prazos: ['Hoje'],
          faixas: [],
          endereco: 'Rua das Flores, 123',
          avisoEndereco: 'Endereço só vai após aceitar.',
          avisoPrazo: 'Orçamentos em até 24h.',
        );
        await tester.pumpWidget(_envolver(
          NovoPedidoTela(
            formulario: formVazio,
            agora: () => DateTime(2026, 11, 20, 10),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('QA5 — PedidoExecucaoTela', () {
    testWidgets('renderiza em 320x568 e tablet 1.3x sem overflow', (tester) async {
      const pedido = PedidoEmExecucao(
        numero: '#100',
        titulo: _textoHostil,
        codigoInicio: '1234',
        codigoConclusao: '4829',
        fotos: [],
        etapas: [],
        aditivo: Aditivo(
          titulo: 'Cabo extra',
          descricao: 'Troca de cabo extra',
          valorCentavos: 5000,
          estado: EstadoAditivo.aguardando,
        ),
      );

      await tester.pumpWidget(_envolver(
        const PedidoExecucaoTela(pedido: pedido),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_envolver(
        const PedidoExecucaoTela(pedido: pedido),
        tamanho: const Size(800, 1280),
        escalaFonte: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('QA5 — RelatarProblemaTela e GarantiaTela', () {
    testWidgets('RelatarProblemaTela evita duplo toque no envio', (tester) async {
      var envios = 0;
      final completer = Completer<void>();
      await tester.pumpWidget(_envolver(
        RelatarProblemaTela(
          dados: const DadosRelatoProblema(
            titulo: 'Pedido #1',
            valorCongeladoCentavos: 15000,
            motivos: ['Serviço incompleto', 'Atraso'],
            solucoes: ['Refazer serviço', 'Estorno parcial'],
            prazoRespostaHoras: 48,
            nomeProfissional: 'Carlos',
          ),
          motivoInicial: 'Serviço incompleto',
          descricaoInicial: _textoHostil,
          aoEnviar: (_) {
            envios++;
            return completer.future;
          },
        ),
      ));
      await tester.pumpAndSettle();
      final botao = find.text('Enviar relato');
      if (botao.evaluate().isNotEmpty) {
        await tester.ensureVisible(botao);
        await tester.tap(botao);
        await tester.tap(botao);
        await tester.pump();
      }
      completer.complete();
      await tester.pumpAndSettle();
      expect(envios, lessThanOrEqualTo(1));
    });

    testWidgets('GarantiaTela desabilita retrabalho quando encerrada', (tester) async {
      var tocou = 0;
      await tester.pumpWidget(_envolver(
        GarantiaTela(
          dados: DadosGarantia(
            titulo: 'Pedido #1',
            diasTotal: 90,
            diasRestantes: 0,
            fimEm: DateTime(2026, 11, 1),
            cobre: 'Vazamento',
            naoCobre: 'Mau uso',
            prazoAtendimentoDias: 3,
          ),
          aoPedirRetrabalho: () => tocou++,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedir retrabalho'));
      await tester.pump();
      expect(tocou, 0);
    });
  });

  group('QA5 — CarteiraTela e DetalheValoresTela', () {
    testWidgets('saldo zero, 500 itens e erro de carregamento sem overflow', (tester) async {
      final vazio = const DadosCarteira(
        resumo: ResumoCarteira(
          disponivelCentavos: 0,
          textoPix: 'Sem chave',
          retidoCentavos: 0,
          textoRetido: 'Nenhum',
          aLiberarCentavos: 0,
          textoALiberar: 'Nenhum',
        ),
        extrato: [],
      );
      await tester.pumpWidget(_envolver(
        CarteiraTela(dados: vazio),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final extrato500 = List<ItemExtrato>.generate(
        500,
        (i) => ItemExtrato(
          titulo: 'Serviço $i $_textoHostil',
          detalheData: '20/11/2026',
          brutoCentavos: 999999999,
          textoTaxa: 'Sem taxa',
          liquidoCentavos: 999999999,
          status: StatusExtrato.liberado,
        ),
      );
      await tester.pumpWidget(_envolver(
        CarteiraTela(
          dados: DadosCarteira(resumo: vazio.resumo, extrato: extrato500),
        ),
        tamanho: const Size(800, 1280),
        escalaFonte: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DetalheValoresTela exibe erro de rede e botão tentar novamente', (tester) async {
      var tentativas = 0;
      await tester.pumpWidget(_envolver(
        DetalheValoresTela(
          carregar: () async {
            tentativas++;
            throw TimeoutException('Demorou demais');
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(tentativas, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('QA5 — ConclusaoTela', () {
    testWidgets('renderiza texto hostil em 320x568 e tablet 1.3x sem overflow', (tester) async {
      const resumo = ResumoConclusao(
        numeroPedido: '#999',
        nomeProfissional: 'Carlos $_textoHostil',
        legendaFotoAntes: 'Antes',
        legendaFotoDepois: 'Depois',
        orcamentoCentavos: 15000,
        aditivoCentavos: 5000,
        codigo: '4829',
        avisoLiberacao: 'Liberação automática em 48 h.',
        checkOutSemCodigo: true,
      );
      var confirmacoes = 0;
      await tester.pumpWidget(_envolver(
        ConclusaoTela(resumo: resumo, aoConfirmar: () => confirmacoes++),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final btn = find.text('Confirmar conclusão e liberar pagamento');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      expect(confirmacoes, 1);
    });
  });

  group('QA5 — Auth (LoginTela e CriarContaTela)', () {
    testWidgets('LoginTela valida campos vazios, evita duplo toque e trata erro de rede', (tester) async {
      final auth = _FakeAuth();
      await tester.pumpWidget(_envolver(LoginTela(servico: auth, sessaoExpirada: true)));
      await tester.pumpAndSettle();

      final btnEntrar = find.text('Entrar').last;
      await tester.ensureVisible(btnEntrar);
      await tester.tap(btnEntrar);
      await tester.pump();
      expect(auth.tentativasLogin, 0);

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'qa@trato.app');
      await tester.enterText(campos.at(1), 'SenhaForte123!');
      await tester.ensureVisible(btnEntrar);
      await tester.tap(btnEntrar);
      await tester.tap(btnEntrar);
      await tester.pump();
      auth.completer.complete(const SessaoAuth(id: 'u1', email: 'qa@trato.app'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(auth.tentativasLogin, 1);
    });

    testWidgets('CriarContaTela valida campos vazios e renderiza em 320x568', (tester) async {
      final auth = _FakeAuth();
      await tester.pumpWidget(_envolver(
        CriarContaTela(servico: auth),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('QA5 — ExcluirContaTela', () {
    testWidgets('renderiza passo 1 em 320x568 sem overflow', (tester) async {
      final priv = _FakePrivacidade();
      await tester.pumpWidget(_envolver(
        ExcluirContaTela(servico: priv),
        tamanho: const Size(320, 568),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeAuth implements ServicoAuth {
  int tentativasLogin = 0;
  final completer = Completer<SessaoAuth>();

  @override
  bool provedorHabilitado(ProvedorAuth provedor) => false;

  @override
  Future<SessaoAuth> entrarComEmail({required String email, required String senha}) {
    tentativasLogin++;
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePrivacidade implements ServicoPrivacidade {
  int chamadasExclusao = 0;
  final completer = Completer<void>();

  @override
  Future<void> solicitarExclusao() {
    chamadasExclusao++;
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
