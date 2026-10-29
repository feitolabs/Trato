import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/telas/profissional/dinheiro.dart';
import 'package:trato/telas/profissional/servico_check_in_fake.dart';
import 'package:trato/telas/profissional/servico_orcamento_fake.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 1800),
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: tela,
    ),
  );
  await tester.pump();
}

const _itens = [
  ItemMaterial(nome: '2 tomadas 20 A', centavos: 4600),
  ItemMaterial(nome: 'Resistência 220 V', centavos: 6400),
];

CalculadoraOrcamentoTela _calculadora(
  ServicoOrcamentoFake servico, {
  ValueChanged<OrcamentoPronto>? aoEnviar,
  List<ItemMaterial> itens = _itens,
  String desloc = '30',
  String horas = '3',
  String valorHora = '80',
}) =>
    CalculadoraOrcamentoTela(
      servico: servico,
      tituloPedido: 'Troca de tomadas e chuveiro',
      deslocamentoInicial: desloc,
      horasInicial: horas,
      valorHoraInicial: valorHora,
      itensIniciais: itens,
      faixaRegiaoCentavos: (30000, 45000),
      aoEnviar: aoEnviar,
    );

Finder _campo(String rotulo) => find.descendant(
      of: find.ancestor(of: find.text(rotulo), matching: find.byType(Column)).first,
      matching: find.byType(TextField),
    );

