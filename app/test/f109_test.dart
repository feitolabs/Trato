// TERMOS-APP11: medidas da conta (cláusula 20) e conta bloqueada (403 `conta_bloqueada`).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/atendimento/atendimento_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/medidas/medidas_tela.dart';
import 'package:trato/telas/medidas/modelos.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/demo.dart';
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

Widget _app(Widget tela, [GlobalKey<NavigatorState>? chave]) =>
    MaterialApp(theme: TemaTrato.claro, navigatorKey: chave, home: tela);

Future<void> _ver(WidgetTester t, Finder alvo) =>
    t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

MedidaDeConta _medida({
  DateTime? ate,
  ContestacaoDeMedida? contestacao,
  DateTime? revertida,
}) =>
    MedidaDeConta(
      id: 'm1',
      tipo: 'suspensao',
      protocolo: 'MED-12',
      motivo: 'Relato de segurança em análise.',
      clausulas: const ['9.4', '20.3'],
      inicioEm: DateTime(2026, 11, 20, 10),
      efeito: 'Pedidos e valores em andamento seguem a cláusula 20.6.',
      comoContestar: 'Conteste em até 30 dias deste aviso.',
      vigente: revertida == null,
      revertidaEm: revertida,
      contestavelAte: ate ?? DateTime.now().add(const Duration(days: 20)),
      contestacao: contestacao,
    );

class _Medidas implements ServicoMedidas {
  _Medidas([List<MedidaDeConta>? itens]) : itens = itens ?? [_medida()];
  List<MedidaDeConta>? itens;
  final enviadas = <(String, String)>[];
  ErroTrato? erro;

  @override
  Future<List<MedidaDeConta>?> listar() async => itens;

  @override
  Future<MedidaDeConta> contestar(
    String id,
    String versao, {
    List<ProvaEscolhida> provas = const [],
  }) async {
    if (erro != null) throw erro!;
    enviadas.add((id, versao));
    final nova = _medida(
        contestacao: ContestacaoDeMedida(
            status: 'aberta',
            protocolo: 'CON-3',
            versao: versao,
            responderAte: DateTime(2026, 12, 10, 18)));
    itens = [nova];
    return nova;
  }
}

class _Sac implements ServicoSac {
  @override
  Future<PaginaDeChamados?> listar({int deslocamento = 0}) async =>
      const PaginaDeChamados(itens: [], total: 0);

