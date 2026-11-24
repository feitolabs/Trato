import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/cache_leitura.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/estado_conexao.dart';
import 'package:trato/dados/monitor_conexao.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/comuns/denuncia_folha.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/reagendamento.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/conclusao/dados_exemplo.dart';

const _tela = Size(320, 568);
const _teclado = 260.0;

Future<void> _abrir(WidgetTester tester, Widget tela, {Size tamanho = const Size(390, 1600)}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

http.Response _json(Object o) =>
    http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});

void main() {
  setUp(EstadoConexao.marcarOnline);
  tearDown(() {
    EstadoConexao.marcarOnline();
    RotasTrato.repos = repositoriosDemo();
  });

  group('Cache de leitura (por usuário, sem segredos, limpo no logout)', () {
    ({ClienteApi api, CacheMemoria disco, SessaoTrato sessao, void Function(bool) cair}) montar({
      String? usuario = 'u1',
    }) {
      var offline = false;
      final disco = CacheMemoria();
      final sessao = SessaoTrato()..entrar('t');
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: sessao,
        intervaloBaseRetry: Duration.zero,
        cache: CacheLeitura(disco, usuarioId: () => usuario),
        cliente: MockClient((req) async {
          if (offline) throw const SocketException('sem rede');
          return _json({'itens': [req.url.path], 'token': 'segredo', 'codigo_inicio': '1234'});
        }),
      );
      return (api: api, disco: disco, sessao: sessao, cair: (v) => offline = v);
    }

    test('sem internet mostra a última leitura guardada e marca "dados salvos"', () async {
      final m = montar();
      await m.api.get('/v1/pedidos');
      await Future<void>.delayed(Duration.zero);
      expect(EstadoConexao.online.value, isTrue);
      expect(EstadoConexao.dadosSalvos.value, isFalse);

      m.cair(true);
      final lida = await m.api.get('/v1/pedidos') as Map;
      expect(lida['itens'], ['/v1/pedidos']);
      expect(EstadoConexao.online.value, isFalse);
      expect(EstadoConexao.dadosSalvos.value, isTrue);

      // Voltou: leitura nova tira o aviso de dados salvos.
      m.cair(false);
      await m.api.get('/v1/pedidos');
      expect(EstadoConexao.online.value, isTrue);
      expect(EstadoConexao.dadosSalvos.value, isFalse);
    });

    test('não guarda segredos (token, código de início)', () async {
      final m = montar();
      await m.api.get('/v1/pedidos/p1');
      await Future<void>.delayed(Duration.zero);
      final guardado = m.disco.itens.values.single;
      expect(guardado, isNot(contains('segredo')));
      expect(guardado, isNot(contains('1234')));
      expect(guardado, contains('/v1/pedidos/p1'));
    });

    test('pagamento e anexos nunca são guardados: sem internet dá o erro de sempre', () async {
      final m = montar();
      await m.api.get('/v1/pedidos/p1/pagamento');
      await Future<void>.delayed(Duration.zero);
      expect(m.disco.itens, isEmpty);
      m.cair(true);
      await expectLater(m.api.get('/v1/pedidos/p1/pagamento'), throwsA(isA<ErroTrato>()));
    });

    test('cada usuário só vê o que é dele', () async {
      var usuario = 'u1';
      var offline = false;
      final disco = CacheMemoria();
      final sessao = SessaoTrato()..entrar('t');
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: sessao,
        intervaloBaseRetry: Duration.zero,
        cache: CacheLeitura(disco, usuarioId: () => usuario),
        cliente: MockClient((req) async {
          if (offline) throw const SocketException('sem rede');
          return _json({'dono': usuario});
        }),
      );
      await api.get('/v1/pedidos');
      await Future<void>.delayed(Duration.zero);
      usuario = 'u2';
      offline = true;
      await expectLater(api.get('/v1/pedidos'), throwsA(isA<ErroTrato>()));
    });

    test('sair da conta apaga o cache', () async {
      final m = montar();
      await m.api.get('/v1/pedidos');
      await Future<void>.delayed(Duration.zero);
      expect(m.disco.itens, isNotEmpty);
      m.sessao.sair();
      await Future<void>.delayed(Duration.zero);
      expect(m.disco.itens, isEmpty);
    });

    test('sem usuário logado não guarda nada', () async {
      final m = montar(usuario: null);
      await m.api.get('/v1/pedidos');
      await Future<void>.delayed(Duration.zero);
      expect(m.disco.itens, isEmpty);
    });

    test('SessaoTrato.usuarioId lê o sub do token e ignora token que não é JWT', () {
      String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      final s = SessaoTrato()..entrar('${b64({'alg': 'x'})}.${b64({'sub': 'abc-1'})}.assinatura');
      expect(s.usuarioId, 'abc-1');
      s.entrar('token-qualquer');
      expect(s.usuarioId, isNull);
    });
  });

  group('Reconexão automática', () {
    test('offline: testa a rede de tempos em tempos e, ao voltar, avisa e para de testar', () async {
      final sinal = ValueNotifier<bool>(true);
      var sondas = 0;
      var reconectou = 0;
      final monitor = MonitorConexao(
        sinal: sinal,
        intervalo: const Duration(milliseconds: 20),
        sonda: () async {
          sondas++;
          if (sondas >= 2) sinal.value = true; // o ClienteApi marca online ao receber resposta
        },
        aoReconectar: () => reconectou++,
      );
      addTearDown(monitor.parar);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sondas, 0); // online: não testa

      sinal.value = false;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(sondas, 2);
      expect(reconectou, 1);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sondas, 2); // parou
    });
  });

  group('Banner no topo, sem cobrir a AppBar', () {
    testWidgets('aparece ao cair, empurra o app, mostra dados salvos e some ao voltar',
        (tester) async {
      final online = ValueNotifier<bool>(true);
      final salvos = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: MoldeConexao(
            estado: online,
            dadosSalvos: salvos,
            child: Scaffold(
              appBar: AppBar(title: const Text('Seus pedidos')),
              body: const TextField(key: ValueKey('campo')),
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('campo')), 'meu texto');
      final topoAntes = tester.getTopLeft(find.text('Seus pedidos')).dy;
      expect(find.text('Sem conexão com a internet'), findsNothing);

      online.value = false;
      await tester.pump();
      expect(find.text('Sem conexão com a internet'), findsOneWidget);
      final banner = tester.getRect(find.byKey(const ValueKey('banner-sem-conexao')));
      final titulo = tester.getRect(find.text('Seus pedidos'));
      expect(banner.bottom, lessThanOrEqualTo(titulo.top), reason: 'banner cobriu a AppBar');
      expect(tester.getTopLeft(find.text('Seus pedidos')).dy, greaterThan(topoAntes));
      // Mudar o estado não recria as telas: o que a pessoa digitou continua.
      expect(find.text('meu texto'), findsOneWidget);

      expect(find.text('Mostrando dados salvos — sem internet'), findsNothing);
      salvos.value = true;
      await tester.pump();
      expect(find.text('Mostrando dados salvos — sem internet'), findsOneWidget);

      online.value = true;
      salvos.value = false;
      await tester.pump();
      expect(find.text('Sem conexão com a internet'), findsNothing);
      expect(tester.getTopLeft(find.text('Seus pedidos')).dy, topoAntes);
    });
  });

  group('Chat: mensagem sem internet espera e sai sozinha, sem duplicar', () {
    const conversa = ConversaPedido(
      nome: 'Carlos M.',
      iniciais: 'CM',
      numeroPedido: 'AB12',
      situacao: 'Agendado',
      mensagens: [],
      respostasRapidas: [],
    );

    testWidgets('fica "Aguardando conexão" e é reenviada com a mesma chave ao reconectar',
        (tester) async {
      final tentativas = <({String texto, String chave})>[];
      var semRede = true;
      await _abrir(
        tester,
        ChatPedidoTela(
          conversa: conversa,
          aoEnviarIdempotente: (texto, chave) async {
            tentativas.add((texto: texto, chave: chave));
            if (semRede) {
              EstadoConexao.marcarOffline();
              throw ErroTrato.semInternet;
            }
          },
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'Posso passar amanhã?');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();

      expect(find.text('Posso passar amanhã?'), findsOneWidget);
      expect(find.text('Aguardando conexão'), findsOneWidget);
      expect(tentativas, hasLength(1));
      // Campo limpo: não dá para mandar de novo sem querer.
      expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, isEmpty);

      semRede = false;
      EstadoConexao.marcarOnline();
      await tester.pumpAndSettle();

      expect(tentativas, hasLength(2));
      expect(tentativas[1].chave, tentativas[0].chave); // idempotência: mesma chave
      expect(tentativas[1].texto, 'Posso passar amanhã?');
      expect(find.text('Aguardando conexão'), findsNothing);
      expect(find.text('Posso passar amanhã?'), findsOneWidget); // uma bolha só

      // Já enviada: voltar a ficar online de novo não reenvia.
      EstadoConexao.marcarOffline();
      EstadoConexao.marcarOnline();
      await tester.pumpAndSettle();
      expect(tentativas, hasLength(2));
    });

    testWidgets('se a conexão volta mas cai de novo, continua esperando (sem perder nem duplicar)',
        (tester) async {
      final tentativas = <String>[];
      await _abrir(
        tester,
        ChatPedidoTela(
          conversa: conversa,
          aoEnviarIdempotente: (texto, chave) async {
            tentativas.add(chave);
            throw ErroTrato.semInternet;
          },
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'Oi');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();
      EstadoConexao.marcarOffline();
      EstadoConexao.marcarOnline();
      await tester.pumpAndSettle();
      expect(tentativas, hasLength(2));
      expect(find.text('Aguardando conexão'), findsOneWidget);
      expect(find.text('Oi'), findsOneWidget);
    });

    testWidgets('erro que não é de rede tira a mensagem (não fica esperando para sempre)',
        (tester) async {
      await _abrir(
        tester,
        ChatPedidoTela(
          conversa: conversa,
          aoEnviarIdempotente: (texto, chave) async => throw StateError('recusado'),
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'Oi');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();
      expect(find.text('Aguardando conexão'), findsNothing);
      expect(find.text('Oi'), findsOneWidget); // texto volta para o campo, não vira bolha
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('Ação que precisa do servidor: aviso humano, sem travar nem duplicar', () {
    testWidgets('pagar/cancelar/aceitar sem internet mostram o aviso e deixam tentar de novo',
        (tester) async {
      var chamadas = 0;
      bool? ultimo;
      await _abrir(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => ultimo = await RotasTrato.tentarParaTeste(context, () async {
                chamadas++;
                throw ErroTrato.semInternet;
              }),
              child: const Text('agir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('agir'));
      await tester.pump();
      expect(find.text('Sem internet. Conecte-se para concluir esta ação.'), findsOneWidget);
      expect(ultimo, isFalse);
      expect(chamadas, 1);

      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.text('agir'));
      await tester.pump();
      expect(chamadas, 2); // não travou: dá para tentar de novo, uma chamada por toque
    });
  });

  group('UX: confirmação e anti-duplo clique', () {
    testWidgets('cancelar a própria proposta de reagendamento pede confirmação', (tester) async {
      final chamadas = <String>[];
      await _abrir(
        tester,
        SecaoReagendamento(
          meuId: 'eu',
          carregar: () async => [
            Reagendamento(
              id: 'r1',
              propostoPor: 'eu',
              inicio: DateTime(2030, 3, 14, 14),
              fim: DateTime(2030, 3, 14, 16),
            ),
          ],
          propor: (i, f, m) async {},
          aceitar: (_) async {},
          recusar: (id) async => chamadas.add(id),
        ),
      );
      await tester.tap(find.text('Cancelar proposta'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar a proposta?'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(chamadas, isEmpty);

      await tester.tap(find.text('Cancelar proposta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmar-cancelar-proposta')));
      await tester.pumpAndSettle();
      expect(chamadas, ['r1']);
    });

    testWidgets('avaliar: toque repetido em "Enviar avaliação" envia uma vez só', (tester) async {
      var envios = 0;
      final pendente = Completer<void>();
      await _abrir(
        tester,
        AvaliacaoTela(
          dados: dadosAvaliacaoExemplo,
          aoEnviar: (e) {
            envios++;
            return pendente.future;
          },
        ),
      );
      await tester.tap(find.byKey(const Key('estrela_Limpeza_3')));
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      await tester.pump();
      await tester.tap(find.byType(BotaoPrimario).last, warnIfMissed: false);
      await tester.pump();
      expect(envios, 1);
      pendente.complete();
      await tester.pumpAndSettle();
    });
  });

  group('UX: teclado aberto em 320x568 não cobre o botão principal', () {
    Future<void> comTeclado(WidgetTester tester, Widget tela, {bool depois = false}) async {
      tester.view.physicalSize = _tela;
      tester.view.devicePixelRatio = 1;
      if (!depois) tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
      await tester.pumpAndSettle();
    }

    Future<void> acessivel(WidgetTester tester, Finder botao) async {
      final rolavel = find.byType(Scrollable);
      if (rolavel.evaluate().isNotEmpty) {
        await tester.drag(rolavel.first, const Offset(0, -6000));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: 'overflow com o teclado aberto');
      expect(botao, findsOneWidget);
      expect(tester.getRect(botao).bottom, lessThanOrEqualTo(_tela.height - _teclado + 0.5),
          reason: 'botão atrás do teclado');
      expect(botao.hitTestable(), findsOneWidget);
    }

    testWidgets('login', (tester) async {
      await comTeclado(tester, LoginTela(servico: ServicoAuthFake()));
      await acessivel(tester, find.widgetWithText(BotaoPrimario, 'Entrar'));
    });

    testWidgets('avaliação', (tester) async {
      await comTeclado(tester, const AvaliacaoTela(dados: dadosAvaliacaoExemplo));
      await acessivel(tester, find.widgetWithText(BotaoPrimario, 'Enviar avaliação'));
    });

    testWidgets('chat: campo e botão de enviar ficam acima do teclado', (tester) async {
      await comTeclado(
        tester,
        const ChatPedidoTela(
          conversa: ConversaPedido(
            nome: 'Carlos M.',
            iniciais: 'CM',
            numeroPedido: 'AB12',
            situacao: 'Agendado',
            mensagens: [],
            respostasRapidas: [],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final enviar = find.byIcon(Icons.arrow_forward);
      expect(tester.getRect(enviar).bottom, lessThanOrEqualTo(_tela.height - _teclado + 0.5));
      expect(enviar.hitTestable(), findsOneWidget);
    });

    testWidgets('denúncia (folha)', (tester) async {
      await comTeclado(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => mostrarFolhaDenuncia(context, enviar: (m, d) async {}),
              child: const Text('abrir'),
            ),
          ),
        ),
        depois: true,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
      await tester.pumpAndSettle();
      await acessivel(tester, find.widgetWithText(BotaoPrimario, 'Enviar denúncia'));
    });

    testWidgets('reagendamento (folha)', (tester) async {
      await comTeclado(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => mostrarFolhaReagendar(context),
              child: const Text('abrir'),
            ),
          ),
        ),
        depois: true,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
      await tester.pumpAndSettle();
      await acessivel(tester, find.widgetWithText(BotaoPrimario, 'Enviar proposta'));
    });
  });
}
