import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'apoio/exemplos/telas/carteira/dados_exemplo.dart';
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
  testWidgets('taxa zero: mostra só "Sem taxa", sem "bruto – taxa"', (tester) async {
    await _abrir(
      tester,
      const CarteiraTela(
        dados: DadosCarteira(
          resumo: null,
          extrato: [
            ItemExtrato(
              titulo: 'Pintura',
              detalheData: '26/10/2026',
              brutoCentavos: 40000,
              textoTaxa: 'Toque para ver os valores',
              liquidoCentavos: 40000,
              status: StatusExtrato.liberado,
            ),
          ],
        ),
        soExtrato: true,
      ),
    );
    expect(find.text('Sem taxa'), findsOneWidget);
    expect(find.textContaining('–'), findsNothing);
  });

  testWidgets('mostra saldos e extrato exatamente como vieram do dado', (tester) async {
    await _abrir(
        tester, const CarteiraTela(dados: DadosExemploCarteira.completo, soExtrato: false));

    expect(find.text('R\$ 712,50'), findsOneWidget);
    expect(find.text('R\$ 425,00'), findsOneWidget);
    expect(find.text('R\$ 190,00'), findsNWidgets(3)); // a liberar + 2 líquidos
    expect(find.text('Pix na chave CPF ***.482.***-12 · cai em até 1 dia útil'), findsOneWidget);
    expect(find.text('Serviço em andamento'), findsOneWidget);
    expect(find.text('Repasse do dinheiro: Automático em até 48 h'), findsOneWidget);

    expect(find.text('Instalar 4 luminárias'), findsOneWidget);
    expect(find.textContaining('de taxa'), findsNothing);
    expect(find.text('Sem taxa'), findsNWidgets(4));
    expect(find.text('R\$ 380,00'), findsOneWidget); // líquido do portão
    expect(find.text('Confirmado'), findsNWidgets(3));
    expect(find.text('A liberar'), findsNWidgets(2)); // cartão de saldo + chip
    expect(find.text('Retido'), findsOneWidget);
  });

  testWidgets('a tela não calcula: taxa e líquido mudam só pelo dado', (tester) async {
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
          liquidoCentavos: 12345, // valor "errado" de propósito: a tela não confere
          status: StatusExtrato.aLiberar,
        ),
      ],
    );
    await _abrir(tester, const CarteiraTela(dados: dados, soExtrato: false));

    expect(find.textContaining('de taxa'), findsNothing);
    expect(find.text('Sem taxa'), findsOneWidget);
    expect(find.text('R\$ 123,45'), findsOneWidget);
    expect(find.text('Repasse do dinheiro: Automático em até 7 dias'), findsOneWidget);
    expect(find.textContaining('5%'), findsNothing);
  });

  testWidgets('F35: card escuro, Retido, A liberar, extrato com chips e sem taxa', (tester) async {
    var abriu = 0;
    await _abrir(
      tester,
      CarteiraTela(
        soExtrato: false,
        aoConfigurarRecebimento: () => abriu++,
        dados: const DadosCarteira(
          resumo: ResumoCarteira(
            disponivelCentavos: 71250,
            textoPix: 'Pix na chave CPF ***.482.***-12',
            retidoCentavos: 42500,
            textoRetido: 'Serviço em andamento',
            aLiberarCentavos: 19000,
            textoALiberar: 'Automático em até 48 horas',
          ),
          contaRecebimento: ContaRecebimento(cadastrada: true, chavePixMascarada: '***.482.***-12'),
          extrato: [
            ItemExtrato(
              titulo: 'Instalar luminárias',
              detalheData: 'Ontem · aguardando confirmação',
              brutoCentavos: 20000,
              textoTaxa: 'x',
              liquidoCentavos: 20000,
              status: StatusExtrato.aLiberar,
            ),
            ItemExtrato(
              titulo: 'Pintura de portão',
              detalheData: '26/10/2026',
              brutoCentavos: 40000,
              textoTaxa: 'x',
              liquidoCentavos: 40000,
              status: StatusExtrato.liberado,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Carteira'), findsOneWidget);
    // Bloco 1: card escuro com o disponível, a chave Pix e o botão de conta (sem saque).
    expect(find.text('Disponível para saque'), findsOneWidget);
    expect(find.text('R\$ 712,50'), findsOneWidget);
    expect(find.text('Pix na chave CPF ***.482.***-12'), findsOneWidget);
    expect(find.text('Sacar via Pix'), findsNothing);
    await tester.tap(find.byKey(const Key('botao-alterar-conta')));
    expect(abriu, 1);
    expect(find.text('Alterar conta de recebimento'), findsOneWidget);
    // Bloco 2: Retido e A liberar lado a lado.
    expect(find.text('Retido'), findsOneWidget);
    expect(find.text('R\$ 425,00'), findsOneWidget);
    expect(find.text('Serviço em andamento'), findsOneWidget);
    expect(find.text('R\$ 190,00'), findsOneWidget); // card A liberar
    expect(find.text('R\$ 200,00'), findsOneWidget); // linha do extrato
    expect(find.text('R\$ 400,00'), findsOneWidget);
    expect(find.text('Repasse do dinheiro: Automático em até 48 horas'), findsOneWidget);
    // Bloco 3: extrato com chips, sem texto de taxa e com a conta ativa e a regra de liberação.
    expect(find.text('Extrato por serviço'), findsOneWidget);
    expect(find.text('Conta de recebimento ativa'), findsOneWidget);
    expect(find.byKey(const Key('regra-liberacao')), findsOneWidget);
    expect(find.text('A liberar'), findsNWidgets(2)); // card + chip
    expect(find.text('Confirmado'), findsOneWidget);
    expect(find.text('Sem taxa'), findsNWidgets(2));
    expect(find.textContaining('de taxa'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('F35: sem conta de recebimento ligada não há botão de saque nem de conta',
      (tester) async {
    await _abrir(
      tester,
      const CarteiraTela(dados: DadosExemploCarteira.completo, soExtrato: false),
    );
    expect(find.text('Sacar via Pix'), findsNothing);
    expect(find.byKey(const Key('botao-alterar-conta')), findsNothing);
  });

  testWidgets('Ver tudo chama o callback', (tester) async {
    var abriu = 0;
    await _abrir(
        tester, CarteiraTela(dados: DadosExemploCarteira.completo, aoVerTudo: () => abriu++));
    await tester.tap(find.text('Ver tudo'));
    expect(abriu, 1);
  });

  testWidgets('estado vazio: sem extrato e sem Ver tudo', (tester) async {
    await _abrir(tester,
        CarteiraTela(dados: DadosExemploCarteira.vazio, soExtrato: false, aoVerTudo: () {}));
    expect(find.text('Nenhum serviço ainda'), findsOneWidget);
    expect(find.text('Ver tudo'), findsNothing);
    expect(find.text('R\$ 0,00'), findsNWidgets(3));
  });

  testWidgets('estado de erro mostra a mensagem e tenta de novo', (tester) async {
    var tentou = 0;
    await _abrir(
      tester,
      CarteiraTela(dados: DadosExemploCarteira.comErro, aoTentarNovamente: () => tentou++),
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
        testWidgets('sem estouro — carteira $variante — $nome, fonte x$escala', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _abrir(tester, CarteiraTela(dados: dados), tamanho: tamanho);
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
