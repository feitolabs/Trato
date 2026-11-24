import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dados/servico_recorrencias_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/telas/recorrencias/modelos.dart';
import 'package:trato/telas/recorrencias/repetir_servico_folha.dart';
import 'package:trato/telas/recorrencias/servico_fake.dart';
import 'package:trato/telas/recorrencias/servicos_recorrentes_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';

// 2030-12-05 17:00 UTC = quinta, 05/12, 14:00 em Brasília.
final _visita1 = DateTime.utc(2030, 12, 5, 17);
final _visita2 = DateTime.utc(2030, 12, 12, 17);

Recorrencia _serie({
  String id = 'rec-1',
  String status = 'ativa',
  String papel = 'cliente',
  bool porMim = false,
  int? proposto,
  List<VisitaRecorrente>? visitas,
  int valor = 12000,
}) =>
    Recorrencia(
      id: id,
      status: status,
      frequencia: 'semanal',
      valorCentavos: valor,
      valorPropostoCentavos: proposto,
      proximaVisita: _visita1,
      meuPapel: papel,
      propostoPorMim: porMim,
      outraParteNome: 'Carlos M.',
      pedidoOrigemId: 'ped-origem',
      visitas: visitas ??
          [
            VisitaRecorrente(id: 'v1', dataPrevista: _visita1, status: 'agendada', pedidoId: 'ped-v1'),
            VisitaRecorrente(id: 'v2', dataPrevista: _visita2, status: 'confirmada_paga'),
          ],
    );

