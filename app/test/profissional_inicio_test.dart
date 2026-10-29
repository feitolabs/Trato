import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/profissional_inicio/casca_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/dados_exemplo.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/profissional_inicio/pecas_profissional.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 1800),
  double fonte = 1.0,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fonte)),
        child: EscalaFonteLimitada(child: filho!),
      ),
      home: tela,
    ),
  );
}

void main() {
  test('formatação de faixa, distância e vagas', () {
    expect(reaisCurto(20000), 'R\$ 200');
    expect(reaisCurto(1250), 'R\$ 12,50');
    expect(reaisCurto(150000), 'R\$ 1.500');
    expect(textoFaixa(pedidoTomadasExemplo), 'R\$ 200 a R\$ 500');
    expect(textoFaixa(inicioProfissionalExemplo.pedidos[1]), 'Sem faixa');
    expect(textoDistancia(2.1), '2,1 km');
    expect(textoOrcamentos(pedidoTomadasExemplo), '3 de 5 orçaram');
    expect(textoOrcamentos(inicioProfissionalExemplo.pedidos[1]), '1 de 5 orçou');
    expect(textoOrcamentos(inicioProfissionalExemplo.pedidos[2]), 'Ninguém orçou');
  });

  group('Início do profissional', () {
    testWidgets('mostra disponibilidade, atendimento, carteira e pedidos', (tester) async {
      await _abrir(tester, const InicioProfissionalTela());
      expect(find.text('Pedidos perto de você'), findsOneWidget);
      expect(find.text('HOJE · 14H'), findsOneWidget);
      expect(find.text('R\$ 425,00'), findsOneWidget);
      expect(find.text('R\$ 712,50'), findsOneWidget);
      expect(find.text('Urgente'), findsOneWidget);
      expect(find.text('R\$ 200 a R\$ 500'), findsOneWidget);
      expect(find.text('Savassi · 2,1 km · até sexta, 30/10'), findsOneWidget);
      expect(find.textContaining('Rua Antônio de Albuquerque'), findsOneWidget);
    });

    testWidgets('pedido aberto não mostra endereço completo', (tester) async {
      await _abrir(tester, const InicioProfissionalTela());
      // O endereço aparece uma vez só: no atendimento já contratado.
      expect(find.textContaining('Rua '), findsOneWidget);
    });

    testWidgets('chave disponível e botões chamam os callbacks', (tester) async {
      bool? disponivel;
      var checkIn = false;
      var filtros = false;
      var carteira = false;
      PedidoAberto? aberto;
      await _abrir(
        tester,
        InicioProfissionalTela(
          aoAlterarDisponivel: (v) => disponivel = v,
          aoFazerCheckIn: () => checkIn = true,
          aoAbrirFiltros: () => filtros = true,
          aoAbrirCarteira: () => carteira = true,
          aoAbrirPedido: (p) => aberto = p,
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(disponivel, isFalse);
      await tester.tap(find.text('Fazer check-in'));
      await tester.tap(find.text('Filtros'));
      await tester.tap(find.text('Retido'));
      await tester.tap(find.text('Disjuntor desarmando'));
      expect([checkIn, filtros, carteira], [true, true, true]);
      expect(aberto!.id, 'ped-disjuntor');
    });

    testWidgets('sem próximo atendimento o cartão escuro some', (tester) async {
      const dados = InicioProfissional(
        nome: 'Ana',
        disponivelAgora: false,
        carteira: ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0),
        pedidos: [],
      );
      await _abrir(tester, const InicioProfissionalTela(dados: dados));
      expect(find.text('Fazer check-in'), findsNothing);
      expect(find.text('R\$ 0,00'), findsNWidgets(2));
    });
  });

  group('Detalhe do pedido', () {
    testWidgets('mostra só bairro e distância, com aviso do endereço', (tester) async {
      await _abrir(tester, const DetalhePedidoTela(), tamanho: const Size(390, 2000));
      expect(find.text('Fecha em 31 horas · 3 de 5 orçaram'), findsOneWidget);
      expect(find.textContaining('Savassi, a 2,1 km'), findsOneWidget);
      expect(find.textContaining('endereço completo aparece depois da contratação'), findsOneWidget);
      expect(find.text('Até sexta, 30/10'), findsOneWidget);
      expect(find.text('R\$ 200 a R\$ 500'), findsOneWidget);
      expect(find.text('Trocar tomada, trocar chuveiro'), findsOneWidget);
    });

    testWidgets('Perguntar e Fazer orçamento chamam os callbacks', (tester) async {
      var perguntou = false;
      var orcou = false;
      await _abrir(
        tester,
        DetalhePedidoTela(aoPerguntar: () => perguntou = true, aoFazerOrcamento: () => orcou = true),
        tamanho: const Size(390, 2000),
      );
      await tester.tap(find.text('Perguntar'));
      await tester.tap(find.text('Fazer orçamento'));
      expect(perguntou && orcou, isTrue);
    });

    testWidgets('recusar pede motivo e só confirma com um escolhido', (tester) async {
      MotivoRecusa? recusado;
      await _abrir(
        tester,
        DetalhePedidoTela(aoRecusar: (m) => recusado = m),
        tamanho: const Size(390, 2000),
      );
      await tester.tap(find.text('Recusar pedido'));
      await tester.pumpAndSettle();
      for (final m in MotivoRecusa.values) {
        expect(find.text(m.texto), findsOneWidget);
      }

      // Sem motivo, o botão fica desabilitado.
      await tester.tap(find.text('Confirmar recusa'));
      await tester.pumpAndSettle();
      expect(recusado, isNull);
      expect(find.text('Confirmar recusa'), findsOneWidget);

      await tester.tap(find.text('Sem agenda'));
      await tester.pump();
      await tester.tap(find.text('Fora do meu escopo'));
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.tap(find.text('Confirmar recusa'));
      await tester.pumpAndSettle();
      expect(recusado, MotivoRecusa.foraDoEscopo);
      expect(find.text('Confirmar recusa'), findsNothing);
    });

    testWidgets('voltar na folha não recusa', (tester) async {
      MotivoRecusa? recusado;
      await _abrir(
        tester,
        DetalhePedidoTela(aoRecusar: (m) => recusado = m),
        tamanho: const Size(390, 2000),
      );
      await tester.tap(find.text('Recusar pedido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(recusado, isNull);
    });
  });

  group('Casca do profissional', () {
    testWidgets('tem as 5 abas; as sem tela mostram Em breve', (tester) async {
      await _abrir(tester, const CascaProfissionalTela(), tamanho: const Size(390, 844));
      expect(find.byType(BarraAbasTrato), findsOneWidget);
      for (final aba in abasProfissional) {
        expect(find.text(aba.rotulo), findsWidgets);
      }
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(find.text('Esta tela chega nas próximas etapas.'), findsWidgets);
    });

    testWidgets('tocar a carteira leva à aba Carteira', (tester) async {
      await _abrir(tester, const CascaProfissionalTela(), tamanho: const Size(390, 1200));
      await tester.tap(find.text('Retido'));
      await tester.pumpAndSettle();
      final barra = tester.widget<BarraAbasTrato>(find.byType(BarraAbasTrato));
      expect(barra.indiceAtual, 3);
    });

    testWidgets('tocar um pedido abre o detalhe e recusar volta à lista', (tester) async {
      MotivoRecusa? recusado;
      await _abrir(
        tester,
        CascaProfissionalTela(aoRecusar: (m) => recusado = m),
        tamanho: const Size(390, 2000),
      );
      await tester.tap(find.text('Instalar 4 luminárias'));
      await tester.pumpAndSettle();
      expect(find.byType(DetalhePedidoTela), findsOneWidget);
      await tester.tap(find.text('Recusar pedido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fora da minha região'));
      await tester.pump();
      await tester.tap(find.text('Confirmar recusa'));
      await tester.pumpAndSettle();
      expect(recusado, MotivoRecusa.foraDaRegiao);
      expect(find.byType(DetalhePedidoTela), findsNothing);
    });
  });

  // Sem estouro de layout em 320/390/768, fonte 1,0 e 1,3.
  const tamanhos = {
    'pequeno 320x568': Size(320, 568),
    'protótipo 390x844': Size(390, 844),
    'tablet 768x1024': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'casca/início': const CascaProfissionalTela(),
    'detalhe': const DetalhePedidoTela(),
  };
  for (final MapEntry(key: nomeTela, value: tela) in telas.entries) {
    for (final MapEntry(key: nomeTam, value: tam) in tamanhos.entries) {
      for (final fonte in [1.0, 1.3]) {
        testWidgets('sem estouro — $nomeTela, $nomeTam, fonte x$fonte', (tester) async {
          await _abrir(tester, tela, tamanho: tam, fonte: fonte);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
