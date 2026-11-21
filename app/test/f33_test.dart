import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/lgpd/central_privacidade_tela.dart';
import 'package:trato/telas/lgpd/modelos.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _pedidoJson({bool? urgente}) => {
      'id': 'ab12cd34',
      'estado': 'em_andamento',
      'estado_nome': 'Em andamento',
      'cliente_id': 'c1',
      'aberto_em': '2026-11-21T10:00:00Z',
      'acoes_permitidas': <String>[],
      'categoria_nome': 'Eletricista',
      if (urgente != null) 'urgente': urgente,
    };

RepositorioPedidosApi _repo(List<String> corpos, {bool? urgente}) {
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((req) async {
      corpos.add(req.body);
      final json = req.method == 'GET' ? [_pedidoJson(urgente: urgente)] : _pedidoJson();
      return http.Response(jsonEncode(json), req.method == 'GET' ? 200 : 201,
          headers: {'content-type': 'application/json'});
    }),
  );
  return RepositorioPedidosApi(api);
}

class _PrivacidadeFake implements ServicoPrivacidade {
  @override
  Future<List<Consentimento>> consentimentos() async => consentimentosPadrao;
  @override
  Future<void> alterarConsentimento(String id, {required bool ativo}) async {}
  @override
  Future<String?> solicitarExportacao() async => null;
  @override
  Future<void> solicitarExclusao() async {}
}

void main() {
  group('F33 · selo Urgente de ponta a ponta', () {
    test('o envio leva urgente=true quando o cliente escolhe "É urgente"', () async {
      final corpos = <String>[];
      await _repo(corpos).criar(
        const RascunhoPedido(
          servicos: ['Aula'],
          quantidade: 1,
          voltagem: '',
          descricao: 'd',
          prazo: 'Urgente · 21/11/2026',
          urgente: true,
          faixa: FaixaPreco(minimoCentavos: 0, maximoCentavos: 0),
          categoriaId: 'cat',
          cidadeId: 'bh',
          modalidade: Modalidade.remoto,
        ),
      );
      expect((jsonDecode(corpos.single) as Map)['urgente'], isTrue);
    });

    testWidgets('lista do cliente: urgente=true da API vira o selo "Urgente"', (tester) async {
      final lista = await _repo([], urgente: true).listar();
      await _abrir(
        tester,
        SeusPedidosTela(emAndamento: lista.emAndamento, finalizados: lista.finalizados),
      );
      expect(find.byKey(const ValueKey('selo-urgente')), findsOneWidget);
      expect(find.text('Urgente'), findsOneWidget);
    });

    testWidgets('API sem o campo urgente: sem selo e sem quebrar', (tester) async {
      final lista = await _repo([]).listar();
      await _abrir(
        tester,
        SeusPedidosTela(emAndamento: lista.emAndamento, finalizados: lista.finalizados),
      );
      expect(find.byKey(const ValueKey('selo-urgente')), findsNothing);
    });
  });

  group('F33 · exclusão agendada', () {
    test('o Perfil do cliente mantém exclusaoAgendadaEm ao filtrar os itens', () {
      final data = DateTime(2026, 11, 28);
      final perfil = PerfilCliente(
        nome: 'Ana',
        iniciais: 'A',
        resumo: '',
        grupos: const [],
        exclusaoAgendadaEm: data,
      );
      expect(RotasTrato.soNoPerfilParaTeste(perfil).exclusaoAgendadaEm, data);
    });

    testWidgets('Meus dados mostra o aviso com a data e cancela a exclusão', (tester) async {
      var cancelou = 0;
      await _abrir(
        tester,
        CentralPrivacidadeTela(
          servico: _PrivacidadeFake(),
          carregarExclusaoAgendada: () async => DateTime(2026, 11, 28),
          aoCancelarExclusao: () async {
            cancelou++;
            return true;
          },
        ),
      );
      expect(find.byKey(const ValueKey('aviso-exclusao-agendada')), findsOneWidget);
      expect(find.textContaining('28/11'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('botao-cancelar-exclusao')));
      await tester.pumpAndSettle();
      expect(cancelou, 1);
      expect(find.byKey(const ValueKey('aviso-exclusao-agendada')), findsNothing);
      expect(find.text('Exclusão cancelada. Sua conta continua ativa.'), findsOneWidget);
    });

    testWidgets('Meus dados sem exclusão agendada não mostra aviso', (tester) async {
      await _abrir(
        tester,
        CentralPrivacidadeTela(
          servico: _PrivacidadeFake(),
          carregarExclusaoAgendada: () async => null,
          aoCancelarExclusao: () async => true,
        ),
      );
      expect(find.byKey(const ValueKey('aviso-exclusao-agendada')), findsNothing);
    });
  });
}
