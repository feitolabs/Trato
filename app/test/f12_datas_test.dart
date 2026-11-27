import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pump();
}

PerfilCliente _perfil({DateTime? vence, int? teto, int? usado}) => PerfilCliente(
      nome: 'Ana',
      iniciais: 'A',
      resumo: '',
      grupos: const [],
      moedas: 300,
      moedasVenceEm: vence,
      tetoDescontoMesCentavos: teto,
      descontoUsadoMesCentavos: usado,
    );

ResumoCarteira _resumo({DateTime? proxima}) => ResumoCarteira(
      disponivelCentavos: 0,
      textoPix: 'Pix',
      retidoCentavos: 0,
      textoRetido: 'Em andamento',
      aLiberarCentavos: 1000,
      textoALiberar: 'Automático em até 48 h',
      proximaLiberacao: proxima,
    );

void main() {
  group('F12 — repasse com data (proxima_liberacao_em)', () {
    testWidgets('com data: mostra dd/mm no lugar do prazo', (tester) async {
      await _abrir(
        tester,
        CarteiraTela(
          dados: DadosCarteira(resumo: _resumo(proxima: DateTime(2026, 12, 3))),
          soExtrato: false,
        ),
      );
      expect(find.text('Repasse do dinheiro: 03/12'), findsOneWidget);
    });

    testWidgets('sem data: mantém o texto atual', (tester) async {
      await _abrir(
        tester,
        CarteiraTela(dados: DadosCarteira(resumo: _resumo()), soExtrato: false),
      );
      expect(find.text('Repasse do dinheiro: Automático em até 48 h'), findsOneWidget);
    });
  });

  group('F12 — Tratinhos do cliente (vencimento e teto do mês)', () {
    testWidgets('com os campos: mostra vencimento e desconto usado', (tester) async {
      await _abrir(
        tester,
        PerfilClienteTela(
          perfil: _perfil(vence: DateTime(2027, 2, 18), teto: 500, usado: 150),
        ),
      );
      expect(find.text('Tratinhos vencem em 18/02'), findsOneWidget);
      expect(find.text('Desconto usado no mês: R\$ 1,50 de R\$ 5,00'), findsOneWidget);
    });

    testWidgets('sem os campos (backend antigo): nenhuma das linhas', (tester) async {
      await _abrir(tester, PerfilClienteTela(perfil: _perfil()));
      expect(find.byKey(const Key('moedas-vencem')), findsNothing);
      expect(find.byKey(const Key('moedas-desconto-mes')), findsNothing);
    });

    testWidgets('só o teto, sem o usado: não mostra a linha do mês', (tester) async {
      await _abrir(tester, PerfilClienteTela(perfil: _perfil(teto: 500)));
      expect(find.byKey(const Key('moedas-desconto-mes')), findsNothing);
    });
  });

}
