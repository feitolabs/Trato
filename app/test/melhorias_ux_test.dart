import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/carregador.dart';
import 'package:trato/dados/repositorios.dart' show StatusPagamento;
import 'package:trato/dados/servico_cep.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/modelos.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/busca/modelos.dart';
import 'package:trato/telas/catalogo/todas_categorias_tela.dart';
import 'package:trato/telas/cliente/inicio_tela.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/comuns/foco_rolagem.dart';
import 'package:trato/telas/comuns/sucesso_acao_tela.dart';
import 'package:trato/telas/conta/dados_pessoais_tela.dart';
import 'package:trato/telas/conta/servico_fake.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/servico_orcamento.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';
import 'apoio/orcamento.dart';

Widget _wrap(Widget tela) => MaterialApp(
      theme: TemaTrato.claro,
      home: tela,
    );

class _ServicoOrcamentoFake implements ServicoOrcamento {
  @override
  Future<ResumoOrcamento> resumir(int totalCentavos) async => ResumoOrcamento(
        totalCentavos: totalCentavos,
      );

  @override
  Future<void> enviar(OrcamentoPronto orcamento) async {}
}

class _ServicoBuscaStub implements ServicoBusca {
  _ServicoBuscaStub(this.resultados);
  final List<Profissional> resultados;
  final List<String> consultas = [];

  @override
  Future<List<Profissional>> buscar(String termo, {bool disponivelAgora = false}) async {
    consultas.add(termo);
    return resultados;
  }
}

class _ServicoAjudaStub implements ServicoAjuda {
  @override
  Future<List<PerguntaFrequente>> perguntas() async => const [
        PerguntaFrequente(
          pergunta: 'Como funciona o pagamento?',
          resposta: 'Você paga pelo aplicativo com segurança.',
        ),
        PerguntaFrequente(
          pergunta: 'Posso cancelar o pedido?',
          resposta: 'Sim, antes da conclusão.',
        ),
      ];
}

