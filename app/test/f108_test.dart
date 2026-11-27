// TERMOS-APP10: "Falar com o Trato" (Termos 25.1 a 25.5).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/servico_ajuda_local.dart';
import 'package:trato/telas/atendimento/atendimento_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/tema/tema.dart';

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

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

Future<void> _ver(WidgetTester t, Finder alvo) =>
    t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await _ver(t, alvo);
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

Chamado _chamado({String status = 'aberto', List<MensagemChamado>? mensagens, bool prazo = false}) =>
    Chamado(
      id: 'c1',
      protocolo: 'TR-2026-0007',
      assunto: 'Cobrança em dobro',
      categoria: 'reclamacao',
      status: status,
      responderAte: DateTime(2026, 12, 3, 18),
      novoPrazoAte: prazo ? DateTime(2026, 12, 10, 18) : null,
      motivoExtensao: prazo ? 'Falta o extrato do parceiro.' : null,
      mensagens:
          mensagens ?? const [MensagemChamado(autor: 'usuario', texto: 'Fui cobrado duas vezes.')],
    );

class _Sac implements ServicoSac {
  _Sac({this.indisponivel = false, this.itens = const []});
  final bool indisponivel;
  List<Chamado> itens;
  final abertos = <(String, String, String, String?)>[];
  final respostas = <String>[];
  var falhar = false;

  @override
  Future<PaginaDeChamados?> listar({int deslocamento = 0}) async => indisponivel
      ? null
      : PaginaDeChamados(itens: itens.skip(deslocamento).take(1).toList(), total: itens.length);

  @override
  Future<Chamado> abrir({
    required String categoria,
    required String assunto,
    required String texto,
    String? pedidoId,
  }) async {
    if (falhar) throw const ErroTrato(TipoErro.semInternet, 'Sem internet.');
    abertos.add((categoria, assunto, texto, pedidoId));
    itens = [_chamado()];
    return _chamado();
  }

  @override
  Future<Chamado> ver(String id) async => _chamado(status: 'respondido', prazo: true);