Future<void> _abrir(WidgetTester tester, Widget tela, {Size tamanho = const Size(390, 2400)}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

Future<void> _detalhe(
  WidgetTester tester,
  ServicoRecorrenciasFake s, {
  String id = 'rec-1',
  AbrirPedidoDaVisita? aoAbrirPedido,
}) =>
    _abrir(
      tester,
      DetalheRecorrenciaTela(
        key: UniqueKey(),
        servico: s,
        recorrenciaId: id,
        aoAbrirPedido: aoAbrirPedido,
      ),
    );

http.Response _json(Object o, [int status = 200]) =>
    http.Response(jsonEncode(o), status, headers: {'content-type': 'application/json'});

Map<String, Object?> _jsonSerie({String id = 'rec-1', String status = 'ativa'}) => {
      'id': id,
      'status': status,
      'frequencia': 'quinzenal',
      'valor_centavos': 15000,
      'valor_proposto_centavos': 17000,
      'proxima_visita_em': '2030-12-05T17:00:00Z',
      'meu_papel': 'profissional',
      'proposto_por_mim': true,
      'outra_parte_nome': 'Ana S.',
      'pedido_origem_id': 'ped-1',
      'categoria_id': 'cat-1',
      'criado_em': '2030-11-01T10:00:00Z',
      'visitas': [
        {'id': 'v1', 'data_prevista_em': '2030-12-05T17:00:00Z', 'status': 'agendada', 'pedido_id': 'ped-v1'},
        {'sem': 'id'},
      ],
    };

void main() {
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('Contrato /v1/recorrencias', () {
    late List<http.Request> pedidas;

    ServicoRecorrenciasApi servico(http.Response Function(http.Request) responder) {
      pedidas = [];
      return ServicoRecorrenciasApi(
        ClienteApi(
          urlBase: 'https://api.teste/',
          sessao: SessaoTrato()..entrar('t'),
          intervaloBaseRetry: Duration.zero,
          cliente: MockClient((req) async {
            pedidas.add(req);
            return responder(req);
          }),
        ),
      );
    }

    test('POST propõe com frequência, 1ª visita em UTC e valor em centavos (omitido se nulo)',
        () async {
      final s = servico((_) => _json(_jsonSerie(status: 'proposta'), 201));
      final criada = await s.propor('ped-1', (
        frequencia: FrequenciaRecorrencia.quinzenal,
        proximaVisita: _visita1,
        valorCentavos: 15000,
      ));
      await s.propor('ped-1', (
        frequencia: FrequenciaRecorrencia.mensal,
        proximaVisita: _visita1,
        valorCentavos: null,
      ));
      expect(pedidas[0].method, 'POST');
      expect(pedidas[0].url.path, '/v1/recorrencias');
      expect(jsonDecode(pedidas[0].body), {
        'pedido_origem_id': 'ped-1',
        'frequencia': 'quinzenal',
        'proxima_visita_em': '2030-12-05T17:00:00.000Z',
        'valor_centavos': 15000,
      });
      expect((jsonDecode(pedidas[1].body) as Map).containsKey('valor_centavos'), isFalse);
      expect((jsonDecode(pedidas[1].body) as Map)['frequencia'], 'mensal');
      expect(criada.status, 'proposta');
    });

    test('GET lista e GET detalhe leem série, reajuste pendente e visitas', () async {
      final s = servico((req) => req.url.path == '/v1/recorrencias'
          ? _json([_jsonSerie(), {'sem': 'id'}])
          : _json(_jsonSerie()));
      final lista = await s.listar();
      expect(lista, hasLength(1)); // item sem id é ignorado
      expect(lista.single.valorPropostoCentavos, 17000);
      expect(lista.single.meuPapel, 'profissional');
      expect(lista.single.propostoPorMim, isTrue);

      final d = await s.detalhe('rec-1');
      expect(pedidas.last.url.path, '/v1/recorrencias/rec-1');
      expect(d.visitas.map((v) => v.id), ['v1']);
      expect(d.visitas.single.pedidoId, 'ped-v1');
      expect(d.proximaVisita, _visita1);
    });

    test('cada ação é um POST no caminho certo e devolve a série', () async {
      final s = servico((_) => _json(_jsonSerie()));
      await s.aceitar('r1');
      await s.recusar('r1');
      await s.pausar('r1');
      await s.retomar('r1');
      await s.cancelar('r1');
      await s.pularProxima('r1');
      await s.pularVisita('r1', 'v9');
      await s.proporReajuste('r1', 18000);
      await s.aceitarReajuste('r1', 17000);
      await s.recusarReajuste('r1');
      expect(pedidas.every((p) => p.method == 'POST'), isTrue);
      expect(pedidas.map((p) => p.url.path), [
        '/v1/recorrencias/r1/aceitar',
        '/v1/recorrencias/r1/recusar',
        '/v1/recorrencias/r1/pausar',
        '/v1/recorrencias/r1/retomar',
        '/v1/recorrencias/r1/cancelar',
        '/v1/recorrencias/r1/pular-proxima',
        '/v1/recorrencias/r1/visitas/v9/pular',
        '/v1/recorrencias/r1/reajuste',
        '/v1/recorrencias/r1/reajuste/aceitar',
        '/v1/recorrencias/r1/reajuste/recusar',
      ]);
      expect(jsonDecode(pedidas[7].body), {'valor_centavos': 18000});
      // O aceite manda o valor que o cliente viu (o backend confere).
      expect(jsonDecode(pedidas[8].body), {'valor_centavos': 17000});
    });

    test('erros 403, 409 e 422 chegam com o texto do backend', () async {
      for (final (status, texto) in [
        (403, 'Apenas a outra parte pode aceitar o serviço recorrente.'),
        (409, 'Este serviço recorrente já foi respondido.'),
        (422, 'A data da primeira visita precisa ser no futuro.'),
      ]) {
        final s = servico((_) => _json({'detail': texto}, status));
        await expectLater(
          s.aceitar('r1'),
          throwsA(isA<ErroTrato>().having((e) => e.mensagem, 'mensagem', texto)),
        );
      }
    });

    test('resposta sem o essencial vira erro (não uma série vazia)', () async {
      final s = servico((_) => _json({'id': 'x'}));
      await expectLater(s.aceitar('x'), throwsA(isA<ErroTrato>()));
    });
  });

  group('Datas em Brasília e status legível', () {
    test('mostra no horário de Brasília (UTC-3), mesmo virando o dia', () {
      expect(dataHoraBrasilia(_visita1), 'qui, 05/12 · 14:00');
      expect(dataHoraBrasilia(DateTime.utc(2030, 12, 6, 2)), 'qui, 05/12 · 23:00');
      expect(dataBrasilia(DateTime.utc(2030, 12, 6, 2)), '05/12/2030');
      expect(deBrasilia(2030, 12, 5, 14, 0), _visita1);
    });

    test('status da série e da visita em português simples', () {
      expect(_serie(status: 'proposta', porMim: true).textoStatus, 'Aguardando resposta');
      expect(_serie(status: 'proposta').textoStatus, 'Proposta recebida');
      expect(_serie().textoStatus, 'Ativo');
      expect(_serie(status: 'pausada').textoStatus, 'Pausado');
      expect(_serie(status: 'cancelada').textoStatus, 'Cancelado');
      for (final (c, t) in [
        ('agendada', 'Agendada'),
        ('confirmada_paga', 'Confirmada e paga'),
        ('pulada', 'Pulada'),
        ('expirada', 'Expirada'),
        ('cancelada', 'Cancelada'),
      ]) {
        expect(VisitaRecorrente(id: 'v', dataPrevista: _visita1, status: c).textoStatus, t);
      }
    });
  });

  group('Folha "Repetir este serviço"', () {
    Future<PropostaRecorrencia?> abrirFolha(
      WidgetTester tester, {
      int? valor = 12000,
      DateTime? agora,
      List<PropostaRecorrencia?>? resultado,
    }) async {
      PropostaRecorrencia? saida;
      var fechou = false;
      await _abrir(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saida = await mostrarFolhaRepetirServico(
                  context,
                  valorInicialCentavos: valor,
                  agora: () => agora ?? DateTime.utc(2030, 1, 1),
                  escolherDia: (_) async => DateTime(2030, 12, 5),
                  escolherHora: (_, __) async => const TimeOfDay(hour: 14, minute: 0),
                );
                fechou = true;
                resultado?.add(saida);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(fechou, isFalse);
      return saida;
    }

    Future<void> preencher(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('repetir-dia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repetir-hora')));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra frequência, 1ª visita e o valor já preenchido', (tester) async {
      await abrirFolha(tester);
      expect(find.text('Repetir este serviço'), findsOneWidget);
      for (final f in ['Toda semana', 'A cada 15 dias', 'Todo mês']) {
        expect(find.text(f), findsOneWidget);
      }
      expect(tester.widget<TextField>(find.byKey(const ValueKey('repetir-valor'))).controller!.text,
          '120,00');
    });

    testWidgets('envia frequência, 1ª visita em horário de Brasília (UTC) e valor em centavos',
        (tester) async {
      final r = <PropostaRecorrencia?>[];
      await abrirFolha(tester, resultado: r);
      await tester.tap(find.byKey(const ValueKey('frequencia-quinzenal')));
      await preencher(tester);
      await tester.enterText(find.byKey(const ValueKey('repetir-valor')), '135,50');
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(r.single!.frequencia, FrequenciaRecorrencia.quinzenal);
      expect(r.single!.proximaVisita, _visita1); // 14:00 BRT = 17:00 UTC
      expect(r.single!.valorCentavos, 13550);
    });

    testWidgets('sem escolher dia e hora, ou com data passada ou valor ruim, não envia',
        (tester) async {
      final r = <PropostaRecorrencia?>[];
      await abrirFolha(tester, resultado: r, agora: DateTime.utc(2031, 1, 1));
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha o dia e a hora da primeira visita.'), findsOneWidget);

      await preencher(tester);
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha uma data no futuro.'), findsOneWidget);
      expect(r, isEmpty);
    });

    testWidgets('valor inválido ou apagado (quando já vinha preenchido) pede o valor', (tester) async {
      final r = <PropostaRecorrencia?>[];
      await abrirFolha(tester, resultado: r);
      await preencher(tester);
      await tester.enterText(find.byKey(const ValueKey('repetir-valor')), '0');
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(find.text('Informe um valor válido por visita.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('repetir-valor')), '');
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o valor de cada visita.'), findsOneWidget);
      expect(r, isEmpty);
    });

    testWidgets('sem valor conhecido o campo fica vazio e o valor sai omitido', (tester) async {
      final r = <PropostaRecorrencia?>[];
      await abrirFolha(tester, valor: null, resultado: r);
      await preencher(tester);
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(r.single!.valorCentavos, isNull);
    });

    testWidgets('teclado aberto em 320x568: botão principal continua acessível', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => mostrarFolhaRepetirServico(context, valorInicialCentavos: 12000),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final botao = find.widgetWithText(BotaoPrimario, 'Enviar proposta');
      expect(tester.getRect(botao).bottom, lessThanOrEqualTo(568 - 260 + 0.5));
      expect(botao.hitTestable(), findsOneWidget);
    });
  });

  group('Lista "Serviços recorrentes"', () {
    testWidgets('mostra status legível, frequência, valor e próxima visita em Brasília',
        (tester) async {
      final s = ServicoRecorrenciasFake(series: [
        _serie(id: 'a', status: 'proposta', porMim: true),
        _serie(id: 'b', status: 'proposta'),
        _serie(id: 'c'),
        _serie(id: 'd', status: 'pausada'),
        _serie(id: 'e', status: 'cancelada'),
      ]);
      await _abrir(tester, ServicosRecorrentesTela(servico: s));
      expect(find.text('Serviços recorrentes'), findsWidgets);
      for (final t in ['Aguardando resposta', 'Proposta recebida', 'Ativo', 'Pausado', 'Cancelado']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('Toda semana · R\$ 120,00 por visita'), findsNWidgets(5));
      expect(find.text('Próxima visita: qui, 05/12 · 14:00'), findsNWidgets(4)); // cancelada não mostra
    });

    testWidgets('lista vazia explica como começar', (tester) async {
      await _abrir(tester, ServicosRecorrentesTela(servico: ServicoRecorrenciasFake()));
      expect(find.text('Nenhum serviço recorrente ainda'), findsOneWidget);
      expect(find.textContaining('Repetir este serviço'), findsOneWidget);
    });

    testWidgets('erro ao carregar: mensagem com "Tentar de novo"', (tester) async {
      await _abrir(
        tester,
        ServicosRecorrentesTela(servico: ServicoRecorrenciasFake(falharAoCarregar: true)),
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('tocar numa série abre o detalhe; ao voltar a lista recarrega o status',
        (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(status: 'proposta')]);
      await _abrir(tester, ServicosRecorrentesTela(servico: s));
      await tester.tap(find.byKey(const ValueKey('serie-rec-1')));
      await tester.pumpAndSettle();
      expect(find.byType(DetalheRecorrenciaTela), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aceitar-serie')));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Ativo'), findsOneWidget);
    });
  });

  group('Detalhe: proposta', () {
    testWidgets('proposta recebida: Aceitar ativa a série e mostra o novo status', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(status: 'proposta')]);
      await _detalhe(tester, s);
      expect(find.byKey(const ValueKey('cartao-proposta')), findsOneWidget);
      expect(find.textContaining('Carlos M. propôs repetir este serviço'), findsOneWidget);
      expect(find.text('Aguardando resposta de Carlos M.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('aceitar-serie')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['aceitar:rec-1']);
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-detalhe'))).data, 'Ativo');
      expect(find.byKey(const ValueKey('cartao-proposta')), findsNothing);
    });

    testWidgets('proposta recebida: Recusar chama /recusar e cancela a série', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(status: 'proposta')]);
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('recusar-serie')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['recusar:rec-1']);
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-detalhe'))).data, 'Cancelado');
    });

    testWidgets('anti-duplo clique: toque repetido em Aceitar chama o servidor uma vez',
        (tester) async {
      final s = _Lento(series: [_serie(status: 'proposta')]);
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('aceitar-serie')));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('recusar-serie')), warnIfMissed: false);
      await tester.pump();
      expect(s.chamadas, ['aceitar:rec-1']);
      s.pendente.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('quem propôs vê "Aguardando resposta" e cancela com confirmação', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(status: 'proposta', porMim: true)]);
      await _detalhe(tester, s);
      expect(find.text('Aguardando resposta de Carlos M.'), findsOneWidget);
      expect(find.byKey(const ValueKey('aceitar-serie')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('cancelar-proposta-serie')));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar a proposta?'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(s.chamadas, isEmpty);

      await tester.tap(find.byKey(const ValueKey('cancelar-proposta-serie')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmar-cancelar-serie')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['cancelar:rec-1']);
    });

    testWidgets('erro do backend (409) aparece como veio e dá para tentar de novo', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(status: 'proposta')])
        ..erroNaProxima = const ErroTrato(
          TipoErro.recusado,
          'Este serviço recorrente já foi respondido.',
          codigoHttp: 409,
        );
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('aceitar-serie')));
      await tester.pumpAndSettle();
      expect(find.text('Este serviço recorrente já foi respondido.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aceitar-serie')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('erro-recorrencia')), findsNothing);
      expect(s.chamadas, ['aceitar:rec-1', 'aceitar:rec-1']);
    });

    testWidgets('sem internet: aviso humano e a tela não trava', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(status: 'proposta')])
        ..erroNaProxima = ErroTrato.semInternet;
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('aceitar-serie')));
      await tester.pumpAndSettle();
      expect(find.text('Sem internet. Conecte-se para concluir esta ação.'), findsOneWidget);
      expect(find.byKey(const ValueKey('aceitar-serie')), findsOneWidget);
    });
  });

  group('Detalhe: série ativa, pausada e visitas', () {
    testWidgets('mostra resumo e visitas em Brasília; ativa oferece pausar, pular e cancelar',
        (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie()]);
      await _detalhe(tester, s);
      expect(find.text('Carlos M.'), findsOneWidget);
      expect(find.text('Toda semana · R\$ 120,00 por visita'), findsOneWidget);
      expect(find.textContaining('qui, 05/12 · 14:00'), findsWidgets);
      expect(find.text('Agendada'), findsOneWidget);
      expect(find.text('Confirmada e paga'), findsOneWidget);
      expect(find.byKey(const ValueKey('pausar-serie')), findsOneWidget);
      expect(find.byKey(const ValueKey('pular-proxima')), findsOneWidget);
      expect(find.byKey(const ValueKey('cancelar-serie')), findsOneWidget);
      expect(find.byKey(const ValueKey('retomar-serie')), findsNothing);
      expect(find.byKey(const ValueKey('propor-reajuste')), findsNothing); // só o profissional
    });

    testWidgets('pausar e retomar (sem confirmação, não destrutivo)', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie()]);
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('pausar-serie')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-detalhe'))).data, 'Pausado');
      expect(find.byKey(const ValueKey('pular-proxima')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('retomar-serie')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-detalhe'))).data, 'Ativo');
      expect(s.chamadas, ['pausar:rec-1', 'retomar:rec-1']);
    });

    testWidgets('cancelar a série pede confirmação: Voltar não chama, confirmar cancela',
        (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie()]);
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('cancelar-serie')));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar o serviço recorrente?'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(s.chamadas, isEmpty);

      await tester.tap(find.byKey(const ValueKey('cancelar-serie')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmar-cancelar-serie')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['cancelar:rec-1']);
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-detalhe'))).data, 'Cancelado');
      // Cancelada: sem ações.
      expect(find.byKey(const ValueKey('pausar-serie')), findsNothing);
      expect(find.byKey(const ValueKey('cancelar-serie')), findsNothing);
      expect(find.byKey(const ValueKey('pular-v1')), findsNothing);
      expect(find.textContaining('Próxima visita'), findsNothing);
    });

    testWidgets('pular a próxima visita e pular uma visita pedem confirmação', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie()]);
      await _detalhe(tester, s);

      await tester.tap(find.byKey(const ValueKey('pular-proxima')));
      await tester.pumpAndSettle();
      expect(find.text('Pular a próxima visita?'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(s.chamadas, isEmpty);
      await tester.tap(find.byKey(const ValueKey('pular-proxima')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmar-pular-visita')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pular-v1')));
      await tester.pumpAndSettle();
      expect(find.text('Pular esta visita?'), findsOneWidget);
      expect(find.textContaining('qui, 05/12 · 14:00'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('confirmar-pular-visita')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['pular-proxima:rec-1', 'pular-visita:rec-1:v1']);
      expect(find.text('Pulada'), findsOneWidget);
      expect(find.byKey(const ValueKey('pular-v1')), findsNothing); // já pulada
    });

    testWidgets('visita com pedido abre pelo pedido_id, no lado certo (cliente/profissional)',
        (tester) async {
      final abertos = <(String, bool)>[];
      await _detalhe(
        tester,
        ServicoRecorrenciasFake(series: [_serie()]),
        aoAbrirPedido: (id, cliente) => abertos.add((id, cliente)),
      );
      await tester.tap(find.byKey(const ValueKey('abrir-pedido-v1')));
      expect(abertos, [('ped-v1', true)]);
      expect(find.byKey(const ValueKey('abrir-pedido-v2')), findsNothing); // sem pedido

      await _detalhe(
        tester,
        ServicoRecorrenciasFake(series: [_serie(papel: 'profissional')]),
        aoAbrirPedido: (id, cliente) => abertos.add((id, cliente)),
      );
      await tester.tap(find.byKey(const ValueKey('abrir-pedido-v1')));
      expect(abertos.last, ('ped-v1', false));
    });

    testWidgets('carregando mostra o estado de espera; falha sem dados mostra erro com retry',
        (tester) async {
      await _abrir(
        tester,
        DetalheRecorrenciaTela(
          servico: ServicoRecorrenciasFake(falharAoCarregar: true),
          recorrenciaId: 'rec-1',
        ),
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  });

  group('Reajuste de valor', () {
    testWidgets('cliente vê o card com valor novo e atual e aceita', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(proposto: 15000)]);
      await _detalhe(tester, s);
      expect(find.byKey(const ValueKey('cartao-reajuste')), findsOneWidget);
      expect(find.textContaining('R\$ 150,00 por visita (hoje R\$ 120,00)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aceitar-reajuste')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['reajuste-aceitar:rec-1:15000']); // manda o valor mostrado
      expect(find.byKey(const ValueKey('cartao-reajuste')), findsNothing);
      expect(find.text('Toda semana · R\$ 150,00 por visita'), findsOneWidget);
    });

    testWidgets('valor do reajuste mudou (409): recarrega e mostra o valor novo; aceitar de novo manda o novo',
        (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(proposto: 15000)]);
      await _detalhe(tester, s);
      expect(find.textContaining('R\$ 150,00 por visita (hoje R\$ 120,00)'), findsOneWidget);

      // O profissional mudou o valor proposto depois de o cliente abrir a tela.
      s.series[0] = _serie(proposto: 17000);
      await tester.tap(find.byKey(const ValueKey('aceitar-reajuste')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['reajuste-aceitar:rec-1:15000']);
      expect(find.text('O valor do reajuste mudou. Confira o novo valor.'), findsOneWidget);
      expect(find.textContaining('R\$ 170,00 por visita (hoje R\$ 120,00)'), findsOneWidget);
      expect(find.textContaining('R\$ 150,00 por visita'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('aceitar-reajuste')));
      await tester.pumpAndSettle();
      expect(s.chamadas.last, 'reajuste-aceitar:rec-1:17000');
      expect(find.text('Toda semana · R\$ 170,00 por visita'), findsOneWidget);
      expect(find.byKey(const ValueKey('erro-recorrencia')), findsNothing);
    });

    testWidgets('cliente recusa o reajuste e a série segue no valor atual', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(proposto: 15000)]);
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('recusar-reajuste')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['reajuste-recusar:rec-1']);
      expect(find.text('Toda semana · R\$ 120,00 por visita'), findsOneWidget);
    });

    testWidgets('profissional vê "aguardando o cliente" e não decide', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(papel: 'profissional', proposto: 15000)]);
      await _detalhe(tester, s);
      expect(find.text('Novo valor aguardando o cliente'), findsOneWidget);
      expect(find.byKey(const ValueKey('aceitar-reajuste')), findsNothing);
      expect(find.byKey(const ValueKey('propor-reajuste')), findsNothing); // já há um pendente
    });

    testWidgets('profissional propõe novo valor (centavos) e valida o campo', (tester) async {
      final s = ServicoRecorrenciasFake(series: [_serie(papel: 'profissional')]);
      await _detalhe(tester, s);
      await tester.tap(find.byKey(const ValueKey('propor-reajuste')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('enviar-novo-valor')));
      await tester.pumpAndSettle();
      expect(find.text('Informe um valor válido por visita.'), findsOneWidget);
      expect(s.chamadas, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('novo-valor')), '135,50');
      await tester.tap(find.byKey(const ValueKey('enviar-novo-valor')));
      await tester.pumpAndSettle();
      expect(s.chamadas, ['reajuste:rec-1:13550']);
      expect(find.text('Novo valor aguardando o cliente'), findsOneWidget);
    });
  });

  group('Pontos de entrada', () {
    PedidoEmExecucao pedido(String estado) => PedidoEmExecucao(
          numero: '#4821',
          titulo: 'Limpeza',
          etapas: const [],
          fotos: const [],
          estadoApi: estado,
        );

    testWidgets('pedido concluído mostra "Repetir este serviço"; nos outros estados não',
        (tester) async {
      var toques = 0;
      await _abrir(
        tester,
        PedidoExecucaoTela(pedido: pedido('concluido'), aoRepetirServico: () => toques++),
      );
      await tester.tap(find.text('Repetir este serviço'));
      expect(toques, 1);
      for (final estado in ['agendado', 'em_andamento', 'em_confirmacao', 'cancelado']) {
        await _abrir(
          tester,
          PedidoExecucaoTela(pedido: pedido(estado), aoRepetirServico: () {}),
        );
        expect(find.text('Repetir este serviço'), findsNothing, reason: estado);
      }
      await _abrir(tester, PedidoExecucaoTela(pedido: pedido('concluido')));
      expect(find.text('Repetir este serviço'), findsNothing); // sem callback
    });

    testWidgets('perfil do profissional: card "Serviços recorrentes" só com o callback',
        (tester) async {
      var abriu = 0;
      await _abrir(
        tester,
        PerfilPublicoTela(servico: ServicoPerfilPublicoFake(), aoAbrirRecorrencias: () => abriu++),
      );
      await tester.ensureVisible(find.byKey(const Key('abrir-servicos-recorrentes')));
      await tester.tap(find.byKey(const Key('abrir-servicos-recorrentes')));
      expect(abriu, 1);
      await _abrir(tester, PerfilPublicoTela(servico: ServicoPerfilPublicoFake()));
      expect(find.byKey(const Key('abrir-servicos-recorrentes')), findsNothing);
    });

    test('perfil do cliente: o item "Serviços recorrentes" fica no Perfil', () {
      const perfil = PerfilCliente(
        nome: 'Ana',
        iniciais: 'A',
        resumo: '',
        grupos: [
          GrupoPerfil(
            titulo: 'CONTA',
            itens: [
              ItemPerfil(acao: AcaoPerfil.servicosRecorrentes, titulo: 'Serviços recorrentes'),
              ItemPerfil(acao: AcaoPerfil.notificacoes, titulo: 'Notificações'),
            ],
          ),
        ],
      );
      expect(
        RotasTrato.soNoPerfilParaTeste(perfil).grupos.single.itens.map((i) => i.acao),
        [AcaoPerfil.servicosRecorrentes],
      );
    });

    testWidgets('rota: abrirRecorrencias abre a lista (demonstração vazia)', (tester) async {
      await _abrir(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RotasTrato.abrirRecorrencias(context),
            child: const Text('abrir'),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(ServicosRecorrentesTela), findsOneWidget);
      expect(find.text('Nenhum serviço recorrente ainda'), findsOneWidget);
    });

    testWidgets('rota de ponta a ponta: pedido concluído → Repetir → folha → proposta → detalhe',
        (tester) async {
      final recorrencias = ServicoRecorrenciasFake();
      final base = repositoriosDemo();
      RotasTrato.repos = RepositoriosTrato(
        pedidos: _PedidoConcluido(
          const PedidoEmExecucao(
            numero: '#4821',
            titulo: 'Limpeza',
            etapas: [],
            fotos: [],
            estadoApi: 'concluido',
            orcamentoCentavos: 18000,
          ),
        ),
        orcamentos: base.orcamentos,
        pagamento: base.pagamento,
        chat: base.chat,
        notificacoes: base.notificacoes,
        perfil: base.perfil,
        profissional: base.profissional,
        catalogo: base.catalogo,
        servicos: base.servicos,
        agenda: base.agenda,
        recorrencias: recorrencias,
      );
      await _abrir(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RotasTrato.abrirServico(context, 'ped-77'),
            child: const Text('abrir'),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('repetir-servico')));
      await tester.tap(find.byKey(const ValueKey('repetir-servico')));
      await tester.pumpAndSettle();
      // Valor do serviço já preenchido na folha.
      expect(tester.widget<TextField>(find.byKey(const ValueKey('repetir-valor'))).controller!.text,
          '180,00');
      await tester.tap(find.byKey(const ValueKey('frequencia-mensal')));
      await tester.tap(find.byKey(const ValueKey('repetir-dia')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repetir-hora')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();

      expect(recorrencias.chamadas, ['propor']);
      expect(recorrencias.series.single.pedidoOrigemId, 'ped-77');
      expect(recorrencias.series.single.frequencia, 'mensal');
      expect(recorrencias.series.single.valorCentavos, 18000);
      expect(find.byType(DetalheRecorrenciaTela), findsOneWidget);
      expect(find.text('Aguardando resposta de Carlos M.'), findsOneWidget);
    });
  });
}

class _Lento extends ServicoRecorrenciasFake {
  _Lento({super.series});

  final pendente = Completer<void>();

  @override
  Future<Recorrencia> aceitar(String id) async {
    chamadas.add('aceitar:$id');
    await pendente.future;
    return super.series.firstWhere((s) => s.id == id);
  }
}

class _PedidoConcluido extends RepositorioPedidosFake {
  _PedidoConcluido(this._pedido);

  final PedidoEmExecucao _pedido;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => _pedido;
}
