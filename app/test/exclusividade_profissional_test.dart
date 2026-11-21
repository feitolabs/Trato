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
    testWidgets('mostra botão, saldo, contador e abre folha com os 4 pontos', (tester) async {
      String? chaveRecebida;
      final dados = _detalheCom(
        exclusividades: const ResumoExclusividades(
          ativasOuPendentes: 1,
          limiteMaximo: 3,
          saldoProfissional: 150,
        ),
      );
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: dados,
          aoPedirExclusividade: (chave) async {
            chaveRecebida = chave;
            return const ExclusividadeProfissional(
              id: 'exc-1',
              pedidoId: 'ped-1',
              status: 'aguardando_cliente',
              saldoRestante: 50,
            );
          },
        ),
      );

      expect(find.text('1 de 3 exclusividades em andamento'), findsOneWidget);
      expect(find.text('150 Tratinhos'), findsOneWidget);
      expect(find.byKey(const ValueKey('texto-exclusividade')), findsOneWidget);
      expect(
        find.text(
          '48 horas sem concorrência neste pedido. Se o cliente recusar ou não responder em 6 horas, '
          'seus 100 Tratinhos voltam. Se você não atender em 48 horas, eles não voltam.',
        ),
        findsNWidgets(1),
      );
      expect(find.text('Pedir exclusividade de 48 horas'), findsOneWidget);
      expect(find.textContaining('comprar cliente'), findsNothing);

      await tester.tap(find.text('Pedir exclusividade de 48 horas'));
      await tester.pumpAndSettle();

      // A folha onde ele gasta os 100 Tratinhos repete o texto exato.
      expect(find.byKey(const ValueKey('texto-exclusividade-folha')), findsOneWidget);
      expect(find.textContaining('Se você não atender em 48 horas, eles não voltam.'),
          findsNWidgets(2));
      expect(find.textContaining('NÃO voltam'), findsNothing);

      await tester.tap(find.text('Confirmar por 100 Tratinhos'));
      await tester.pumpAndSettle();

      expect(chaveRecebida, isNotNull);
      expect(find.text('Oferta enviada, aguardando o cliente (prazo de 6h)'), findsOneWidget);
    });

    testWidgets('botão desabilitado por saldo menor que 100', (tester) async {
      var chamou = false;
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            exclusividades: const ResumoExclusividades(saldoProfissional: 50),
          ),
          aoPedirExclusividade: (_) async {
            chamou = true;
            return const ExclusividadeProfissional(id: 'e', pedidoId: 'ped-1', status: 'ativa');
          },
        ),
      );
      expect(
          find.textContaining('Saldo insuficiente: você precisa de 100 Tratinhos'), findsOneWidget);
      await tester.tap(find.text('Pedir exclusividade de 48 horas'));
      await tester.pump();
      expect(chamou, isFalse);
    });

    testWidgets('botão desabilitado por limite de 3 atingido', (tester) async {
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            exclusividades: const ResumoExclusividades(
              ativasOuPendentes: 3,
              limiteMaximo: 3,
              saldoProfissional: 200,
            ),
          ),
          aoPedirExclusividade: (_) async =>
              const ExclusividadeProfissional(id: 'e', pedidoId: 'ped-1', status: 'ativa'),
        ),
      );
      expect(find.textContaining('limite de 3 exclusividades em andamento'), findsOneWidget);
    });

    testWidgets('botão desabilitado para pedido urgente', (tester) async {
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            urgente: true,
            exclusividades: const ResumoExclusividades(saldoProfissional: 200),
          ),
          aoPedirExclusividade: (_) async =>
              const ExclusividadeProfissional(id: 'e', pedidoId: 'ped-1', status: 'ativa'),
        ),
      );
      expect(find.text('Pedidos urgentes não têm exclusividade.'), findsOneWidget);
    });

    testWidgets('botão desabilitado para categoria sem exclusividade', (tester) async {
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            permiteExclusividade: false,
            exclusividades: const ResumoExclusividades(saldoProfissional: 200),
          ),
          aoPedirExclusividade: (_) async =>
              const ExclusividadeProfissional(id: 'e', pedidoId: 'ped-1', status: 'ativa'),
        ),
      );
      expect(find.text('Esta categoria não permite exclusividade.'), findsOneWidget);
    });

    testWidgets('botão desabilitado por bloqueio após recusa', (tester) async {
      await _abrir(
        tester,
        DetalhePedidoTela(
          dados: _detalheCom(
            bloqueadoRecusa: true,
            exclusividades: const ResumoExclusividades(saldoProfissional: 200),
          ),
          aoPedirExclusividade: (_) async =>
              const ExclusividadeProfissional(id: 'e', pedidoId: 'ped-1', status: 'ativa'),
        ),
      );
      expect(
        find.textContaining('oferta recusada por este cliente recentemente'),
        findsOneWidget,
      );
    });

    testWidgets('erro do servidor aparece junto do botão para cada código', (tester) async {
      final erros = <String, String>{
        'saldo_insuficiente': 'Você não tem 100 Tratinhos disponíveis para pedir exclusividade.',
        'limite_simultaneas': 'Você já atingiu o limite de exclusividades em andamento.',
        'pedido_indisponivel': 'Este pedido não está mais disponível para exclusividade.',
        'bloqueado_recusa':
            'Você precisa aguardar antes de pedir exclusividade para este cliente de novo.',
        'pedido_urgente': 'Pedidos urgentes não têm exclusividade.',
        'categoria_sem_exclusividade': 'Esta categoria não permite exclusividade.',
        'proprio_pedido': 'Você não pode pedir exclusividade no seu próprio pedido.',
        'fora_da_area': 'Você não atende a categoria ou a região deste pedido.',
        'indisponivel': 'A exclusividade está indisponível no momento. Tente de novo em instantes.',
      };

      for (final entry in erros.entries) {
        await _abrir(
          tester,
          DetalhePedidoTela(
            dados: _detalheCom(
              exclusividades: const ResumoExclusividades(saldoProfissional: 200),
            ),
            aoPedirExclusividade: (_) async {
              throw ErroTrato(TipoErro.recusado, 'Detalhe bruto', codigo: entry.key);
            },
          ),
        );
        await tester.tap(find.text('Pedir exclusividade de 48 horas'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar por 100 Tratinhos'));
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget);
      }
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
        find.text('Ganhe Tratinhos avaliando clientes e use 100 para pedir 48h de exclusividade.'),
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
    testWidgets('mostra +50 Tratinhos a liberar em 7 dias quando moedas_ganhas > 0',
        (tester) async {
      await _abrir(
        tester,
        AvaliarClienteTela(
          pedidoNumero: '#1234',
          aoEnviar: (_, __) async => 50,
        ),
      );

      expect(find.textContaining('Avaliar o cliente vale +50 Tratinhos (1 por cliente)'),
          findsOneWidget);
      expect(find.textContaining('Tratinhos liberados: '), findsOneWidget);
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('+50 Tratinhos a liberar em 7 dias (se não houver disputa)'),
        findsOneWidget,
      );
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
