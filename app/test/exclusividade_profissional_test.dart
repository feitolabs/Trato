import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/telas/carteira/avaliar_cliente_tela.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/profissional_inicio/dados_exemplo.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: filho!,
      ),
      home: tela,
    ),
  );
}

DetalhePedido _detalheCom({
  bool urgente = false,
  bool permiteExclusividade = true,
  String estado = 'aberto',
  bool bloqueadoRecusa = false,
  ExclusividadeProfissional? exclusividade,
  ResumoExclusividades? exclusividades,
}) {
  return DetalhePedido(
    pedido: PedidoAberto(
      id: 'ped-1',
      titulo: 'Instalar chuveiro',
      bairro: 'Savassi',
      prazo: urgente ? 'hoje' : 'até sexta',
      urgente: urgente,
      permiteExclusividade: permiteExclusividade,
      estado: estado,
      exclusividade: exclusividade,
    ),
    fechaEm: 'Publicado agora',
    clienteResumo: 'Para até 25/11',
    legendasFotos: const [],
    descricao: 'Trocar resistência e fiação.',
    linhas: const [LinhaDetalhe('Modalidade', 'Presencial')],
    exclusividade: exclusividade,
    exclusividades: exclusividades,
    bloqueadoRecusa: bloqueadoRecusa,
  );
}

