import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/dados_exemplo.dart';
import 'package:trato/telas/carteira/modelos.dart';
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
}

void main() {
  testWidgets('mostra saldos e extrato exatamente como vieram do dado',
      (tester) async {
    await _abrir(tester, const CarteiraTela());

    expect(find.text('R\$ 712,50'), findsOneWidget);
    expect(find.text('R\$ 425,00'), findsOneWidget);
    expect(find.text('R\$ 190,00'), findsNWidgets(3)); // a liberar + 2 líquidos
    expect(find.text('Pix na chave CPF ***.482.***-12 · cai em até 1 dia útil'),
        findsOneWidget);
    expect(find.text('Serviço em andamento'), findsOneWidget);
    expect(find.text('Automático em até 48 h'), findsOneWidget);

    expect(find.text('Instalar 4 luminárias'), findsOneWidget);
    expect(find.text('R\$ 200,00 – R\$ 10,00 de taxa'), findsNWidgets(2));
    expect(find.text('R\$ 380,00'), findsOneWidget); // líquido do portão
    expect(find.text('Confirmado'), findsNWidgets(3));
    expect(find.text('A confirmar'), findsNWidgets(2)); // cartão de saldo + chip
  });

  testWidgets('a tela não calcula: taxa e líquido mudam só pelo dado',
      (tester) async {
    const dados = DadosCarteira(
      resumo: ResumoCarteira(
        disponivelCentavos: 100,
        textoPix: 'chave x',
        retidoCentavos: 200,
        textoRetido: 'r',
        aLiberarCentavos: 300,
        textoALiberar: 'Automático em até 7 dias',
      ),
      extrato: [
        ItemExtrato(
          titulo: 'Serviço X',
          detalheData: 'hoje',
          brutoCentavos: 100000,
          textoTaxa: 'R\$ 7,00 de taxa',
          liquidoCentavos:
              12345, // valor "errado" de propósito: a tela não confere
          status: StatusExtrato.aLiberar,
        ),
      ],
    );
    await _abrir(tester, const CarteiraTela(dados: dados));

    expect(find.text('R\$ 1.000,00 – R\$ 7,00 de taxa'), findsOneWidget);
    expect(find.text('R\$ 123,45'), findsOneWidget);
    expect(find.text('Automático em até 7 dias'), findsOneWidget);
    expect(find.textContaining('5%'), findsNothing);
  });

  testWidgets('Sacar via Pix chama o callback', (tester) async {
    var sacou = 0;
    await _abrir(tester, CarteiraTela(aoSacarPix: () => sacou++));
    await tester.tap(find.text('Sacar via Pix'));
    expect(sacou, 1);
  });

  testWidgets('sem saldo disponível o saque fica desligado', (tester) async {
    var sacou = 0;
    await _abrir(
      tester,
      CarteiraTela(
          dados: DadosExemploCarteira.vazio, aoSacarPix: () => sacou++),
    );
    await tester.tap(find.text('Sacar via Pix'), warnIfMissed: false);
    expect(sacou, 0);
  });

  testWidgets('Ver tudo chama o callback', (tester) async {
    var abriu = 0;
    await _abrir(tester, CarteiraTela(aoVerTudo: () => abriu++));
    await tester.tap(find.text('Ver tudo'));
    expect(abriu, 1);
  });

  testWidgets('estado vazio: sem extrato e sem Ver tudo', (tester) async {
    await _abrir(tester,
        CarteiraTela(dados: DadosExemploCarteira.vazio, aoVerTudo: () {}));
    expect(find.text('Nenhum serviço ainda'), findsOneWidget);
    expect(find.text('Ver tudo'), findsNothing);
    expect(find.text('R\$ 0,00'), findsNWidgets(3));
  });

  testWidgets('estado de erro mostra a mensagem e tenta de novo',
      (tester) async {
    var tentou = 0;
    await _abrir(
      tester,
      CarteiraTela(
          dados: DadosExemploCarteira.comErro,
          aoTentarNovamente: () => tentou++),
    );
    expect(find.text('Não foi possível carregar a carteira.'), findsOneWidget);
    expect(find.text('Sacar via Pix'), findsNothing);
    await tester.tap(find.text('Tentar de novo'));
    expect(tentou, 1);
  });

  const tamanhos = {
    '320x640': Size(320, 640),
    '390x844': Size(390, 844),
    '768x1024': Size(768, 1024),
  };
  final variantes = {
    'completo': DadosExemploCarteira.completo,
    'vazio': DadosExemploCarteira.vazio,
    'erro': DadosExemploCarteira.comErro,
  };
  for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
    for (final escala in [1.0, Responsivo.escalaFonteMaxima]) {
      for (final MapEntry(key: variante, value: dados) in variantes.entries) {
        testWidgets('sem estouro — carteira $variante — $nome, fonte x$escala',
            (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _abrir(tester, CarteiraTela(dados: dados), tamanho: tamanho);
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, -3000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
