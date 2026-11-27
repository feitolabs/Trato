// FIX-C (qa12): conclusão só para consulta (C15), estado real nas Conversas (C16/P15) e
// "Caso em análise" só com caso aberto (C18).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/chip_status.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios.dart' show PedidosDoCliente;
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/conclusao/dados_exemplo.dart';
import 'apoio/fontes.dart';

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(
      theme: TemaTrato.claro,
      builder: (c, f) => EscalaFonteLimitada(child: f!),
      home: tela,
    );

/// API simulada de um pedido no [estado], com as [acoes] que o servidor permite ao cliente.
RepositorioPedidosApi _repo(String estado, List<String> acoes, [List<String>? chamadas]) {
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((req) async {
      final caminho = req.url.path;
      chamadas?.add(caminho);
      final Object corpo = switch (caminho) {
        '/v1/pedidos/cca51234' => {
            'id': 'cca51234',
            'cliente_id': 'cli-1',
            'profissional_id': 'pro-1',
            'profissional_nome': 'Carlos M.',
            'estado': estado,
            'estado_nome': estado,
            'aberto_em': '2026-11-20T10:00:00Z',
            'acoes_permitidas': acoes,
            'codigo_conclusao': '7310',
          },
        '/v1/pedidos/cca51234/saldo' => {
            'pedido_id': 'cca51234',
            'cliente_pagou_centavos': 10000,
            'retido_centavos': 10000,
            'a_liberar_centavos': 0,
            'liberado_centavos': 0,
          },
        '/v1/contratos/cca51234/garantia' => {'dias': 90},
        _ => <Object>[],
      };
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return RepositorioPedidosApi(api);
}

class _Conversas implements ServicoMensagens {
  const _Conversas();
  static ConversaResumo _c(String id, String titulo, {bool encerrada = false}) => ConversaResumo(
        pedidoId: id,
        tituloPedido: titulo,
        interlocutor: 'Pessoa $titulo',
        iniciais: 'PX',
        ultimaMensagem: 'Combinado',
        quando: 'ontem',
        contratado: true,
        encerrada: encerrada,
      );

  @override
  Future<List<ConversaResumo>> listar() async => [
        _c('p-concluido', 'Chuveiro'),
        _c('p-cancelado', 'Pintura'),
        _c('p-vivo', 'Faxina'),
        _c('p-sem-estado', 'Jardim', encerrada: true),
      ];
}

class _PedidosComEstado extends RepositorioPedidosFake {
  _PedidosComEstado({this.falha = false});
  final bool falha;

  static PedidoResumo _p(String id, String estado) => PedidoResumo(
        id: id,
        estadoApi: estado,
        titulo: id,
        subtitulo: id,
        statusTexto: estado,
        statusTipo: TipoStatus.info,
      );

  @override
  Future<PedidosDoCliente> listar() async {
    if (falha) throw Exception('sem rede');
    return PedidosDoCliente(
      emAndamento: [_p('p-vivo', 'em_andamento')],
      finalizados: [_p('p-concluido', 'concluido'), _p('p-cancelado', 'cancelado')],
    );
  }
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('1. Conclusão só para consulta (C15)', () {
    test('concluído (só pedir_retrabalho): sem confirmar, relatar, código nem prazo', () async {
      final chamadas = <String>[];
      final r = await _repo('concluido', ['pedir_retrabalho'], chamadas).conclusao('cca51234');
      expect(r.podeConfirmar, isFalse);
      expect(r.podeRelatarProblema, isFalse);
      expect(r.concluido, isTrue);
      expect(r.codigo, isEmpty);
      expect(r.prazoConfirmacao, isNull);
      expect(r.garantiaTexto, isNull);
      expect(r.orcamentoCentavos, 10000);
      expect(chamadas, isNot(contains('/v1/contratos/cca51234/garantia')));
    });

    test('em_confirmacao continua igual: confirma, relata, tem código e garantia', () async {
      final r = await _repo('em_confirmacao', ['abrir_disputa', 'confirmar_conclusao'])
          .conclusao('cca51234');
      expect(r.podeConfirmar, isTrue);
      expect(r.podeRelatarProblema, isTrue);
      expect(r.codigo, '7310');
      expect(r.garantiaTexto, contains('90'));
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

        testWidgets('tela do concluído mostra só fotos e valores ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final resumo = await t.runAsync(
              () => _repo('concluido', ['pedir_retrabalho']).conclusao('cca51234'));
          await t.pumpWidget(_app(ConclusaoTela(resumo: resumo!)));
          await t.pumpAndSettle();
          expect(find.text('Serviço finalizado'), findsOneWidget);
          expect(find.text('Total pago', skipOffstage: false), findsOneWidget);
          expect(find.text('Antes', skipOffstage: false), findsOneWidget);
          for (final proibido in [
            'terminou o serviço',
            'Confirm',
            'Código de conclusão',
            'horas',
            'liberad',
            'Relatar problema',
          ]) {
            expect(find.textContaining(proibido, skipOffstage: false), findsNothing,
                reason: proibido);
          }
          expect(find.byIcon(Icons.schedule), findsNothing);
          expect(t.takeException(), isNull);
        });

        testWidgets('tela que pede confirmação não muda ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(const ConclusaoTela(resumo: resumoConclusaoExemplo)));
          await t.pumpAndSettle();
          expect(find.text('Carlos terminou o serviço'), findsOneWidget);
          expect(find.text('Confirmar serviço'), findsOneWidget);
          expect(find.text('Relatar problema'), findsOneWidget);
          expect(find.text('Código de conclusão', skipOffstage: false), findsOneWidget);
          expect(find.byIcon(Icons.schedule, skipOffstage: false), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('consulta com abrir_disputa permitido mostra só "Relatar problema"', (t) async {
      await _janela(t, _tamanhos.first, 1);
      var tocou = false;
      final resumo = await t
          .runAsync(() => _repo('retrabalho', ['abrir_disputa']).conclusao('cca51234'));
      await t.pumpWidget(
          _app(ConclusaoTela(resumo: resumo!, aoRelatarProblema: () => tocou = true)));
      await t.pumpAndSettle();
      expect(find.text('Conclusão do serviço'), findsOneWidget);
      expect(find.textContaining('Confirm'), findsNothing);
      await t.tap(find.text('Relatar problema'));
      expect(tocou, isTrue);
    });
  });

  group('2. Conversas do cliente com o estado real (C16, P15)', () {
    Future<void> abrir(WidgetTester t, {bool falha = false}) async {
      RotasTrato.repos = repositoriosDemo(
        mensagens: const _Conversas(),
        pedidos: _PedidosComEstado(falha: falha),
      );
      await t.pumpWidget(_app(Scaffold(body: RotasTrato.abaMensagens())));
      await t.pumpAndSettle();
    }

    Future<void> filtrar(WidgetTester t, String chip) async {
      final alvo = find.byKey(ValueKey('chip-mensagens-$chip'));
      await t.ensureVisible(alvo);
      await t.pumpAndSettle();
      await t.tap(alvo);
      await t.pumpAndSettle();
    }

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

        testWidgets('selo, contagem e filtros usam o mesmo estado ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          await abrir(t);
          // Concluído, cancelado e o já encerrado pelo servidor; só um segue vivo.
          expect(find.text('Em andamento (1)'), findsOneWidget);
          expect(find.text('Finalizadas (3)'), findsOneWidget);

          await filtrar(t, 'finalizadas');
          expect(find.text('Pessoa Chuveiro'), findsOneWidget);
          expect(find.text('Concluído'), findsWidgets);
          expect(find.text('Pessoa Faxina'), findsNothing);
          expect(find.text('Em andamento'), findsNothing);

          await filtrar(t, 'emAndamento');
          expect(find.text('Pessoa Faxina'), findsOneWidget);
          expect(find.text('Em andamento'), findsOneWidget);
          expect(find.text('Pessoa Chuveiro'), findsNothing);
          expect(find.text('Pessoa Pintura'), findsNothing);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('falha ao ler os estados: a lista fica como veio', (t) async {
      await _janela(t, _tamanhos.first, 1);
      await abrir(t, falha: true);
      expect(find.text('Em andamento (3)'), findsOneWidget);
      expect(find.text('Finalizadas (1)'), findsOneWidget);
      expect(find.text('Pessoa Chuveiro'), findsOneWidget);
      expect(find.text('Cancelado'), findsNothing);
    });
  });

  group('3. "Caso em análise" só com caso aberto (C18)', () {
    for (final estado in ['agendado', 'em_andamento', 'em_confirmacao', 'retrabalho']) {
      test('$estado: sem caso aberto', () async {
        final d = await _repo(estado, ['abrir_disputa']).dadosRelato('cca51234');
        expect(d.casoEmAnalise, isFalse);
      });
    }

    test('em_disputa: caso aberto', () async {
      final d = await _repo('em_disputa', const []).dadosRelato('cca51234');
      expect(d.casoEmAnalise, isTrue);
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';
        for (final aberto in [false, true]) {
          testWidgets('aviso do relato, caso aberto = $aberto ($r)', (t) async {
            await _janela(t, tamanho, fonte);
            final dados = await t.runAsync(() =>
                _repo(aberto ? 'em_disputa' : 'agendado', const []).dadosRelato('cca51234'));
            await t.pumpWidget(_app(RelatarProblemaTela(dados: dados!)));
            await t.pumpAndSettle();
            expect(find.textContaining('Caso em análise'),
                aberto ? findsOneWidget : findsNothing);
            expect(find.textContaining('Relato ainda não enviado'),
                aberto ? findsNothing : findsOneWidget);
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });
}