void main() {
  group('Dinheiro', () {
    test('formatar', () {
      expect(Dinheiro.formatar(4600), 'R\$ 46,00');
      expect(Dinheiro.formatar(5), 'R\$ 0,05');
      expect(Dinheiro.formatar(123456), 'R\$ 1.234,56');
      expect(Dinheiro.formatar(100000000), 'R\$ 1.000.000,00');
    });

    test('lerCentavos', () {
      expect(Dinheiro.lerCentavos('30'), 3000);
      expect(Dinheiro.lerCentavos('30,5'), 3050);
      expect(Dinheiro.lerCentavos('30.50'), 3050);
      expect(Dinheiro.lerCentavos(''), isNull);
      expect(Dinheiro.lerCentavos('abc'), isNull);
      expect(Dinheiro.lerCentavos('1,234'), isNull);
    });

    test('horas em décimos e valor das horas', () {
      expect(Dinheiro.lerDecimosDeHora('3'), 30);
      expect(Dinheiro.lerDecimosDeHora('2,5'), 25);
      expect(Dinheiro.lerDecimosDeHora('2,55'), isNull);
      expect(Dinheiro.valorDasHoras(8000, 30), 24000);
      expect(Dinheiro.valorDasHoras(8000, 25), 20000);
      expect(Dinheiro.valorDasHoras(3333, 5), 1667); // meio centavo sobe
    });

    test('percentual vem de pontos-base', () {
      expect(Dinheiro.formatarBps(500), '5%');
      expect(Dinheiro.formatarBps(750), '7,5%');
      expect(Dinheiro.formatarBps(725), '7,25%');
    });
  });

  group('Calculadora de orçamento', () {
    testWidgets('soma exibida e interface chamada com o total certo', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      await _abrir(tester, _calculadora(servico));
      await tester.pump();

      // 30 + 3 x 80 + 46 + 64 = R$ 380,00
      expect(servico.pedidos, [38000]);
      expect(find.text('R\$ 380,00'), findsOneWidget);
      // Taxa e líquido vêm da interface (fake em 7,5%).
      expect(find.text('Taxa Trato (7,5%)'), findsOneWidget);
      expect(find.text('– R\$ 28,50'), findsOneWidget);
      expect(find.text('R\$ 351,50'), findsOneWidget);
      expect(find.text('Serviços parecidos na região: R\$ 300,00 a R\$ 450,00.'), findsOneWidget);
    });

    testWidgets('rótulo da taxa acompanha o percentual devolvido', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 500);
      await _abrir(tester, _calculadora(servico));
      await tester.pump();
      expect(find.text('Taxa Trato (5%)'), findsOneWidget);
      expect(find.text('– R\$ 19,00'), findsOneWidget);
      expect(find.text('R\$ 361,00'), findsOneWidget);
    });

    testWidgets('mudar um campo refaz o pedido com o novo total', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      await _abrir(tester, _calculadora(servico));
      await tester.pump();

      await tester.enterText(_campo('Horas'), '4');
      await tester.pump();
      await tester.pump();

      expect(servico.pedidos.last, 46000); // 30 + 4 x 80 + 110
      expect(find.text('R\$ 460,00'), findsOneWidget);
    });

    testWidgets('Cliente fornece tira o material do total', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      await _abrir(tester, _calculadora(servico));
      await tester.pump();

      await tester.tap(find.text('Cliente fornece'));
      await tester.pump();
      await tester.pump();

      expect(servico.pedidos.last, 27000);
      expect(find.text('Pedir sinal para o material'), findsNothing);
    });

    testWidgets('sem horas e valor não há total nem chamada', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      await _abrir(tester, _calculadora(servico, itens: [], desloc: '', horas: '', valorHora: ''));
      await tester.pump();
      expect(servico.pedidos, isEmpty);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('validação: campos obrigatórios bloqueiam o envio', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      OrcamentoPronto? enviado;
      await _abrir(
        tester,
        _calculadora(servico, aoEnviar: (o) => enviado = o, horas: '', valorHora: ''),
      );

      await tester.tap(find.text('Enviar orçamento'));
      await tester.pump();

      expect(enviado, isNull);
      expect(find.text('Informe as horas, como 3 ou 2,5.'), findsOneWidget);
      expect(find.text('Informe o valor da hora.'), findsOneWidget);
    });

    testWidgets('validação: deslocamento inválido', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      OrcamentoPronto? enviado;
      await _abrir(tester, _calculadora(servico, aoEnviar: (o) => enviado = o, desloc: '1,2,3'));
      await tester.tap(find.text('Enviar orçamento'));
      await tester.pump();
      expect(enviado, isNull);
      expect(find.text('Use só números, como 30 ou 30,50.'), findsOneWidget);
    });

    testWidgets('enviar entrega o orçamento em centavos inteiros', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      OrcamentoPronto? enviado;
      await _abrir(tester, _calculadora(servico, aoEnviar: (o) => enviado = o));
      await tester.tap(find.text('Pedir sinal para o material'));
      await tester.pump();

      await tester.tap(find.text('Enviar orçamento'));
      await tester.pump();

      expect(enviado, isNotNull);
      expect(enviado!.totalCentavos, 38000);
      expect(enviado!.deslocamentoCentavos, 3000);
      expect(enviado!.decimosDeHora, 30);
      expect(enviado!.valorHoraCentavos, 8000);
      expect(enviado!.garantiaDias, 90);
      expect(enviado!.itens.length, 2);
      expect(enviado!.pedirSinalMaterial, isTrue);
      expect(
        find.text('Válido por 3 dias · você pode editar até o cliente aceitar'),
        findsOneWidget,
      );
    });

    testWidgets('adicionar item soma ao total', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      await _abrir(tester, _calculadora(servico));
      await tester.pump();

      await tester.tap(find.text('Adicionar item'));
      await tester.pumpAndSettle();
      await tester.enterText(_campo('Item'), 'Disjuntor');
      await tester.enterText(_campo('Valor'), '20');
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      expect(find.text('Disjuntor'), findsOneWidget);
      expect(servico.pedidos.last, 40000);
    });

    testWidgets('adicionar item sem valor mostra erro e não fecha', (tester) async {
      final servico = ServicoOrcamentoFake(taxaBps: 750);
      await _abrir(tester, _calculadora(servico));
      await tester.tap(find.text('Adicionar item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar'));
      await tester.pump();
      expect(find.text('Informe o item.'), findsOneWidget);
      expect(find.text('Informe o valor.'), findsOneWidget);
    });
  });

  group('Check-in', () {
    Future<ServicoCheckInFake> abrirCheckIn(
      WidgetTester tester, {
      bool completo = true,
      VoidCallback? aoIniciar,
    }) async {
      final servico = ServicoCheckInFake();
      await _abrir(
        tester,
        CheckInTela(
          servico: servico,
          tituloBarra: 'Mariana · hoje, 14h',
          aoIniciar: aoIniciar,
          fotoInicial: completo ? await servico.tirarFoto() : null,
          distanciaInicialMetros: completo ? 20 : null,
        ),
      );
      return servico;
    }

    testWidgets('mostra os passos feitos', (tester) async {
      await abrirCheckIn(tester);
      expect(find.text('14h06'), findsOneWidget);
      expect(find.text('A 20 m do endereço'), findsOneWidget);
      expect(find.text('Feito'), findsNWidgets(2));
    });

    testWidgets('só inicia com foto, localização e 4 números', (tester) async {
      final servico = await abrirCheckIn(tester, completo: false);
      FilledButton botao() => tester.widget<FilledButton>(find.byType(FilledButton));
      expect(botao().onPressed, isNull);

      await tester.tap(find.text('Tirar foto'));
      await tester.pump();
      await tester.tap(find.text('Localizar'));
      await tester.pump();
      expect(botao().onPressed, isNull); // falta o código

      await tester.enterText(find.byType(TextField), '482');
      await tester.pump();
      expect(botao().onPressed, isNull);

      await tester.enterText(find.byType(TextField), '4821');
      await tester.pump();
      expect(botao().onPressed, isNotNull);
      expect(servico.codigosEnviados, isEmpty);
    });

    testWidgets('campo aceita só 4 dígitos', (tester) async {
      await abrirCheckIn(tester);
      await tester.enterText(find.byType(TextField), '48a2199');
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '4821');
    });

    testWidgets('código certo inicia; errado mostra erro vindo do backend', (tester) async {
      var iniciou = false;
      final servico = await abrirCheckIn(tester, aoIniciar: () => iniciou = true);

      await tester.enterText(find.byType(TextField), '0000');
      await tester.pump();
      await tester.tap(find.text('Iniciar serviço'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Código incorreto. Peça de novo ao cliente.'), findsOneWidget);
      expect(iniciou, isFalse);

      await tester.enterText(find.byType(TextField), '4821');
      await tester.pump();
      await tester.tap(find.text('Iniciar serviço'));
      await tester.pump();
      await tester.pump();
      expect(servico.codigosEnviados, ['0000', '4821']);
      expect(iniciou, isTrue);
    });

    testWidgets('mensagens rápidas e cliente ausente chamam o serviço', (tester) async {
      final servico = await abrirCheckIn(tester);
      await tester.tap(find.text('Estou na portaria'));
      await tester.pump();
      expect(servico.mensagens, ['Estou na portaria']);

      final link = find.text('Cliente não está no local');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pump();
      expect(servico.clienteAusenteAvisado, isTrue);
    });
  });

  // Qualquer estouro de layout falha o teste.
  const tamanhos = {
    '320x640': Size(320, 640),
    '390x844': Size(390, 844),
    '768x1024': Size(768, 1024),
  };
  for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
    for (final escala in [1.0, Responsivo.escalaFonteMaxima]) {
      testWidgets('sem estouro — calculadora e check-in — $nome, fonte x$escala', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = escala;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _abrir(tester, _calculadora(ServicoOrcamentoFake(taxaBps: 750)), tamanho: tamanho);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull);

        await _abrir(
          tester,
          CheckInTela(servico: ServicoCheckInFake(), tituloBarra: 'Mariana · hoje, 14h'),
          tamanho: tamanho,
        );
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
