import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_catalogo_fake.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/pagamento/dados_exemplo.dart' as pag;

class _PagamentoSemOpcoesDepoisOk extends RepositorioPagamentoFake {
  int chamadas = 0;

  @override
  Future<DadosPagamento> dados(String pedidoId) async {
    chamadas++;
    if (chamadas == 1) {
      return pag.DadosExemplo.pagamento.copiarCom(opcoes: const []);
    }
    return pag.DadosExemplo.pagamento;
  }
}

void main() {
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  testWidgets(
      'opcoes vazias: tocar em Tentar de novo recarrega e mostra a tela de pagamento normal',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pagamento = _PagamentoSemOpcoesDepoisOk();
    RotasTrato.repos = RepositoriosTrato(
      pedidos: RepositorioPedidosFake(),
      orcamentos: RepositorioOrcamentosFake(),
      pagamento: pagamento,
      chat: RepositorioChatFake(),
      notificacoes: RepositorioNotificacoesFake(),
      perfil: RepositorioPerfilFake(),
      profissional: RepositorioProfissionalFake(),
      catalogo: RepositorioCatalogoFake(),
      servicos: RepositorioServicosClienteFake(),
      agenda: RepositorioAgendaFake(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: RotasTrato.pagamentoParaTeste('ped-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pagamento-indisponivel')), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(pagamento.chamadas, 1);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(pagamento.chamadas, 2);
    expect(find.byKey(const Key('pagamento-indisponivel')), findsNothing);
    expect(find.text('Pagamento'), findsOneWidget);
    expect(find.text('Como funciona o pagamento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
