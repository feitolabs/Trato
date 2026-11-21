import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/comuns/desconto_moedas.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/pagamento/dados_exemplo.dart' as expag;

const _explicacao =
    'O desconto é pago pelo Trato e tem limite por dia e por mês. Seus Tratinhos continuam guardados.';

Widget _pagamento(
  DadosPagamento dados, {
  Future<DadosPagamento> Function(bool, String?)? aoAlternar,
}) =>
    MaterialApp(
      theme: TemaTrato.claro,
      home: PagamentoTela(
        dados: dados,
        aoAlternarMoedas: aoAlternar ?? (usar, cupom) async => dados,
      ),
    );

void main() {
  final base = expag.DadosExemplo.pagamento.copiarCom(moedasSaldo: 5000);

  group('indisponível com data e motivo', () {
    testWidgets('orçamento esgotado com data: volta no dia 1º (01/12)', (tester) async {
      await tester.pumpWidget(_pagamento(base.copiarCom(
        descontoDisponivel: false,
        descontoIndisponivelMotivo: MotivoDescontoIndisponivel.orcamentoEsgotado,
        descontoVoltaEm: DateTime(2026, 12, 1),
      )));
      expect(
        find.text('Desconto indisponível agora. Ele volta no dia 1º (01/12). $_explicacao'),
        findsOneWidget,
      );
    });

    testWidgets('teto do cliente com data: volta no dia 1º (01/12)', (tester) async {
      await tester.pumpWidget(_pagamento(base.copiarCom(
        descontoDisponivel: false,
        descontoIndisponivelMotivo: MotivoDescontoIndisponivel.tetoCliente,
        descontoVoltaEm: DateTime(2026, 12, 1),
      )));
      expect(
        find.text('Você já usou o desconto máximo deste mês. '
            'Ele volta no dia 1º (01/12). $_explicacao'),
        findsOneWidget,
      );
    });

    testWidgets('limite diário: volta amanhã (com ou sem data)', (tester) async {
      for (final data in [null, DateTime(2026, 11, 21)]) {
        await tester.pumpWidget(_pagamento(base.copiarCom(
          descontoDisponivel: false,
          descontoIndisponivelMotivo: MotivoDescontoIndisponivel.limiteDiario,
          descontoVoltaEm: data,
        )));
        expect(
          find.text('O desconto de hoje já acabou. Ele volta amanhã. $_explicacao'),
          findsOneWidget,
        );
      }
    });

    testWidgets('sem desconto_volta_em: texto sem data (fallback)', (tester) async {
      await tester.pumpWidget(_pagamento(base.copiarCom(
        descontoDisponivel: false,
        descontoIndisponivelMotivo: MotivoDescontoIndisponivel.orcamentoEsgotado,
      )));
      expect(
        find.text('Desconto indisponível agora. Ele volta no próximo mês. $_explicacao'),
        findsOneWidget,
      );
    });

    testWidgets('a informação aparece antes do botão de pagar', (tester) async {
      await tester.pumpWidget(_pagamento(base.copiarCom(
        descontoDisponivel: false,
        descontoIndisponivelMotivo: MotivoDescontoIndisponivel.orcamentoEsgotado,
      )));
      expect(find.byKey(const Key('moedas-indisponivel')), findsOneWidget);
      final cartao = tester.getTopLeft(find.byKey(const Key('moedas-indisponivel'))).dy;
      final botao = tester.getTopLeft(find.textContaining('Pagar ')).dy;
      expect(cartao, lessThan(botao));
    });

    testWidgets('perfil usa a data quando vier', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: PerfilClienteTela(
          perfil: PerfilCliente(
            nome: 'Ana',
            iniciais: 'A',
            resumo: '',
            grupos: const [],
            moedas: 10,
            moedasDescontoDisponivel: false,
            moedasDescontoMotivo: MotivoDescontoIndisponivel.orcamentoEsgotado,
            moedasDescontoVoltaEm: DateTime(2026, 12, 1),
          ),
        ),
      ));
      expect(find.textContaining('Ele volta no dia 1º (01/12).'), findsOneWidget);
    });
  });

  group('abater até R\$ X', () {
    testWidgets('disponível e com o campo: mostra a linha', (tester) async {
      await tester.pumpWidget(_pagamento(base.copiarCom(descontoPossivelCentavos: 1500)));
      expect(find.text('Você pode abater até R\$ 15,00 neste serviço'), findsOneWidget);
    });

    testWidgets('campo ausente: sem a linha', (tester) async {
      await tester.pumpWidget(_pagamento(base));
      expect(find.byKey(const Key('desconto-possivel')), findsNothing);
    });

    testWidgets('indisponível: sem a linha', (tester) async {
      await tester.pumpWidget(_pagamento(base.copiarCom(
        descontoPossivelCentavos: 1500,
        descontoDisponivel: false,
      )));
      expect(find.byKey(const Key('desconto-possivel')), findsNothing);
    });
  });

  group('frase fixa', () {
    testWidgets('aparece no pagamento, com o texto exato', (tester) async {
      await tester.pumpWidget(_pagamento(base));
      expect(
        find.text('Sem taxa para você neste serviço.'),
        findsOneWidget,
      );
    });

    testWidgets('aparece na tela Criar conta', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: CriarContaTela(servico: ServicoAuthFake()),
      ));
      expect(
        find.text('Sem taxa para você.'),
        findsOneWidget,
      );
    });
  });

  group('erro próprio dos Tratinhos', () {
    testWidgets('falha ao usar: erro visível junto ao cartão, sem cupom na tela', (tester) async {
      await tester.pumpWidget(_pagamento(
        base,
        aoAlternar: (usar, cupom) async => throw Exception('falhou'),
      ));
      expect(find.byKey(const Key('campo-cupom')), findsNothing); // cupom oculto
      await tester.tap(find.byKey(const Key('interruptor-moedas')));
      await tester.pumpAndSettle();
      expect(find.text('Sem conexão. Tente de novo.'), findsOneWidget);
      expect(find.byKey(const Key('erro-moedas')), findsOneWidget);
    });

    testWidgets('o erro some na próxima tentativa que der certo', (tester) async {
      var falhar = true;
      await tester.pumpWidget(_pagamento(
        base,
        aoAlternar: (usar, cupom) async {
          if (falhar) throw Exception('falhou');
          return base;
        },
      ));
      await tester.tap(find.byKey(const Key('interruptor-moedas')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('erro-moedas')), findsOneWidget);
      falhar = false;
      await tester.tap(find.byKey(const Key('interruptor-moedas')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('erro-moedas')), findsNothing);
    });
  });
}