void main() {
  group('Exclusividade no detalhe do pedido (profissional)', () {
    testWidgets('não há mais oferta paga pelo profissional', (tester) async {
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            exclusividades: const ResumoExclusividades(saldoProfissional: 200),
          ),
        ),
      );
      expect(find.textContaining('Pedir exclusividade'), findsNothing);
      expect(find.textContaining('100 Tratinhos'), findsNothing);
    });

    testWidgets('reservado pelo cliente: mostra e permite desistir', (tester) async {
      final desistencias = <String>[];
      var falhar = true;
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            estado: 'reservado',
            exclusividade: const ExclusividadeProfissional(
              id: 'exc-c',
              pedidoId: 'ped-1',
              status: 'ativa',
              pagador: 'cliente',
            ),
          ),
          aoDesistirExclusividade: (id) async {
            if (falhar) {
              throw const ErroTrato(TipoErro.recusado, 'Esta exclusividade já terminou.');
            }
            desistencias.add(id);
          },
        ),
      );
      expect(find.text('O cliente reservou este pedido para você'), findsOneWidget);

      Future<void> desistir() async {
        await tester.tap(find.byKey(const ValueKey('desistir-exclusividade')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Desistir'));
        await tester.pumpAndSettle();
      }

      await desistir();
      expect(find.text('Esta exclusividade já terminou.'), findsOneWidget);
      falhar = false;
      await desistir();
      expect(desistencias, ['exc-c']);
      expect(find.textContaining('Os Tratinhos voltaram ao cliente'), findsOneWidget);
    });

    testWidgets('exclusividade antiga (paga pelo profissional) não tem desistir', (tester) async {
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            estado: 'reservado',
            exclusividade: const ExclusividadeProfissional(
                id: 'exc-p', pedidoId: 'ped-1', status: 'ativa'),
          ),
          aoDesistirExclusividade: (_) async {},
        ),
      );
      expect(find.byKey(const ValueKey('desistir-exclusividade')), findsNothing);
    });

    testWidgets('mostra estado Reservado para você com hora que termina', (tester) async {
      final termina = DateTime(2026, 11, 22, 14, 30);
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            estado: 'reservado',
            exclusividade: ExclusividadeProfissional(
              id: 'exc-1',
              pedidoId: 'ped-1',
              status: 'ativa',
              expiraEm: termina,
            ),
          ),
        ),
      );
      expect(find.text('Reservado para você · termina em 22/11 às 14:30'), findsOneWidget);
    });
  });

  group('Início do profissional — card Exclusividades: X de 3', () {
    testWidgets('mostra card X de 3, saldo sem reais e lista curta de ofertas', (tester) async {
      final dados = InicioProfissional(
        nome: 'Carlos',
        disponivelAgora: true,
        carteira: inicioProfissionalExemplo.carteira,
        pedidos: const [
          PedidoAberto(
            id: 'ped-1',
            titulo: 'Instalar chuveiro',
            bairro: 'Savassi',
            prazo: 'amanhã',
            estado: 'reservado',
            exclusividade: ExclusividadeProfissional(
              id: 'e1',
              pedidoId: 'ped-1',
              status: 'ativa',
            ),
          ),
          PedidoAberto(
            id: 'ped-2',
            titulo: 'Trocar tomada',
            bairro: 'Lourdes',
            prazo: 'semana',
            exclusividade: ExclusividadeProfissional(
              id: 'e2',
              pedidoId: 'ped-2',
              status: 'aguardando_cliente',
            ),
          ),
        ],
        exclusividades: const ResumoExclusividades(
          ativasOuPendentes: 2,
          limiteMaximo: 3,
          saldoProfissional: 150,
          moedasPendentesProfissional: 50,
          itens: [
            ExclusividadeProfissional(
              id: 'e1',
              pedidoId: 'ped-1',
              status: 'ativa',
              tituloPedido: 'Instalar chuveiro',
            ),
            ExclusividadeProfissional(
              id: 'e2',
              pedidoId: 'ped-2',
              status: 'aguardando_cliente',
              tituloPedido: 'Trocar tomada',
            ),
          ],
        ),
      );
      await _abrir(tester, InicioProfissionalTela(dados: dados));

      expect(find.text('Exclusividades: 2 de 3'), findsOneWidget);
      expect(find.text('150 Tratinhos'), findsOneWidget);
      expect(find.text('Você tem 50 Tratinhos a liberar'), findsOneWidget);
      expect(
        find.text(
            'Ganhe Tratinhos avaliando clientes. Um cliente pode reservar um pedido para você.'),
        findsOneWidget,
      );
      expect(find.text('Ativa (48h)'), findsOneWidget);
      expect(find.text('Aguardando o cliente'), findsOneWidget);
      expect(find.text('Reservado para você'), findsOneWidget);
      expect(find.text('Oferta enviada, aguardando o cliente'), findsOneWidget);
      expect(find.textContaining('comprar cliente'), findsNothing);
    });
  });

  group('Avaliar cliente — bônus de Tratinhos', () {
    testWidgets('sem número antes de o servidor informar; depois mostra os ganhos',
        (tester) async {
      await _abrir(
        tester,
        AvaliarClienteTela(
          pedidoNumero: '#1234',
          aoEnviar: (_, __) async => 50,
        ),
      );

      expect(find.textContaining('Avaliar o cliente pode render Tratinhos'), findsOneWidget);
      expect(find.textContaining('50'), findsNothing);
      expect(find.textContaining('7 dias'), findsNothing);
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      await tester.pumpAndSettle();

      expect(find.text('+50 Tratinhos a liberar (se não houver disputa).'), findsOneWidget);
      expect(find.textContaining('7 dias'), findsNothing);
      expect(find.text('Continuar'), findsOneWidget);
    });

    testWidgets('não mostra mensagem de Tratinhos quando moedas_ganhas == 0', (tester) async {
      bool? resultado;
      await _abrir(
        tester,
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                resultado = await Navigator.of(ctx).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AvaliarClienteTela(
                      pedidoNumero: '#1234',
                      aoEnviar: (_, __) async => 0,
                    ),
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tratinhos'), findsNothing);
      expect(resultado, isTrue);
    });
  });

  test('modelos da API toleram campos ausentes (backend antigo)', () {
    final lista = ListaExclusividadesApi.deJson(const {});
    expect(lista.itens, isEmpty);
    expect(lista.ativasOuPendentes, 0);
    expect(lista.limiteMaximo, 3);
    expect(lista.saldoProfissional, 0);

    final ex = ExclusividadeApi.deJson({
      'id': 'e1',
      'pedido_id': 'p1',
      'criada_em': '2026-11-20T12:00:00Z',
    });
    expect(ex.status, 'aguardando_cliente');
    expect(ex.moedasCobradas, 100);
  });
}
