import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_aberto_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1200);
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

Widget _pedidoComOferta({
  OfertaExclusividadeCliente? oferta,
  String estado = 'aberto',
  Future<OfertaExclusividadeCliente> Function(String, String)? aoResponder,
}) {
  return PedidoAbertoTela(
    numero: 'AB12',
    dados: DadosDoPedido(
      titulo: 'Trocar chuveiro',
      descricao: 'Chuveiro queimado no banheiro.',
      faixaMaxCentavos: 30000,
      estado: estado,
      ofertaExclusividade: oferta,
    ),
    aoSalvar: ({
      required String descricao,
      required int faixaMaxCentavos,
      required String logradouro,
      required String numero,
      required String bairro,
      String? cep,
    }) async =>
        null,
    aoVerOrcamentos: () {},
    aoResponderExclusividade: aoResponder,
  );
}

void main() {
  group('Exclusividade no detalhe do pedido do cliente (F2)', () {
    testWidgets('mostra oferta aguardando_cliente com Sem compromisso e botões de mesmo destaque',
        (tester) async {
      final oferta = OfertaExclusividadeCliente(
        id: 'exc-1',
        pedidoId: 'ped-1',
        profissionalId: 'prof-1',
        profissionalNome: 'Carlos M.',
        notaPublica: 4.9,
        status: 'aguardando_cliente',
        responderAte: DateTime(2026, 11, 20, 20, 30),
        texto: 'Sem compromisso',
      );
      await _abrir(
        tester,
        _pedidoComOferta(
          oferta: oferta,
          aoResponder: (_, __) async => oferta,
        ),
      );

      expect(find.text('Sem compromisso'), findsOneWidget);
      expect(find.text('Aceitar é sem compromisso de contratar.'), findsOneWidget);
      expect(find.textContaining('cancelar a reserva'), findsNothing);
      expect(find.text('Carlos M. · nota 4,9'), findsOneWidget);
      expect(find.text('Responda até 20/11 às 20:30'), findsOneWidget);
      expect(find.textContaining('48 horas exclusivas'), findsOneWidget);
      expect(
          find.textContaining('Outros orçamentos já recebidos continuam visíveis'), findsOneWidget);
      expect(find.textContaining('comprar cliente'), findsNothing);
      expect(find.textContaining('Tratinho'), findsNothing);

      final btnRecusar = find.widgetWithText(BotaoSecundario, 'Recusar e ver outros');
      final btnAceitar = find.widgetWithText(BotaoSecundario, 'Aceitar');
      expect(btnRecusar, findsOneWidget);
      expect(btnAceitar, findsOneWidget);
      // Mesmo destaque visual: ambos são BotaoSecundario com mesma altura na mesma linha.
      expect(
        tester.getSize(btnRecusar).height,
        tester.getSize(btnAceitar).height,
      );
    });

    testWidgets('aceitar previne duplo clique e muda para estado Reservado', (tester) async {
      final completer = Completer<OfertaExclusividadeCliente>();
      var chamadas = 0;
      String? decisaoEnviada;
      final oferta = OfertaExclusividadeCliente(
        id: 'exc-1',
        pedidoId: 'ped-1',
        profissionalNome: 'Carlos M.',
        notaPublica: 4.9,
        status: 'aguardando_cliente',
        responderAte: DateTime(2026, 11, 20, 20, 30),
      );
      await _abrir(
        tester,
        _pedidoComOferta(
          oferta: oferta,
          aoResponder: (_, decisao) {
            chamadas++;
            decisaoEnviada = decisao;
            return completer.future;
          },
        ),
      );

      await tester.tap(find.text('Aceitar'));
      await tester.pump();
      // Segundo toque enquanto em voo deve ser ignorado.
      await tester.tap(find.text('Aceitar'));
      await tester.pump();
      expect(chamadas, 1);
      expect(decisaoEnviada, 'aceitar');

      completer.complete(
        OfertaExclusividadeCliente(
          id: 'exc-1',
          pedidoId: 'ped-1',
          profissionalNome: 'Carlos M.',
          status: 'ativa',
          expiraEm: DateTime(2026, 11, 22, 15, 0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reservado para Carlos M. até 22/11 às 15:00'), findsOneWidget);
      expect(find.text('Outros orçamentos já enviados continuam disponíveis.'), findsOneWidget);
    });

    testWidgets('recusar chama decisão recusar e mantém outros orçamentos disponíveis',
        (tester) async {
      String? decisaoEnviada;
      const oferta = OfertaExclusividadeCliente(
        id: 'exc-1',
        pedidoId: 'ped-1',
        profissionalNome: 'Carlos M.',
        status: 'aguardando_cliente',
      );
      await _abrir(
        tester,
        _pedidoComOferta(
          oferta: oferta,
          aoResponder: (_, decisao) async {
            decisaoEnviada = decisao;
            return const OfertaExclusividadeCliente(
              id: 'exc-1',
              pedidoId: 'ped-1',
              status: 'recusada',
            );
          },
        ),
      );

      await tester.tap(find.text('Recusar e ver outros'));
      await tester.pumpAndSettle();

      expect(decisaoEnviada, 'recusar');
      expect(
        find.text('Oferta recusada. Seus outros orçamentos continuam disponíveis.'),
        findsOneWidget,
      );
    });

    testWidgets('exibe estado reservado quando oferta já está ativa', (tester) async {
      final oferta = OfertaExclusividadeCliente(
        id: 'exc-1',
        pedidoId: 'ped-1',
        profissionalNome: 'Ana R.',
        status: 'ativa',
        expiraEm: DateTime(2026, 11, 23, 9, 15),
      );
      await _abrir(
        tester,
        _pedidoComOferta(oferta: oferta, estado: 'reservado'),
      );

      expect(find.text('Reservado'), findsOneWidget);
      expect(find.text('Reservado para Ana R. até 23/11 às 09:15'), findsOneWidget);
      expect(find.text('Outros orçamentos já enviados continuam disponíveis.'), findsOneWidget);
    });

    testWidgets('mostra erro amigável por código prazo_vencido', (tester) async {
      const oferta = OfertaExclusividadeCliente(
        id: 'exc-1',
        pedidoId: 'ped-1',
        profissionalNome: 'Carlos M.',
        status: 'aguardando_cliente',
      );
      await _abrir(
        tester,
        _pedidoComOferta(
          oferta: oferta,
          aoResponder: (_, __) async {
            throw const ErroTrato(
              TipoErro.recusado,
              'Expirado',
              codigoHttp: 409,
              codigo: 'prazo_vencido',
            );
          },
        ),
      );

      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'O prazo para responder acabou. A oferta expirou e seus outros orçamentos seguem valendo.',
        ),
        findsOneWidget,
      );
    });

    test('modelos da API toleram campos opcionais ausentes', () {
      final oferta = OfertaExclusividadeApi.deJson({
        'id': 'exc-1',
        'pedido_id': 'ped-1',
      });
      expect(oferta.status, 'aguardando_cliente');
      expect(oferta.texto, 'Sem compromisso');

      final resp = RespostaExclusividadeApi.deJson({
        'id': 'exc-1',
        'pedido_id': 'ped-1',
        'status': 'ativa',
      });
      expect(resp.outrosOrcamentosContinuamVisiveis, isTrue);
      expect(resp.pedidoEstado, 'aberto');
    });
  });
}
