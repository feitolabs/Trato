import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart' hide ResumoCarteira;
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

DetalhePedido _detalhe({DateTime? bloqueadoAte}) => DetalhePedido(
      pedido: const PedidoAberto(
        id: 'ped-1',
        titulo: 'Instalar chuveiro',
        bairro: 'Savassi',
        prazo: 'até sexta',
        urgente: false,
        permiteExclusividade: true,
        estado: 'aberto',
      ),
      fechaEm: 'Publicado agora',
      clienteResumo: 'Para até 25/11',
      legendasFotos: const [],
      descricao: 'Trocar resistência.',
      linhas: const [LinhaDetalhe('Modalidade', 'Presencial')],
      exclusividades: const ResumoExclusividades(saldoProfissional: 200),
      bloqueadoRecusa: bloqueadoAte != null && bloqueadoAte.isAfter(DateTime.now()),
      bloqueadoAte: bloqueadoAte,
    );

Widget _detalheTela(DetalhePedido d) => DetalhePedidoTela(
      dados: d,
      aoPedirExclusividade: (_) async =>
          const ExclusividadeProfissional(id: 'e', pedidoId: 'ped-1', status: 'ativa'),
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

  group('F12 — bloqueio de exclusividade (bloqueado_ate)', () {
    test('ExclusividadeApi lê bloqueado_ate e tolera a ausência', () {
      final base = {
        'id': 'e1',
        'pedido_id': 'p1',
        'status': 'recusada',
        'criada_em': '2026-11-20T10:00:00Z',
      };
      expect(ExclusividadeApi.deJson(base).bloqueadoAte, isNull);
      expect(
        ExclusividadeApi.deJson({...base, 'bloqueado_ate': null}).bloqueadoAte,
        isNull,
      );
      expect(
        ExclusividadeApi.deJson({...base, 'bloqueado_ate': '2026-11-25T15:30:00Z'}).bloqueadoAte,
        DateTime.utc(2026, 11, 25, 15, 30),
      );
    });

    testWidgets('bloqueio futuro: avisa quando poderá tentar de novo', (tester) async {
      final fim = DateTime.now().add(const Duration(days: 3));
      await _abrir(tester, _detalheTela(_detalhe(bloqueadoAte: fim)));
      expect(find.textContaining('Você poderá tentar de novo em '), findsOneWidget);
    });

    testWidgets('bloqueio já passado ou nulo: sem aviso de bloqueio', (tester) async {
      await _abrir(
        tester,
        _detalheTela(_detalhe(bloqueadoAte: DateTime.now().subtract(const Duration(days: 1)))),
      );
      expect(find.textContaining('Você poderá tentar de novo'), findsNothing);
      await _abrir(tester, _detalheTela(_detalhe()));
      expect(find.textContaining('Você poderá tentar de novo'), findsNothing);
      expect(find.textContaining('oferta recusada por este cliente'), findsNothing);
    });
  });
}