  @override
  Future<Chamado> responder(String id, String texto) async {
    if (falhar) {
      throw const ErroTrato(TipoErro.recusado, 'Este chamado foi encerrado. Abra um novo.');
    }
    respostas.add(texto);
    return _chamado(mensagens: [MensagemChamado(autor: 'usuario', texto: texto)]);
  }
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  test('API: lista, 404/503, abrir, responder', () async {
    final chamadas = <(String, Object?)>[];
    var status = 200;
    final servico = ServicoSacApi(ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        chamadas.add((
          '${req.method} ${req.url.path}',
          req.body.isEmpty ? null : jsonDecode(req.body),
        ));
        final corpo = status >= 400
            ? {'detail': 'x'}
            : req.method == 'GET' && req.url.path.endsWith('chamados')
                ? {
                    'itens': [
                      {'id': 'c1', 'protocolo': 'P1', 'assunto': 'A', 'status': 'aberto'}
                    ],
                    'total': 3,
                  }
                : {'id': 'c1', 'protocolo': 'P1', 'mensagens': <Object>[]};
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
            headers: const {'content-type': 'application/json'});
      }),
    ));
    final pagina = await servico.listar();
    expect((pagina!.total, pagina.itens.single.protocolo), (3, 'P1'));
    await servico.abrir(categoria: 'duvida', assunto: ' Oi ', texto: ' Texto ', pedidoId: 'p1');
    expect(chamadas.last.$2,
        {'categoria': 'duvida', 'assunto': 'Oi', 'texto': 'Texto', 'pedido_id': 'p1'});
    await servico.responder('c1', 'Mais');
    expect(chamadas.last.$1, 'POST /v1/sac/chamados/c1/mensagens');
    for (final s in [404, 503]) {
      status = s;
      expect(await servico.listar(), isNull);
      await expectLater(
        servico.abrir(categoria: 'duvida', assunto: 'abc', texto: 'x'),
        throwsA(predicate((e) => e is ErroTrato && e.mensagem == textoAtendimentoIndisponivel)),
      );
    }
    status = 403;
    await expectLater(servico.listar(), throwsA(isA<ErroTrato>()));
  });

  test('avisos "suporte" abrem o atendimento (push e caixa)', () {
    expect(
      resultadoDoPush({'evento': 'suporte.chamado_resposta', 'tela': 'suporte'}),
      const ResultadoLink.valido(DestinoApp.suporte, null),
    );
    for (final tipo in ['aberto', 'resposta', 'prazo']) {
      final r = RotasTrato.destinoDaCaixa(
        Notificacao(
          id: 'n',
          titulo: 't',
          texto: 'x',
          quando: 'agora',
          tipo: TipoNotificacao.sistema,
          tipoApi: 'suporte.chamado_$tipo',
        ),
        modoAtualProfissional: false,
      );
      expect(r?.destino, DestinoApp.suporte, reason: tipo);
    }
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('abre chamado: valida, erro, protocolo na hora e copiar ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        String? copiado;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
            (c) async {
          if (c.method == 'Clipboard.setData') copiado = (c.arguments as Map)['text'] as String?;
          return null;
        });
        final sac = _Sac();
        await t.pumpWidget(_app(AtendimentoTela(
          servico: sac,
          carregarPedidos: () async => [(id: 'p9', rotulo: 'Troca de chuveiro')],
          pedidoInicial: 'p9',
        )));
        await t.pumpAndSettle();
        await _ver(t, find.text('Você ainda não abriu nenhum chamado.'));
        await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await t.pumpAndSettle();
        await _tocar(t, find.byKey(const Key('abrir-chamado')));
        final enviar = find.byKey(const Key('enviar-chamado'));
        await _tocar(t, enviar);
        expect(sac.abertos, isEmpty);

        await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await t.pumpAndSettle();
        await _tocar(t, find.byKey(const Key('categoria-chamado')));
        await t.tap(find.text('Reclamação').last);
        await t.pumpAndSettle();
        for (final (chave, valor) in [
          ('assunto-chamado', 'Cobrança em dobro'),
          ('texto-chamado', 'Fui cobrado duas vezes.'),
        ]) {
          await _ver(t, find.byKey(Key(chave)));
          await t.enterText(find.byKey(Key(chave)), valor);
        }
        sac.falhar = true;
        await _tocar(t, enviar);
        await _ver(t, find.byKey(const Key('erro-chamado')));
        sac.falhar = false;
        await _tocar(t, enviar);
        expect(sac.abertos.single,
            ('reclamacao', 'Cobrança em dobro', 'Fui cobrado duas vezes.', 'p9'));
        expect(find.text('TR-2026-0007'), findsOneWidget);
        await _tocar(t, find.byKey(const Key('copiar-protocolo')));
        expect(copiado, 'TR-2026-0007');
        expect(t.takeException(), isNull);
      });

      testWidgets('conversa: prazo estendido, resposta e cópia ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final guardados = <(String, String)>[];
        final sac = _Sac(itens: [_chamado(), _chamado()]);
        await t.pumpWidget(_app(ChamadoTela(
          servico: sac,
          id: 'c1',
          guardar: (n, c) async => guardados.add((n, c)),
        )));
        await t.pumpAndSettle();
        await _ver(t, find.textContaining('Novo prazo de resposta: 10/12/2026'));
        await _ver(t, find.textContaining('Falta o extrato do parceiro.'));
        await _tocar(t, find.byKey(const Key('guardar-texto-legal')));
        final (nome, copia) = guardados.single;
        expect(nome, 'trato-atendimento-TR-2026-0007.txt');
        for (final parte in ['TR-2026-0007', 'Cobrança em dobro', 'Fui cobrado duas vezes.']) {
          expect(copia, contains(parte));
        }
        await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await t.pumpAndSettle();
        await _ver(t, find.byKey(const Key('resposta-chamado')));
        await t.enterText(find.byKey(const Key('resposta-chamado')), 'Segue o comprovante');
        sac.falhar = true;
        await _tocar(t, find.byKey(const Key('enviar-resposta')));
        await _ver(t, find.byKey(const Key('erro-resposta')));
        sac.falhar = false;
        await _tocar(t, find.byKey(const Key('enviar-resposta')));
        expect(sac.respostas, ['Segue o comprovante']);
        await _ver(t, find.text('Segue o comprovante'));
        expect(t.takeException(), isNull);
      });

      testWidgets('lista com "Ver mais"; encerrado não responde ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(
            _app(AtendimentoTela(servico: _Sac(itens: [_chamado(), _chamado()]))));
        await t.pumpAndSettle();
        await _tocar(t, find.byKey(const Key('mais-chamados')));
        expect(find.byKey(const Key('mais-chamados')), findsNothing);

        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(_app(ChamadoTela(
            servico: _Sac(), id: 'c1', inicial: _chamado(status: 'encerrado'))));
        await t.pumpAndSettle();
        await _ver(t, find.textContaining('foi encerrado'));
        expect(find.byKey(const Key('enviar-resposta')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('Ajuda: com atendimento mostra "Falar com o Trato"; sem, como antes ($r)',
          (t) async {
        await _janela(t, tamanho, fonte);
        for (final disponivel in [true, false]) {
          var abriu = 0;
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(AjudaTela(
            servico: const ServicoAjudaLocal(),
            aoFalarComSuporte: () {},
            verificarAtendimento: () async => disponivel,
            aoFalarComOTrato: () => abriu++,
          )));
          await t.pumpAndSettle();
          if (disponivel) {
            await _tocar(t, find.byKey(const Key('falar-com-o-trato')));
            expect(abriu, 1);
            await _ver(t, find.text('Escrever por e-mail'));
          } else {
            await _ver(t, find.text('Falar com o suporte'));
            expect(find.text('Falar com o Trato'), findsNothing);
          }
        }
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('servidor sem a rota: tela avisa e oferece o e-mail', (t) async {
    var email = 0;
    await t.pumpWidget(_app(AtendimentoTela(
        servico: _Sac(indisponivel: true), aoEscreverEmail: () => email++)));
    await t.pumpAndSettle();
    await t.tap(find.text('Escrever por e-mail'));
    expect(email, 1);
    expect(find.byKey(const Key('abrir-chamado')), findsNothing);
  });

  testWidgets('aviso do atendimento abre a lista de chamados', (t) async {
    RotasTrato.repos = repositoriosDemo(sac: _Sac());
    await t.pumpWidget(_app(Builder(
      builder: (c) => Scaffold(
        body: TextButton(
          onPressed: () =>
              RotasTrato.abrirDestino(c, DestinoApp.suporte, null, profissional: false),
          child: const Text('abrir'),
        ),
      ),
    )));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(find.byType(AtendimentoTela), findsOneWidget);
  });
}