void main() {
  test('ordenação alfabética PT-BR ignora acento e caixa', () {
    final lista = ['Zeladoria', 'Água e Gás', 'Elétrica', 'Alvenaria']
      ..sort(compararAlfabeticoPtBr);
    expect(lista, ['Água e Gás', 'Alvenaria', 'Elétrica', 'Zeladoria']);
    expect(normalizarTextoBusca('Água & Ar-Condicionado'), 'agua ar condicionado');
  });

  test('ContrapropostaChat lê contraproposta e proposta com prazo em dias', () {
    final (cp, textoCp) = ContrapropostaChat.ler('[contraproposta:orc1:25000:5] Fecho por isso');
    expect(cp?.orcamentoId, 'orc1');
    expect(cp?.valorCentavos, 25000);
    expect(cp?.prazoExecucaoDias, 5);
    expect(cp?.ehPropostaDoProfissional, isFalse);
    expect(textoCp, 'Fecho por isso');

    final (prop, textoProp) = ContrapropostaChat.ler('[proposta:orc1:28000:4] Nova condição');
    expect(prop?.orcamentoId, 'orc1');
    expect(prop?.valorCentavos, 28000);
    expect(prop?.prazoExecucaoDias, 4);
    expect(prop?.ehPropostaDoProfissional, isTrue);
    expect(textoProp, 'Nova condição');
  });

  testWidgets('CalculadoraOrcamentoTela permite negociar prazo em dias e valida', (tester) async {
    OrcamentoPronto? enviado;
    await tester.pumpWidget(
      _wrap(
        CalculadoraOrcamentoTela(
          servico: _ServicoOrcamentoFake(),
          tituloPedido: 'Instalar tomadas',
          horasInicial: '2',
          valorHoraInicial: '100,00',
          garantiaInicialDias: 90,
          aoEnviar: (p) => enviado = p,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final campoDias = find.widgetWithText(TextField, 'Ex.: 3');
    await tester.enterText(campoDias, '0');
    await tester.tap(find.text('Enviar orçamento'));
    await tester.pumpAndSettle();
    expect(find.text('Informe em quantos dias pretende concluir (mínimo 1 dia).'), findsOneWidget);
    expect(enviado, isNull);

    await tester.enterText(campoDias, '6');
    await completarOrcamento(tester);
    await tester.tap(find.text('Enviar orçamento'));
    await tester.pumpAndSettle();
    expect(enviado?.prazoExecucaoDias, 6);
  });

  testWidgets('ChatPedidoTela mostra Aceitar e pagar em proposta do profissional e desativa antiga', (tester) async {
    ContrapropostaChat? aceita;
    await tester.pumpWidget(
      _wrap(
        ChatPedidoTela(
          conversa: const ConversaPedido(
            nome: 'Carlos M.',
            iniciais: 'CM',
            numeroPedido: '#1234',
            situacao: 'Aguardando',
            orcamentosAtivos: {'orc1'},
            mensagens: [
              MensagemChat(
                tipo: TipoMensagem.texto,
                hora: '10:00',
                texto: 'Primeira oferta',
                contraproposta: ContrapropostaChat(
                  orcamentoId: 'orc1',
                  valorCentavos: 20000,
                  prazoExecucaoDias: 5,
                  ehPropostaDoProfissional: true,
                ),
              ),
              MensagemChat(
                tipo: TipoMensagem.texto,
                hora: '10:05',
                texto: 'Oferta atual',
                contraproposta: ContrapropostaChat(
                  orcamentoId: 'orc1',
                  valorCentavos: 18000,
                  prazoExecucaoDias: 3,
                  ehPropostaDoProfissional: true,
                ),
              ),
            ],
            respostasRapidas: [],
          ),
          aoAceitarProposta: (c) async => aceita = c,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proposta substituída'), findsOneWidget);
    expect(find.text('Aceitar e pagar'), findsOneWidget);
    expect(find.textContaining('Prazo: 3 dias'), findsOneWidget);

    await tester.tap(find.text('Aceitar e pagar'));
    await tester.pumpAndSettle();
    expect(aceita?.valorCentavos, 18000);
    expect(aceita?.prazoExecucaoDias, 3);
  });

  testWidgets('TodasCategoriasTela ordena A-Z e BuscaProfissionaisTela debouncing e filtros', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TodasCategoriasTela(
          carregar: () async => const [
            CategoriaServico('Pintura', Icons.format_paint),
            CategoriaServico('Água', Icons.water_drop),
            CategoriaServico('Elétrica', Icons.bolt),
          ],
          aoEscolher: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final posAgua = tester.getTopLeft(find.text('Água'));
    final posEletrica = tester.getTopLeft(find.text('Elétrica'));
    final posPintura = tester.getTopLeft(find.text('Pintura'));
    expect(posAgua.dy < posPintura.dy || posAgua.dx < posEletrica.dx, isTrue);

    final stub = _ServicoBuscaStub(const [
      Profissional(
        nome: 'Ana S.',
        iniciais: 'AS',
        verificacao: 'Verificado',
        especialidade: 'Eletricista',
        servicosConcluidos: 10,
        nota: 4.9,
        distanciaKm: 2,
        atendeHoje: true,
        regiao: 'Centro',
      ),
      Profissional(
        nome: 'Bruno K.',
        iniciais: 'BK',
        verificacao: 'Verificado',
        especialidade: 'Eletricista',
        servicosConcluidos: 4,
        nota: 4.1,
        distanciaKm: 5,
        atendeHoje: false,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(
        BuscaProfissionaisTela(
          servico: stub,
          sugestoes: const [
            CategoriaServico('Ver todas', Icons.grid_view),
            CategoriaServico('Pintura', Icons.format_paint),
            CategoriaServico('Alvenaria', Icons.foundation),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Alvenaria')).dx < tester.getTopLeft(find.text('Ver todas')).dx ||
          tester.getTopLeft(find.text('Alvenaria')).dy < tester.getTopLeft(find.text('Ver todas')).dy,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'e');
    await tester.pump();
    expect(find.text('Continue digitando'), findsOneWidget);
    expect(stub.consultas, isEmpty);

    await tester.enterText(find.byType(TextField), 'eletrica');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(stub.consultas, ['eletrica']);
    expect(find.text('Ana S.'), findsOneWidget);
    expect(find.text('Bruno K.'), findsOneWidget);

    await tester.tap(find.text('Nota 4,5+'));
    await tester.pumpAndSettle();
    expect(find.text('Ana S.'), findsOneWidget);
    expect(find.text('Bruno K.'), findsNothing);
  });

  testWidgets('AjudaTela e SeusPedidosTela possuem busca inline e pull-to-refresh', (tester) async {
    var recarregou = 0;
    await tester.pumpWidget(
      _wrap(
        AtualizadorTela(
          recarregar: () async => recarregou++,
          child: const SeusPedidosTela(
            emAndamento: [
              PedidoResumo(
                titulo: 'Trocar chuveiro',
                subtitulo: '2 orçamentos',
                statusTexto: 'Aguardando',
                statusTipo: TipoStatus.info,
                profissionalNome: 'Carlos',
              ),
              PedidoResumo(
                titulo: 'Pintar sala',
                subtitulo: '1 orçamento',
                statusTexto: 'Aberto',
                statusTipo: TipoStatus.info,
              ),
            ],
            finalizados: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'chuveiro');
    await tester.pump();
    expect(find.text('Trocar chuveiro'), findsOneWidget);
    expect(find.text('Pintar sala'), findsNothing);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(recarregou, 1);

    await tester.pumpWidget(_wrap(AjudaTela(servico: _ServicoAjudaStub())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'cancelar');
    await tester.pump();
    expect(find.text('Posso cancelar o pedido?'), findsOneWidget);
    expect(find.text('Como funciona o pagamento?'), findsNothing);
  });

  testWidgets('CampoCepAutoPreenchimento e NovoPedidoTela preenchem endereço por CEP', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const NovoPedidoTela(
          formulario: formularioExemplo,
          servicoCep: ServicoCepFake(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cepField = find.descendant(
      of: find.byKey(const ValueKey('campo-cep')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(cepField);
    await tester.enterText(cepField, '35500000');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Av. Primeiro de Junho'), findsOneWidget);
    expect(find.text('Centro'), findsOneWidget);
  });

  testWidgets('SucessoAcaoTela, DadosPessoaisTela e textos sem jargão técnico', (tester) async {
    var voltou = false;
    await tester.pumpWidget(
      _wrap(
        SucessoAcaoTela(
          titulo: 'Ação concluída!',
          subtitulo: 'Tudo certo por aqui.',
          detalhes: const [
            ItemResumoSucesso('Pedido', 'Troca de tomadas'),
            ItemResumoSucesso('Prazo', '3 dias'),
          ],
          aoVoltarInicio: () => voltou = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ação concluída!'), findsOneWidget);
    expect(find.text('3 dias'), findsOneWidget);
    final cartaoSucesso = find.byType(CartaoTrato);
    final direitaSucesso = tester
        .getTopRight(
          find.descendant(of: cartaoSucesso, matching: find.byType(Column)).first,
        )
        .dx;
    for (final valor in ['Troca de tomadas', '3 dias']) {
      expect(
        tester
            .getTopRight(find.descendant(of: cartaoSucesso, matching: find.text(valor)))
            .dx,
        closeTo(direitaSucesso, 0.5),
      );
    }
    await tester.tap(find.text('Voltar ao início'));
    await tester.pump();
    expect(voltou, isTrue);

    await tester.pumpWidget(
      _wrap(
        DadosPessoaisTela(
          servico: ServicoContaFake(),
          servicoCep: const ServicoCepFake(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ENDEREÇO PRINCIPAL'), findsOneWidget);

    await tester.pumpWidget(_wrap(InicioTela(aoBuscar: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('parceiro'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        const PagamentoTela(
          dados: DadosPagamento(
            subtitulo: 'Carlos M. · Teste',
            valorAgoraCentavos: 10000,
            opcoes: [OpcaoPagamento(metodo: MetodoPagamento.pix, titulo: 'Pix', descricao: 'Na hora')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('parceiro'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        DetalheOrcamentoTela(
          orcamento: Orcamento(
            id: 'o1',
            profissional: 'Carlos M.',
            iniciais: 'CM',
            verificacao: 'Verificado',
            totalCentavos: 10000,
            nota: 5.0,
            notaResumo: '5,0',
            servicosResumo: '10',
            servicosConcluidos: 10,
            quando: '3 dias',
            inicio: DateTime(2026, 12, 1),
            garantia: '90 dias',
            observacao: '',
            detalhe: const DetalheOrcamento(
              validoAte: '30/11',
              itens: [ItemOrcamento(descricao: 'Serviço', centavos: 10000)],
              notaMaterial: 'Incluso',
              agendaTitulo: '',
              agendaDetalhe: '',
              garantiaTitulo: 'Garantia',
              garantiaDetalhe: '90 dias',
              foraDoEscopo: '',
              cancelamento: '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
    expect(find.textContaining('parceiro de pagamento'), findsNothing);
  });

  testWidgets('AguardandoPagamentoTela consulta imediatamente ao abrir', (tester) async {
    var chamadas = 0;
    var confirmou = false;
    await tester.pumpWidget(
      _wrap(
        AguardandoPagamentoTela(
          consultar: () async {
            chamadas++;
            return StatusPagamento.pago;
          },
          aoConfirmar: () => confirmou = true,
        ),
      ),
    );
    await tester.pump();
    expect(chamadas, 1);
    expect(confirmou, isTrue);
  });
}

