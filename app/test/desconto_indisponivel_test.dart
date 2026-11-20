import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/comuns/desconto_moedas.dart';
import 'package:trato/telas/comuns/moedas_ganhas_tela.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/pagamento/dados_exemplo.dart' as expag;

Widget _pagamento(DadosPagamento dados) => MaterialApp(
      theme: TemaTrato.claro,
      home: PagamentoTela(
        dados: dados,
        aoAlternarMoedas: (usar, cupom) async => dados,
      ),
    );

void main() {
  final base = expag.DadosExemplo.pagamento.copiarCom(moedasSaldo: 5000);

  testWidgets('orçamento esgotado: sem interruptor e com a mensagem', (tester) async {
    await tester.pumpWidget(_pagamento(base.copiarCom(
      descontoDisponivel: false,
      descontoIndisponivelMotivo: MotivoDescontoIndisponivel.orcamentoEsgotado,
    )));
    expect(find.byKey(const Key('interruptor-moedas')), findsNothing);
    expect(find.text('Desconto indisponível agora'), findsOneWidget);
    expect(
      find.textContaining('Desconto indisponível agora. Ele volta no próximo mês.'),
      findsOneWidget,
    );
  });

  testWidgets('teto do cliente: sem interruptor e com a mensagem do teto', (tester) async {
    await tester.pumpWidget(_pagamento(base.copiarCom(
      descontoDisponivel: false,
      descontoIndisponivelMotivo: MotivoDescontoIndisponivel.tetoCliente,
    )));
    expect(find.byKey(const Key('interruptor-moedas')), findsNothing);
    expect(
      find.textContaining('Você já usou o desconto máximo deste mês. Ele volta no próximo mês.'),
      findsOneWidget,
    );
  });

  testWidgets('campo ausente (backend antigo): interruptor normal', (tester) async {
    expect(base.descontoDisponivel, isTrue);
    await tester.pumpWidget(_pagamento(base));
    expect(find.byKey(const Key('interruptor-moedas')), findsOneWidget);
    expect(find.byKey(const Key('moedas-indisponivel')), findsNothing);
  });

  testWidgets('limite diário: mensagem de hoje/amanhã', (tester) async {
    await tester.pumpWidget(_pagamento(base.copiarCom(
      descontoDisponivel: false,
      descontoIndisponivelMotivo: MotivoDescontoIndisponivel.limiteDiario,
    )));
    expect(find.byKey(const Key('interruptor-moedas')), findsNothing);
    expect(
      find.textContaining('O desconto de hoje já acabou. Ele volta amanhã.'),
      findsOneWidget,
    );
  });

  testWidgets('saldo no pagamento também em reais quando o valor da moeda vem', (tester) async {
    await tester.pumpWidget(_pagamento(base.copiarCom(moedasSaldo: 50, moedaValorCentavos: 1)));
    expect(find.text('Você tem 50 Tratinhos = R\$ 0,50'), findsOneWidget);
  });

  test('textos de Tratinhos: singular, reais e pendentes', () {
    expect(textoTratinhos(1), '1 Tratinho');
    expect(textoTratinhosEmReais(50, 1), '50 Tratinhos = R\$ 0,50');
    expect(textoTratinhosEmReais(50, null), '50 Tratinhos');
    expect(textoTratinhosPendentes(0, null, 1), isNull);
    expect(
      textoTratinhosPendentes(50, lerDataIso('2026-11-27'), 1),
      'Você tem 50 Tratinhos a liberar em 27/11 (R\$ 0,50)',
    );
    expect(textoTratinhosPendentes(50, null, null), 'Você tem 50 Tratinhos a liberar');
    expect(lerDataIso(null), isNull);
    expect(lerDataIso('x'), isNull);
  });

  test('motivo desconhecido não quebra', () {
    expect(MotivoDescontoIndisponivel.deTexto('outro'), isNull);
    expect(MotivoDescontoIndisponivel.deTexto(null), isNull);
    expect(MotivoDescontoIndisponivel.deTexto('limite_diario'),
        MotivoDescontoIndisponivel.limiteDiario);
    expect(
        MotivoDescontoIndisponivel.deTexto('teto_cliente'), MotivoDescontoIndisponivel.tetoCliente);
  });

  PerfilCliente perfil({
    bool disponivel = true,
    MotivoDescontoIndisponivel? motivo,
    int pendentes = 0,
    int? valorMoeda,
    int moedas = 300,
  }) =>
      PerfilCliente(
        nome: 'Ana',
        iniciais: 'A',
        resumo: '',
        grupos: const [],
        moedas: moedas,
        moedasPendentes: pendentes,
        moedasProximaLiberacao: pendentes > 0 ? DateTime(2026, 11, 27) : null,
        moedasValorCentavos: valorMoeda,
        moedasDescontoDisponivel: disponivel,
        moedasDescontoMotivo: motivo,
      );

  testWidgets('perfil: linha discreta só quando indisponível', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PerfilClienteTela(
        perfil: perfil(disponivel: false, motivo: MotivoDescontoIndisponivel.tetoCliente),
      ),
    ));
    expect(find.byKey(const Key('moedas-desconto-indisponivel')), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PerfilClienteTela(perfil: perfil()),
    ));
    expect(find.byKey(const Key('moedas-desconto-indisponivel')), findsNothing);
  });

  testWidgets('perfil: Tratinhos a liberar com data e reais; sem pendentes, sem linha',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PerfilClienteTela(perfil: perfil(pendentes: 50, valorMoeda: 1)),
    ));
    expect(find.text('Você tem 50 Tratinhos a liberar em 27/11 (R\$ 0,50)'), findsOneWidget);
    expect(find.text('Seus Tratinhos'), findsOneWidget);
    expect(find.text('300 Tratinhos = R\$ 3,00'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PerfilClienteTela(perfil: perfil()),
    ));
    expect(find.byKey(const Key('moedas-pendentes')), findsNothing);
  });

  testWidgets('perfil: só pendentes (saldo 0) ainda mostra a linha', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PerfilClienteTela(perfil: perfil(moedas: 0, pendentes: 50)),
    ));
    expect(find.byKey(const Key('moedas-pendentes')), findsOneWidget);
  });

  testWidgets('moedas ganhas: linha de pendentes e reais só quando vierem', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: MoedasGanhasTela(
        moedas: 50,
        pendentes: 50,
        proximaLiberacao: DateTime(2026, 11, 27),
        valorMoedaCentavos: 1,
        aoContinuar: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Você tem 50 Tratinhos a liberar em 27/11 (R\$ 0,50)'), findsOneWidget);
    expect(find.text('50 Tratinhos = R\$ 0,50'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: MoedasGanhasTela(moedas: 50, aoContinuar: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('tratinhos-pendentes')), findsNothing);
    expect(find.byKey(const Key('tratinhos-em-reais')), findsNothing);
  });
}
