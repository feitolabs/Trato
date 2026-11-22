import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/tema/tema.dart';

Widget _envolver(Widget child) => MaterialApp(theme: TemaTrato.claro, home: child);

const _opcoesPadrao = [
  OpcaoPagamento(
    metodo: MetodoPagamento.cartao,
    titulo: 'Cartão de crédito',
    descricao: 'À vista sem taxa',
  ),
];

void main() {
  group('F62 — Tratinhos restantes ao ligar desconto no pagamento', () {
    testWidgets('saldo 700 e usadas 500 mostra "restam 200 Tratinhos"', (tester) async {
      const inicial = DadosPagamento(
        subtitulo: 'Carlos · Elétrica',
        valorAgoraCentavos: 20000,
        opcoes: _opcoesPadrao,
        moedasSaldo: 700,
        moedaValorCentavos: 1,
      );

      await tester.pumpWidget(
        _envolver(
          PagamentoTela(
            dados: inicial,
            aoAlternarMoedas: (usar, _) async => inicial.copiarCom(
              valorAgoraCentavos: usar ? 19500 : 20000,
              moedasUsadas: usar ? 500 : 0,
              moedasDescontoCentavos: usar ? 500 : 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('interruptor-moedas')));
      await tester.pumpAndSettle();

      expect(
        find.text('Usando 500 Tratinhos · desconto de R\$ 5,00 · restam 200 Tratinhos'),
        findsOneWidget,
      );
    });

    testWidgets('saldo 100 e usadas 100 não mostra "restam"', (tester) async {
      const inicial = DadosPagamento(
        subtitulo: 'Carlos · Elétrica',
        valorAgoraCentavos: 20000,
        opcoes: _opcoesPadrao,
        moedasSaldo: 100,
        moedaValorCentavos: 1,
      );

      await tester.pumpWidget(
        _envolver(
          PagamentoTela(
            dados: inicial,
            aoAlternarMoedas: (usar, _) async => inicial.copiarCom(
              valorAgoraCentavos: usar ? 19900 : 20000,
              moedasUsadas: usar ? 100 : 0,
              moedasDescontoCentavos: usar ? 100 : 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('interruptor-moedas')));
      await tester.pumpAndSettle();

      expect(
        find.text('Usando 100 Tratinhos · desconto de R\$ 1,00'),
        findsOneWidget,
      );
      expect(find.textContaining('restam'), findsNothing);
    });
  });
}
