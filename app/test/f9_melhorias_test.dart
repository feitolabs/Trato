import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/telas/ajuda/servico_ajuda_local.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/cliente/inicio_tela.dart';
import 'package:trato/telas/comuns/sucesso_acao_tela.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/legal/texto_legal_tela.dart';
import 'package:trato/telas/onboarding/onboarding_tela.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
import 'package:trato/telas/profissional_cadastro/cadastro.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
}

void main() {
  group('F9 — Conversão, clareza e retenção', () {
    testWidgets('1. InicioTela e OnboardingTela destacam Orçamento grátis · 0% de taxa',
        (tester) async {
      await _abrir(tester, InicioTela(aoBuscar: () {}));
      expect(find.text('Orçamento grátis · 0% de taxa'), findsOneWidget);

      await _abrir(tester, const OnboardingTela());
      expect(find.textContaining('Orçamento grátis · 0% de taxa'), findsOneWidget);
    });

    testWidgets('2. CriarContaTela remove Passo 1 de 2 e Confirmar senha', (tester) async {
      await _abrir(tester, const CriarContaTela());
      expect(find.text('Passo 1 de 2'), findsNothing);
      expect(find.text('Confirmar senha'), findsNothing);
    });

    testWidgets('3. PedidoAbertoTela exibe aviso quando orcamentosRecebidos == 0', (tester) async {
      const semOrcamentos = DadosDoPedido(
        titulo: 'Trocar tomada',
        descricao: 'Tomada da sala',
        orcamentosRecebidos: 0,
      );
      await _abrir(
        tester,
        PedidoAbertoTela(
          numero: 'AB12',
          dados: semOrcamentos,
          aoSalvar: ({
            required descricao,
            required faixaMaxCentavos,
            required logradouro,
            required numero,
            required bairro,
            cep,
          }) async =>
              null,
          aoVerOrcamentos: () {},
        ),
      );
      expect(
        find.text(
          'Pedido enviado aos profissionais da região — avisaremos quando chegar o 1º orçamento.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('4. AvaliacaoTela avisa sobre +50 Tratinhos antes do botão', (tester) async {
      await _abrir(
        tester,
        const AvaliacaoTela(
          dados: DadosAvaliacao(
            nomeProfissional: 'Carlos',
            valorLiberadoCentavos: 20000,
            criterios: ['Pontualidade'],
            gorjetasCentavos: [1000],
            bonusDisponivel: true,
            bonusMoedas: 50,
            valorMoedaCentavos: 1,
          ),
        ),
      );
      expect(find.textContaining('+50 Tratinhos'), findsOneWidget);
      expect(find.textContaining('R\$ 0,50'), findsOneWidget);
    });

    testWidgets('5. SucessoAcaoTela inclui botão Indicar o Trato com cópia', (tester) async {
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiado = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _abrir(
        tester,
        SucessoAcaoTela(
          titulo: 'Pedido enviado!',
          subtitulo: 'Tudo certo.',
          aoVoltarInicio: () {},
          // Sem plugin de compartilhamento (teste/desktop): cai no copiar.
          compartilhar: (_) async => throw StateError('sem plugin'),
        ),
      );

      await tester.tap(find.text('Indicar o Trato'));
      await tester.pumpAndSettle();

      expect(copiado, isNotNull);
      expect(find.text('Convite copiado!'), findsOneWidget);
    });

    testWidgets(
        '6. DetalheOrcamentoTela mostra Novo no Trato e Identidade verificada para iniciante',
        (tester) async {
      final orc = Orcamento(
        id: 'o1',
        profissional: 'Ana Lima',
        iniciais: 'AL',
        nota: 0,
        notaResumo: semAvaliacoes,
        servicosConcluidos: 0,
        servicosResumo: '0',
        verificacao: '',
        totalCentavos: 15000,
        quando: 'Hoje',
        inicio: DateTime(2026, 11, 20, 14),
        garantia: '90 dias',
        observacao: '',
        detalhe: const DetalheOrcamento(
          validoAte: '25/11',
          itens: [ItemOrcamento(descricao: 'Instalação', centavos: 15000)],
          notaMaterial: 'Sem material',
          agendaTitulo: 'Hoje',
          agendaDetalhe: '14h às 16h',
          garantiaTitulo: 'Garantia de 90 dias',
          garantiaDetalhe: 'Cobre mão de obra.',
          foraDoEscopo: '',
          cancelamento: 'Grátis',
        ),
      );
      await _abrir(tester, DetalheOrcamentoTela(orcamento: orc));

      expect(find.text('Identidade verificada'), findsOneWidget);
      expect(find.textContaining('Novo no Trato'), findsOneWidget);
      expect(find.textContaining('0 serviços'), findsNothing);
    });

    testWidgets('7. CadastroProfissionalTela exibe faixa de 0% de taxa no topo', (tester) async {
      await _abrir(
        tester,
        CadastroProfissionalTela(servico: _ServicoCadastroFake()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sem taxa de serviço. Receba pedidos direto no celular.'),
        findsOneWidget,
      );
    });

    test('8 e 9. ServicoAjudaLocal tem 4 novas FAQs e avisoRascunhoLegal usa piloto vigente',
        () async {
      final faqs = await const ServicoAjudaLocal().perguntas();
      final textoFaqs = faqs.map((f) => '${f.pergunta} ${f.resposta}').join('\n');
      expect(textoFaqs, contains('Tratinhos'));
      expect(textoFaqs, contains('48h'));
      expect(textoFaqs, contains('0% de taxa'));
      expect(textoFaqs, contains('disputa'));

      expect(avisoRascunhoLegal, equals('Documento oficial em vigor durante o piloto. Dúvidas ou exercício de direitos LGPD: privacidade@tratofeitolabs.com.br.'));
      expect(avisoRascunhoLegal, isNot(contains('Belo Horizonte/MG')));
    });
  });
}

class _ServicoCadastroFake implements ServicoCadastroProfissional {
  @override
  Future<DadosCadastroProfissional?> carregarAtual() async => null;

  @override
  Future<OpcoesCadastro> carregarOpcoes() async => const OpcoesCadastro(
        categorias: ['Elétrica'],
        cidades: ['Belo Horizonte'],
        raiosKm: [10],
        dias: ['Seg'],
        periodos: ['Manhã'],
      );

  @override
  Future<void> salvar(DadosCadastroProfissional dados) async {}
}
