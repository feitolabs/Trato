import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/carregador.dart';
import 'package:trato/telas/cliente/inicio_tela.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_out_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/conclusao/dados_exemplo.dart';
import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';
import 'apoio/exemplos/telas/profissional/servico_check_out_fake.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';

Widget _app(Widget home, {ThemeData? tema, Size tamanho = const Size(390, 844)}) =>
    MediaQuery(
      data: MediaQueryData(size: tamanho),
      child: MaterialApp(
        theme: tema ?? TemaTrato.claro,
        home: home,
      ),
    );

void main() {
  testWidgets('TemaTrato.escuro expõe CoresTemaTrato e estiliza cartão e link destrutivo',
      (tester) async {
    late CoresTemaTrato lidas;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) {
              lidas = context.cores;
              return CartaoTrato(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Claro ou escuro', style: TextStyle(color: lidas.texto)),
                    BotaoLink(texto: 'Cancelar pedido', destrutivo: true, aoTocar: () {}),
                  ],
                ),
              );
            },
          ),
        ),
        tema: TemaTrato.escuro,
      ),
    );

    expect(lidas.fundo, CoresTratoEscuro.fundo);
    expect(lidas.superficie, CoresTratoEscuro.superficie);
    expect(find.text('Cancelar pedido'), findsOneWidget);
  });

  testWidgets(
      'ChatPedidoTela faz rollback em falha, destrava polling e cabe em 320dp sem overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const base = ConversaPedido(
      nome: 'Mariana Oliveira Costa Santos',
      iniciais: 'MO',
      numeroPedido: '#9988',
      situacao: 'Pedido aberto',
      respostasRapidas: [],
      mensagens: [
        MensagemChat(tipo: TipoMensagem.texto, texto: 'Olá!', hora: '09:00', minha: false),
      ],
    );

    var recarregamentos = 0;
    await tester.pumpWidget(
      _app(
        ChatPedidoTela(
          conversa: base,
          aoProporNovaCondicao: () async {},
          aoSugerirAgenda: () async {},
          aoEnviar: (_) => Future<void>.error(StateError('sem rede')),
          aoRecarregar: () async {
            recarregamentos++;
            return const ConversaPedido(
              nome: 'Mariana Oliveira Costa Santos',
              iniciais: 'MO',
              numeroPedido: '#9988',
              situacao: 'Pedido aberto',
              respostasRapidas: [],
              mensagens: [
                MensagemChat(tipo: TipoMensagem.texto, texto: 'Olá!', hora: '09:00', minha: false),
                MensagemChat(
                  tipo: TipoMensagem.texto,
                  texto: 'Resposta do servidor',
                  hora: '09:01',
                  minha: false,
                ),
              ],
            );
          },
        ),
        tamanho: const Size(320, 640),
      ),
    );

    // Compacto em 320dp sem estourar.
    expect(tester.takeException(), isNull);
    expect(find.text('Nova proposta'), findsOneWidget);
    expect(find.text('Horário'), findsOneWidget);

    // Envia mensagem que falha: remove a bolha otimista, preserva texto digitado e mantém polling.
    await tester.enterText(find.byType(TextField), 'Falhou aqui');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('Falhou aqui')),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(TextField), matching: find.text('Falhou aqui')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Atualizar conversa'));
    await tester.pump();
    await tester.pump();

    expect(recarregamentos, greaterThanOrEqualTo(1));
    expect(find.text('Resposta do servidor'), findsOneWidget);
  });

  testWidgets('Carregador pausa polling com TickerMode desligado e atualiza ao voltar a ficar visível',
      (tester) async {
    var chamadas = 0;
    late void Function(VoidCallback) atualizarPai;
    var ativo = false;

    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            atualizarPai = setState;
            return TickerMode(
              enabled: ativo,
              child: Carregador<int>(
                carregar: () async => ++chamadas,
                atualizarACada: const Duration(seconds: 2),
                construir: (context, v) => Text('v=$v'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(chamadas, 1);

    // Com TickerMode desabilitado (aba oculta), o relógio de 2s não dispara novas chamadas.
    await tester.pump(const Duration(seconds: 6));
    expect(chamadas, 1);

    // Ao voltar a ficar visível, atualiza na hora.
    atualizarPai(() => ativo = true);
    await tester.pump();
    await tester.pump();
    expect(chamadas, greaterThanOrEqualTo(2));
  });

  testWidgets('BarraAbasTrato e botão de sino exibem badge quando há não lidas', (tester) async {
    await tester.pumpWidget(
      _app(
        InicioTela(
          dados: const DadosInicio(
            nome: 'João',
            categorias: [],
            notificacoesNaoLidas: 3,
          ),
          aoBuscar: () {},
        ),
      ),
    );
    final sino = find.bySemanticsLabel('Notificações');
    expect(sino, findsOneWidget);
    expect(tester.getSemantics(sino).value, '3 não lidas');
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('3')),
      findsOneWidget,
    );

    final abasComBadge = [
      for (var i = 0; i < abasCliente.length; i++)
        i == 3 ? abasCliente[i].comBadge(7) : abasCliente[i],
    ];
    await tester.pumpWidget(
      _app(
        Scaffold(
          bottomNavigationBar: BarraAbasTrato(
            abas: abasComBadge,
            indiceAtual: 0,
            aoSelecionar: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('NovoPedidoTela e RelatarProblemaTela permitem remover foto anexada', (tester) async {
    await tester.pumpWidget(
      _app(
        NovoPedidoTela(
          formulario: formularioExemplo,
          aoCapturarFoto: () async => 'foto://pedido-1.jpg',
        ),
        tamanho: const Size(390, 2000),
      ),
    );
    final addPedido = find.text('Adicionar');
    await tester.ensureVisible(addPedido);
    await tester.tap(addPedido);
    await tester.pumpAndSettle();
    final remPedido = find.byTooltip('Remover foto');
    expect(remPedido, findsOneWidget);
    await tester.ensureVisible(remPedido);
    await tester.tap(remPedido);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remover foto'), findsNothing);

    await tester.pumpWidget(
      _app(
        RelatarProblemaTela(
          dados: dadosRelatoExemplo,
          aoCapturarFoto: () async => 'foto://disputa-1.jpg',
        ),
        tamanho: const Size(390, 2000),
      ),
    );
    final addRelato = find.text('Adicionar');
    await tester.ensureVisible(addRelato);
    await tester.tap(addRelato);
    await tester.pumpAndSettle();
    final remRelato = find.byTooltip('Remover foto');
    expect(remRelato, findsOneWidget);
    await tester.ensureVisible(remRelato);
    await tester.tap(remRelato);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remover foto'), findsNothing);
  });

  testWidgets(
      'CalculadoraOrcamentoTela usa teclado decimal, edita/remove item e colapsa ao marcar Cliente fornece',
      (tester) async {
    await tester.pumpWidget(
      _app(
        CalculadoraOrcamentoTela(
          servico: ServicoOrcamentoFake(),
          tituloPedido: 'Trocar disjuntor',
        ),
        tamanho: const Size(390, 1400),
      ),
    );

    final camposFinder = find.byType(TextField);
    final campos = tester.widgetList<TextField>(camposFinder).toList();
    expect(
      campos.take(3).every(
            (f) => f.keyboardType == const TextInputType.numberWithOptions(decimal: true),
          ),
      isTrue,
    );

    // Adiciona item
    await tester.ensureVisible(find.text('Adicionar item'));
    await tester.tap(find.text('Adicionar item'));
    await tester.pumpAndSettle();
    final totalCampos = tester.widgetList<TextField>(camposFinder).length;
    expect(
      tester.widget<TextField>(camposFinder.at(totalCampos - 1)).keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    await tester.enterText(camposFinder.at(totalCampos - 2), 'Cabo flexível');
    await tester.enterText(camposFinder.at(totalCampos - 1), '40');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Cabo flexível'), findsOneWidget);

    // Edita item ao tocar no título
    await tester.tap(find.text('Cabo flexível'));
    await tester.pumpAndSettle();
    final totalCamposEdit = tester.widgetList<TextField>(camposFinder).length;
    await tester.enterText(camposFinder.at(totalCamposEdit - 2), 'Cabo PP');
    await tester.tap(find.text('Salvar item'));
    await tester.pumpAndSettle();
    expect(find.text('Cabo PP'), findsOneWidget);

    // Alterna para Cliente fornece: oculta itens e mostra resumo sem cobrança
    await tester.ensureVisible(find.text('Cliente fornece'));
    await tester.tap(find.text('Cliente fornece'));
    await tester.pumpAndSettle();
    expect(find.text('Cabo PP'), findsNothing);
    expect(find.textContaining('1 item listado não entra no total'), findsOneWidget);

    // Volta para Eu forneço e remove item
    await tester.tap(find.text('Eu forneço'));
    await tester.pumpAndSettle();
    expect(find.text('Cabo PP'), findsOneWidget);
    await tester.tap(find.byTooltip('Remover item'));
    await tester.pumpAndSettle();
    expect(find.text('Cabo PP'), findsNothing);
  });

  testWidgets('CheckOutTela exibe miniatura da foto e opção Refazer após captura',
      (tester) async {
    await tester.pumpWidget(
      _app(
        CheckOutTela(
          servico: ServicoCheckOutFake(),
          tituloBarra: 'Mariana · hoje, 16h',
        ),
      ),
    );

    await tester.tap(find.text('Tirar foto'));
    await tester.pumpAndSettle();

    expect(find.byType(ToquePreviewImagem), findsOneWidget);
    expect(find.text('Refazer'), findsOneWidget);
  });
}