  @override
  Object? noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

(ClienteApi, SessaoTrato, List<(String, Object?)>) _api(Map<String, (int, Object)> respostas) {
  final chamadas = <(String, Object?)>[];
  final sessao = SessaoTrato()..entrar('t');
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: sessao,
    cliente: MockClient((req) async {
      final chave = '${req.method} ${req.url.path}';
      chamadas.add((chave, req.body.isEmpty ? null : jsonDecode(req.body)));
      final (status, corpo) = respostas[chave] ?? (404, {'detail': 'Not Found'});
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return (api, sessao, chamadas);
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() {
    ligarDemoNosTestes();
    DeepLinks.reiniciarParaTeste();
  });
  tearDown(() {
    RotasTrato.esquecerBloqueio();
    RotasTrato.repos = repositoriosDemo();
  });

  group('API', () {
    test('403 conta_bloqueada avisa, não faz logout e não expira a sessão', () async {
      final (api, sessao, _) = _api({
        'GET /v1/me': (403, {'detail': 'Sua conta está bloqueada.', 'codigo': 'conta_bloqueada'}),
        'GET /v1/pedidos': (403, {'detail': 'Seu perfil não pode fazer isso.'}),
      });
      final avisos = <String?>[];
      var expirou = 0;
      var renovou = 0;
      sessao
        ..aoBloquear = avisos.add
        ..aoExpirar = (() => expirou++)
        ..renovar = () async {
          renovou++;
          return null;
        };
      await expectLater(api.get('/v1/me'),
          throwsA(predicate((e) => e is ErroTrato && e.codigo == 'conta_bloqueada')));
      expect(avisos, ['Sua conta está bloqueada.']);
      expect((sessao.logada, expirou, renovou), (true, 0, 0));
      await expectLater(api.get('/v1/pedidos'), throwsA(isA<ErroTrato>()));
      expect(avisos.length, 1, reason: '403 comum não é bloqueio');
      await expectLater(api.getBytes('/v1/me'), throwsA(isA<ErroTrato>()));
      expect(avisos.length, 2);
    });

    test('401 continua saindo da conta', () async {
      final (api, sessao, _) = _api({
        'GET /v1/me': (401, {'detail': 'Faça login.'}),
      });
      var bloqueou = 0;
      var expirou = 0;
      sessao
        ..aoBloquear = ((_) => bloqueou++)
        ..aoExpirar = () => expirou++;
      await expectLater(api.get('/v1/me'), throwsA(isA<ErroTrato>()));
      expect((bloqueou, expirou, sessao.logada), (0, 1, false));
    });

    test('medidas: lê, 404/503 somem, contesta com "versao" em texto e códigos', () async {
      final (api, _, chamadas) = _api({
        'GET /v1/me/medidas': (
          200,
          [
            {
              'id': 'm1',
              'tipo': 'trava_saque',
              'clausulas': ['17.4'],
              'inicio_em': '2026-11-20T12:00:00Z',
              'vigente': true,
              'contestavel_ate': '2026-12-20T12:00:00Z',
              'contestacao': {'status': 'em_analise', 'versao': 'v', 'protocolo': 'C1'},
            }
          ]
        ),
        'POST /v1/me/medidas/m1/contestacao': (200, {'id': 'm1', 'tipo': 'aviso'}),
        'POST /v1/me/medidas/m2/contestacao': (
          409,
          {'detail': 'x', 'codigo': 'prazo_encerrado'}
        ),
        'POST /v1/me/medidas/m3/contestacao': (409, {'detail': 'x', 'codigo': 'ja_contestada'}),
        'POST /v1/me/medidas/m4/contestacao': (404, {'detail': 'x', 'codigo': 'nao_encontrada'}),
        'POST /v1/me/medidas/m5/contestacao': (503, {'detail': 'x', 'codigo': 'indisponivel'}),
      });
      final servico = ServicoMedidasApi(api);
      final m = (await servico.listar())!.single;
      expect((m.tipoTexto, m.contestacao!.status), ('Trava de saques', 'em_analise'));
      await servico.contestar('m1', '  Minha versão ');
      expect(chamadas.last.$2, {'versao': 'Minha versão'});
      for (final (id, texto) in [
        ('m2', 'O prazo de 30 dias para contestar terminou.'),
        ('m3', 'Esta medida já foi contestada.'),
        ('m4', 'Medida não encontrada.'),
        ('m5', textoMedidasIndisponiveis),
        ('m9', textoMedidasIndisponiveis),
      ]) {
        await expectLater(servico.contestar(id, 'a'),
            throwsA(predicate((e) => e is ErroTrato && e.mensagem == texto)),
            reason: id);
      }
      final semRota = _api(const {}).$1;
      expect(await ServicoMedidasApi(semRota).listar(), isNull);
      final fora = _api({
        'GET /v1/me/medidas': (503, {'detail': 'x', 'codigo': 'indisponivel'}),
      }).$1;
      expect(await ServicoMedidasApi(fora).listar(), isNull);
    });

    test('avisos de medida usam a tela "medidas" (push e caixa)', () {
      expect(resultadoDoPush({'evento': 'conta.medida_aplicada', 'tela': 'medidas'}),
          const ResultadoLink.valido(DestinoApp.medidas, null));
      for (final tipo in ['conta.medida_aplicada', 'conta.medida_encerrada']) {
        final r = RotasTrato.destinoDaCaixa(
          Notificacao(
              id: 'n',
              titulo: 't',
              texto: 'x',
              quando: 'agora',
              tipo: TipoNotificacao.sistema,
              tipoApi: tipo),
          modoAtualProfissional: true,
        );
        expect(r?.destino, DestinoApp.medidas, reason: tipo);
      }
    });
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('lista a medida e envia a contestação ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final servico = _Medidas();
        await t.pumpWidget(_app(MedidasTela(servico: servico)));
        await t.pumpAndSettle();
        for (final texto in [
          'Suspensão da conta',
          'Relato de segurança em análise.',
          '9.4, 20.3',
          'Conteste em até 30 dias deste aviso.',
        ]) {
          await _ver(t, find.text(texto));
        }
        await _ver(t, find.byKey(const ValueKey('contestar-m1')));
        await _tocar(t, find.byKey(const ValueKey('contestar-m1')));
        final enviar = find.byKey(const Key('enviar-contestacao-medida'));
        await _ver(t, enviar);
        await _tocar(t, enviar);
        expect(servico.enviadas, isEmpty);
        await _ver(t, find.byKey(const Key('erro-contestacao-medida')));

        await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await t.pumpAndSettle();
        await _ver(t, find.byKey(const Key('versao-contestacao')));
        await t.enterText(find.byKey(const Key('versao-contestacao')), 'Não fui eu.');
        servico.erro = const ErroTrato(TipoErro.recusado, 'Esta medida já foi contestada.');
        await _ver(t, enviar);
        await _tocar(t, enviar);
        await _ver(t, find.text('Esta medida já foi contestada.'));
        servico.erro = null;
        await _ver(t, enviar);
        await _tocar(t, enviar);
        expect(servico.enviadas, [('m1', 'Não fui eu.')]);
        expect(find.byKey(const Key('contestacao-recebida'), skipOffstage: false),
            findsOneWidget);
        await _ver(t, find.text('Voltar'));
        await _tocar(t, find.text('Voltar'));
        await _ver(t, find.text('Contestação enviada'));
        expect(find.byKey(const ValueKey('contestar-m1')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('prazo vencido, revertida, vazia e indisponível ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        Future<void> abrir(List<MedidaDeConta>? itens) async {
          final servico = _Medidas()..itens = itens;
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(MedidasTela(servico: servico)));
          await t.pumpAndSettle();
        }

        await abrir([_medida(ate: DateTime(2026, 1, 5))]);
        await _ver(t, find.textContaining('O prazo para contestar terminou em 05/01/2026'));
        expect(find.byKey(const ValueKey('contestar-m1')), findsNothing);
        await abrir([_medida(revertida: DateTime(2026, 11, 22))]);
        await _ver(t, find.text('Revertida em'));
        expect(find.byKey(const ValueKey('contestar-m1')), findsNothing);
        await abrir(const []);
        expect(find.text('Nenhuma medida'), findsOneWidget);
        await abrir(null);
        expect(find.text('Medidas indisponíveis'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('bloqueio: tela única, atendimento, medidas e sair ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        RotasTrato.repos = repositoriosDemo(sac: _Sac(), medidas: _Medidas());
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(_app(const Scaffold(body: Text('INICIO')), nav));
        // Várias respostas juntas: uma tela só, e nada por baixo.
        for (var i = 0; i < 3; i++) {
          RotasTrato.contaFoiBloqueada(() => nav.currentState, 'Conta bloqueada pela equipe.');
        }
        await t.pumpAndSettle();
        expect(find.byType(ContaBloqueadaTela), findsOneWidget);
        expect(find.text('INICIO', skipOffstage: false), findsNothing);
        expect(find.text('Conta bloqueada pela equipe.'), findsOneWidget);
        expect(nav.currentState!.canPop(), isFalse);
        expect(ServicoAuthPadrao.atual.sessaoAtual, isNull);

        await _tocar(t, find.byKey(const Key('bloqueio-falar')));
        expect(find.byType(AtendimentoTela), findsOneWidget);
        // Outro 403 enquanto está no atendimento não derruba a tela.
        RotasTrato.contaFoiBloqueada(() => nav.currentState, 'x');
        await t.pumpAndSettle();
        expect(find.byType(AtendimentoTela), findsOneWidget);
        nav.currentState!.pop();
        await t.pumpAndSettle();

        await _tocar(t, find.byKey(const Key('bloqueio-medidas')));
        expect(find.byType(MedidasTela), findsOneWidget);
        nav.currentState!.pop();
        await t.pumpAndSettle();

        await _tocar(t, find.byKey(const Key('bloqueio-sair')));
        expect(find.byType(LoginTela), findsOneWidget);
        expect(RotasTrato.contaBloqueada, isFalse);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('bloqueio sem medidas no servidor: a entrada some', (t) async {
    RotasTrato.repos = repositoriosDemo(medidas: _Medidas()..itens = null);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(const Scaffold(), nav));
    RotasTrato.contaFoiBloqueada(() => nav.currentState, null);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('bloqueio-falar')), findsOneWidget);
    expect(find.byKey(const Key('bloqueio-medidas')), findsNothing);
  });

  testWidgets('403 já no GET /v1/me leva à tela de bloqueio sem renovar nem sair', (t) async {
    final (api, sessao, chamadas) = _api({
      'GET /v1/me': (403, {'detail': 'Sua conta está bloqueada.', 'codigo': 'conta_bloqueada'}),
    });
    final nav = GlobalKey<NavigatorState>();
    var renovou = 0;
    var expirou = 0;
    // A mesma ligação do main.
    sessao
      ..aoBloquear = ((m) => RotasTrato.contaFoiBloqueada(() => nav.currentState, m))
      ..aoExpirar = (() => expirou++)
      ..renovar = () async {
        renovou++;
        return null;
      };
    await t.pumpWidget(_app(const Scaffold(body: Text('INICIO')), nav));
    await t.runAsync(() async {
      try {
        await api.get('/v1/me');
      } on ErroTrato {
        // quem chamou recebe o erro; a tela de bloqueio já foi pedida
      }
    });
    await t.pumpAndSettle();
    expect(find.byType(ContaBloqueadaTela), findsOneWidget);
    expect(find.text('Sua conta está bloqueada.'), findsOneWidget);
    expect((renovou, expirou, sessao.logada), (0, 0, true));
    expect(chamadas.length, 1);
  });

  testWidgets('bloqueada, o app não volta para o início', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(const Scaffold(body: Text('INICIO')), nav));
    RotasTrato.contaFoiBloqueada(() => nav.currentState, null);
    await t.pumpAndSettle();
    RotasTrato.irParaCliente(nav.currentContext!);
    await t.pumpAndSettle();
    RotasTrato.irParaInicio(nav.currentState!.overlay!.context);
    await t.pumpAndSettle();
    expect(find.byType(CascaClienteTela), findsNothing);
    expect(find.byType(ContaBloqueadaTela), findsOneWidget);
  });

  testWidgets('bloqueada, o aviso de medida abre as medidas por cima', (t) async {
    await entrarNaContaDeTeste(ServicoAuthPadrao.atual);
    RotasTrato.repos = repositoriosDemo(medidas: _Medidas());
    final nav = GlobalKey<NavigatorState>();
    final anterior = DeepLinks.navegador;
    DeepLinks.navegador = () => nav.currentState;
    addTearDown(() => DeepLinks.navegador = anterior);
    await t.pumpWidget(_app(const Scaffold(), nav));
    RotasTrato.contaFoiBloqueada(() => nav.currentState, null);
    await t.pumpAndSettle();
    DeepLinks.receberPush({'tela': 'medidas', 'evento': 'conta.medida_aplicada'});
    await t.pumpAndSettle();
    expect(find.byType(MedidasTela), findsOneWidget);
  });

  testWidgets('Configurações: "Medidas da conta" aparece só quando o servidor tem', (t) async {
    await _janela(t, const Size(390, 2400), 1);
    for (final profissional in [false, true]) {
      for (final tem in [true, false]) {
        RotasTrato.repos = repositoriosDemo(medidas: _Medidas()..itens = tem ? [] : null);
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(_app(Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => RotasTrato.abrirConfiguracoes(c, profissional: profissional),
              child: const Text('abrir'),
            ),
          ),
        )));
        await t.tap(find.text('abrir'));
        await t.pumpAndSettle();
        expect(find.text('Medidas da conta'), tem ? findsOneWidget : findsNothing,
            reason: 'profissional=$profissional tem=$tem');
      }
    }
  });
}
