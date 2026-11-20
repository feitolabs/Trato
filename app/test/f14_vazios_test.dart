import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/busca/modelos.dart';
import 'package:trato/telas/carteira/conta_recebimento_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/legal/texto_legal_tela.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/notificacoes/servico_fake.dart';

class _BuscaBaixaNota implements ServicoBusca {
  @override
  Future<List<Profissional>> buscar(String termo) async => const [
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
      ];
}

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  test('1. aviso legal neutro, sem repetição nem cidade', () {
    expect(avisoRascunhoLegal, startsWith('Documento oficial em vigor durante o piloto.'));
    expect(avisoRascunhoLegal, isNot(contains('Belo Horizonte')));
  });

  group('6. notificações vazias', () {
    testWidgets('com preferências: botão "Ajustar avisos" leva às configurações', (tester) async {
      var abriu = 0;
      await _abrir(
        tester,
        NotificacoesTela(
          servico: ServicoNotificacoesFake(itens: const []),
          aoAbrirPreferencias: () => abriu++,
        ),
      );
      await tester.tap(find.text('Ajustar avisos'));
      expect(abriu, 1);
    });

    testWidgets('sem preferências: sem o botão', (tester) async {
      await _abrir(tester, NotificacoesTela(servico: ServicoNotificacoesFake(itens: const [])));
      expect(find.text('Nada por aqui'), findsOneWidget);
      expect(find.text('Ajustar avisos'), findsNothing);
    });
  });

  group('7. pedidos vazios', () {
    testWidgets('"Fazer um pedido" chama a ação; sem ação não aparece', (tester) async {
      var fez = 0;
      await _abrir(
        tester,
        SeusPedidosTela(emAndamento: const [], finalizados: const [], aoFazerPedido: () => fez++),
      );
      await tester.tap(find.text('Fazer um pedido'));
      expect(fez, 1);
      await _abrir(tester, const SeusPedidosTela(emAndamento: [], finalizados: []));
      expect(find.text('Fazer um pedido'), findsNothing);
    });
  });

  testWidgets('8. busca sem resultado com filtros: "Limpar filtros" traz os resultados de volta',
      (tester) async {
    await _abrir(
      tester,
      BuscaProfissionaisTela(servico: _BuscaBaixaNota(), sugestoes: const [], termoInicial: 'eletrica'),
    );
    expect(find.text('Bruno K.'), findsOneWidget);
    await tester.tap(find.text('Nota 4,5+'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum resultado com esses filtros'), findsOneWidget);
    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Bruno K.'), findsOneWidget);
  });

  group('2. conta de recebimento', () {
    Widget tela({Future<DateTime?> Function()? carregar}) => ContaRecebimentoTela(
          inicial: const ContaRecebimento(cadastrada: false),
          aoSalvar: ({required tipoPix, required chavePix, bancoCodigo, bancoNome, agencia, conta, tipoConta}) async =>
              const ContaRecebimento(cadastrada: true),
          carregarProximaLiberacao: carregar,
        );

    testWidgets('com data prevista: mostra dd/mm e explica o titular', (tester) async {
      await _abrir(tester, tela(carregar: () async => DateTime(2026, 12, 3)));
      expect(find.textContaining('Próximo repasse previsto: 03/12'), findsOneWidget);
      expect(find.textContaining('a conta precisa estar no seu nome'), findsOneWidget);
      expect(find.textContaining('48'), findsNothing);
    });

    testWidgets('sem data ou com falha: texto geral, sem quebrar', (tester) async {
      await _abrir(tester, tela());
      expect(find.textContaining('o repasse é enviado para a conta do mesmo titular'), findsOneWidget);
      await _abrir(tester, tela(carregar: () async => throw Exception('rede')));
      expect(find.textContaining('o repasse é enviado para a conta do mesmo titular'), findsOneWidget);
    });
  });
}
