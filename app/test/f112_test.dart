// TERMOS-APP14: contestar a decisão da disputa (8.7), cliente e profissional.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servico_upload.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_camera.dart';
import 'package:trato/telas/atendimento/atendimento_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/contestacao_decisao/contestacao_decisao_tela.dart';
import 'package:trato/telas/contestacao_decisao/modelos.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/medidas/modelos.dart' show ProvaEscolhida;
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];
const _rota = '/v1/pedidos/ped-1/disputa/contestacoes';

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela, [GlobalKey<NavigatorState>? chave]) =>
    MaterialApp(theme: TemaTrato.claro, navigatorKey: chave, home: tela);

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

Uint8List _jpg([int n = 2048]) => Uint8List(n)..setRange(0, 3, const [0xFF, 0xD8, 0xFF]);

http.Response _json(Object corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json'},
    );

ClienteApi _api(Future<http.Response> Function(http.Request) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient(responder),
    );

Map<String, Object?> _item({bool minha = true, String status = 'aberta'}) => {
      'id': minha ? 'm1' : 'o1',
      'protocolo': minha ? 'CD-1' : 'CD-2',
      'minha': minha,
      'status': status,
      'aberta_em': '2026-11-20T10:00:00Z',
      'responder_ate': '2026-12-04T23:00:00Z',
      'o_que_faltou': minha ? 'Faltou ver as fotos.' : null,
      'anexos': minha ? ['a1', 'a2'] : <String>[],
      'resposta': status == 'alterada' ? 'As fotos mudam a análise.' : null,
      'nova_decisao': status == 'alterada' ? 'reembolso_parcial' : null,
      'novo_valor_reembolso_centavos': status == 'alterada' ? 4500 : null,
      'decidida_em': status == 'alterada' ? '2026-11-25T10:00:00Z' : null,
    };

class _Upload implements ServicoUpload {
  final enviados = <(String, String?, String)>[];
  int? falhaNo;
  var _n = 0;

  @override
  Future<ArquivoEnviado> enviar(ArquivoCapturado arquivo, FinalidadeArquivo finalidade,
      {String? pedidoId}) async {
    if (falhaNo == _n + 1) throw const ErroTrato(TipoErro.recusado, 'Arquivo grande demais.');
    enviados.add((finalidade.codigo, pedidoId, arquivo.mime));
    return ArquivoEnviado(arquivoId: 'arq${++_n}');
  }
}

class _Servico implements ServicoContestacaoDecisao {
  _Servico(this.dados, {this.falhaAoVer});
  ContestacoesDoPedido? dados;
  Object? falhaAoVer;
  Object? falhaAoEnviar;
  final enviadas = <(String, String, int)>[];

  @override
  bool get podeAnexar => true;

  @override
  Future<ContestacoesDoPedido?> ver(String pedidoId) async {
    if (falhaAoVer != null) throw falhaAoVer!;
    return dados;
  }

  @override
  Future<ContestacaoDaParte> contestar(String pedidoId, String oQueFaltou,
      {List<ProvaEscolhida> arquivos = const []}) async {
    if (falhaAoEnviar != null) throw falhaAoEnviar!;
    enviadas.add((pedidoId, oQueFaltou, arquivos.length));
    final minha = const ContestacaoDaParte(id: 'm1', status: 'aberta', minha: true, protocolo: 'CD-9');
    dados = ContestacoesDoPedido(
        podeContestar: false, contestarAte: dados?.contestarAte, itens: [minha]);
    return minha;
  }
}

ContestacoesDoPedido _aberta() =>
    ContestacoesDoPedido(podeContestar: true, contestarAte: DateTime(2026, 12, 3, 23, 59));

ContestacaoDecisaoTela _tela(_Servico s, {void Function()? aoFalar, Key? chave}) =>
    ContestacaoDecisaoTela(
      key: chave,
      servico: s,
      pedidoId: 'ped-1',
      aoFalarComOTrato: (_) => aoFalar?.call(),
      escolherFoto: () async => ProvaEscolhida(nome: 'foto.jpg', bytes: _jpg()),
    );

class _Pedidos extends RepositorioPedidosFake {
  _Pedidos(this.estado);
  final String estado;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => PedidoEmExecucao(
        numero: '#AB12',
        titulo: 'Serviço de teste',
        etapas: const [],
        fotos: const [],
        estadoApi: estado,
      );
}

class _Sac implements ServicoSac {
  @override
  Object? noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);

  group('1. API', () {
    test('lê os campos do servidor; campo ausente não quebra', () async {
      final caminhos = <String>[];
      final s = ServicoContestacaoDecisaoApi(_api((r) async {
        caminhos.add('${r.method} ${r.url.path}');
        return _json({
          'pode_contestar': false,
          'contestar_ate': '2026-12-03T23:59:59-03:00',
          'itens': [
            _item(status: 'alterada'),
            {'id': 'velho'},
          ],
        });
      }));
      final d = (await s.ver('ped-1'))!;
      expect(caminhos, ['GET $_rota']);
      expect((d.podeContestar, d.temDecisao, d.itens.length), (false, true, 2));
      final c = d.minha!;
      expect(
        (c.protocolo, c.status, c.oQueFaltou, c.anexos.length, c.novoValorReembolsoCentavos),
        ('CD-1', 'alterada', 'Faltou ver as fotos.', 2, 4500),
      );
      expect(c.resposta, 'As fotos mudam a análise.');
      expect(c.novaDecisaoTexto, 'Devolver parte do valor ao cliente');
      expect(c.decididaEm, isNotNull);
      expect(d.itens.last.minha, isFalse);
      expect(d.itens.last.statusTexto, 'Contestação registrada');
    });

    test('sem decisão', () async {
      final s = ServicoContestacaoDecisaoApi(
          _api((_) async => _json({'pode_contestar': false, 'contestar_ate': null, 'itens': []})));
      expect((await s.ver('ped-1'))!.temDecisao, isFalse);
    });

    for (final status in [404, 503]) {
      test('GET $status: sem a função (nulo)', () async {
        final s = ServicoContestacaoDecisaoApi(
            _api((_) async => _json({'detail': 'x', 'codigo': 'indisponivel'}, status)));
        expect(await s.ver('ped-1'), isNull);
      });
    }

    test('GET 500 é erro', () async {
      final s = ServicoContestacaoDecisaoApi(_api((_) async => _json({'detail': 'x'}, 500)));
      await expectLater(s.ver('ped-1'), throwsA(isA<ErroTrato>()));
    });

    for (final status in [201, 200]) {
      test('envia os arquivos do pedido e depois a contestação ($status)', () async {
        final upload = _Upload();
        Object? corpo;
        final s = ServicoContestacaoDecisaoApi(_api((r) async {
          expect('${r.method} ${r.url.path}', 'POST $_rota');
          corpo = jsonDecode(r.body);
          return _json(_item(), status);
        }), upload: upload);
        final c = await s.contestar('ped-1', '  Faltou ver as fotos.  ',
            arquivos: [ProvaEscolhida(nome: 'f.jpg', bytes: _jpg())]);
        expect(upload.enviados, [('disputa', 'ped-1', 'image/jpeg')]);
        expect(corpo, {
          'o_que_faltou': 'Faltou ver as fotos.',
          'anexos': ['arq1'],
        });
        expect(c.protocolo, 'CD-1');
      });
    }

    test('falha num arquivo aponta qual; tentar de novo não reenvia os que subiram', () async {
      final upload = _Upload()..falhaNo = 2;
      var posts = 0;
      final s = ServicoContestacaoDecisaoApi(_api((_) async {
        posts++;
        return _json(_item(), 201);
      }), upload: upload);
      final arquivos = [
        ProvaEscolhida(nome: '1.jpg', bytes: _jpg()),
        ProvaEscolhida(nome: '2.jpg', bytes: _jpg()),
      ];
      await expectLater(
        s.contestar('ped-1', 'Faltou ver as fotos.', arquivos: arquivos),
        throwsA(isA<ErroDeArquivo>().having((e) => e.indice, 'indice', 1)),
      );
      expect(posts, 0);
      upload.falhaNo = null;
      await s.contestar('ped-1', 'Faltou ver as fotos.', arquivos: arquivos);
      expect(upload.enviados.length, 2);
      expect(posts, 1);
    });

    for (final (codigo, status, mensagem) in [
      ('sem_decisao', 409, 'Só dá para contestar uma disputa já decidida.'),
      ('prazo_encerrado', 409, 'O prazo para contestar esta decisão terminou.'),
      ('ja_contestada', 409, 'Esta parte já contestou a decisão.'),
      ('anexo_invalido', 422, 'Cada anexo precisa ter sido enviado pela própria parte.'),
      ('pedido_nao_encontrado', 404, 'Pedido não encontrado.'),
      ('indisponivel', 503, 'A contestação ainda não está disponível. Fale com o atendimento.'),
    ]) {
      test('POST $status $codigo vira erro com mensagem', () async {
        final s = ServicoContestacaoDecisaoApi(
          _api((_) async => _json({'detail': mensagem, 'codigo': codigo}, status)),
          upload: _Upload(),
        );
        final arquivo = ProvaEscolhida(nome: 'f.jpg', bytes: _jpg());
        Object? erro;
        try {
          await s.contestar('ped-1', 'Faltou ver as fotos.', arquivos: [arquivo]);
        } on Object catch (e) {
          erro = e;
        }
        expect(erro, isA<ErroTrato>());
        expect((erro! as ErroTrato).codigo, codigo);
        // Mensagem mostrada na tela (o 404 usa o texto padrão do app).
        expect(mensagemErroTrato(erro), isNotEmpty);
        if (status != 404) expect(mensagemErroTrato(erro), mensagem);
        expect(arquivo.anexoId, codigo == 'anexo_invalido' ? isNull : 'arq1');
      });
    }
  });

  group('2. Tela', () {
    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} fonte $fonte';

        testWidgets('valida, envia com foto e mostra o protocolo ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final s = _Servico(_aberta());
          await t.pumpWidget(_app(_tela(s)));
          expect(find.bySemanticsLabel('Carregando'), findsOneWidget);
          await t.pumpAndSettle();
          expect(find.byKey(const Key('prazo-contestar')), findsOneWidget);
          final enviar = find.byKey(const Key('enviar-contestacao-decisao'));
          final campo = find.byKey(const Key('o-que-faltou'));
          await t.enterText(campo, 'curto');
          await _tocar(t, enviar);
          expect(find.text('Escreva pelo menos 10 caracteres.'), findsOneWidget);
          expect(s.enviadas, isEmpty);

          await t.enterText(campo, 'Faltou ver as fotos.');
          await _tocar(t, find.byKey(const Key('adicionar-arquivo')));
          expect(find.textContaining('1. Foto JPG · 2 KB'), findsOneWidget);
          await _tocar(t, enviar);
          expect(s.enviadas, [('ped-1', 'Faltou ver as fotos.', 1)]);
          expect(find.textContaining('Protocolo CD-9.'), findsOneWidget);
          expect(find.byKey(const Key('o-que-faltou')), findsNothing);
          expect(find.text('Sua contestação'), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets('erro mantém texto e arquivos, junto do item ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final s = _Servico(_aberta())
            ..falhaAoEnviar = const ErroDeArquivo(0, 'Arquivo grande demais.');
          await t.pumpWidget(_app(_tela(s)));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('o-que-faltou')), 'Faltou ver as fotos.');
          await _tocar(t, find.byKey(const Key('adicionar-arquivo')));
          final enviar = find.byKey(const Key('enviar-contestacao-decisao'));
          await _tocar(t, enviar);
          expect(find.byKey(const ValueKey('erro-arquivo-0')), findsOneWidget);
          expect(find.textContaining('1. Foto JPG'), findsOneWidget);

          s.falhaAoEnviar = const ErroTrato(
              TipoErro.recusado, 'O prazo para contestar esta decisão terminou.',
              codigoHttp: 409, codigo: 'prazo_encerrado');
          await _tocar(t, enviar);
          expect(find.byKey(const Key('erro-contestar-decisao')), findsOneWidget);
          expect(find.text('O prazo para contestar esta decisão terminou.'), findsOneWidget);
          expect(find.byKey(const ValueKey('erro-arquivo-0')), findsNothing);
          expect(find.textContaining('1. Foto JPG'), findsOneWidget);
          expect(
            t.widget<TextField>(find.byType(TextField)).controller!.text,
            'Faltou ver as fotos.',
          );
          await _tocar(t, find.byKey(const ValueKey('remover-arquivo-0')));
          expect(find.textContaining('1. Foto JPG'), findsNothing);
          expect(t.takeException(), isNull);
        });

        testWidgets('as duas contestações, resposta e nova decisão ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final dados = ContestacoesDoPedido.deJson({
            'pode_contestar': false,
            'contestar_ate': '2026-12-03T23:59:59-03:00',
            'itens': [_item(status: 'alterada'), _item(minha: false, status: 'em_analise')],
          });
          var falas = 0;
          await t.pumpWidget(_app(_tela(_Servico(dados), aoFalar: () => falas++)));
          await t.pumpAndSettle();
          for (final texto in [
            'Sua contestação',
            'Analisada: decisão alterada',
            'Protocolo CD-1',
            'Faltou ver as fotos.',
            'Arquivos enviados',
            'As fotos mudam a análise.',
            'Devolver parte do valor ao cliente',
            'R\$ 45,00',
            'Contestação da outra parte',
            'Em análise',
            'Resposta até',
          ]) {
            expect(find.text(texto), findsOneWidget, reason: texto);
          }
          expect(find.byKey(const Key('o-que-faltou')), findsNothing);
          expect(find.byKey(const Key('prazo-encerrado')), findsNothing);
          await _tocar(t, find.byKey(const Key('falar-sobre-decisao')));
          expect(falas, 1);
          expect(t.takeException(), isNull);
        });

        testWidgets('erro, sem decisão, indisponível e prazo encerrado ($r)', (t) async {
          await _janela(t, tamanho, fonte);
          final s = _Servico(const ContestacoesDoPedido(podeContestar: false),
              falhaAoVer: const ErroTrato(TipoErro.semInternet, 'Sem internet.'));
          await t.pumpWidget(_app(_tela(s)));
          await t.pumpAndSettle();
          expect(find.text('Sem internet.'), findsOneWidget);
          s.falhaAoVer = null;
          await _tocar(t, find.text('Tentar de novo'));
          expect(find.text('Nenhuma decisão para contestar'), findsOneWidget);

          var falas = 0;
          await t.pumpWidget(
              _app(_tela(_Servico(null), aoFalar: () => falas++, chave: const Key('b'))));
          await t.pumpAndSettle();
          expect(find.text('Contestação indisponível'), findsOneWidget);
          await _tocar(t, find.text('Falar com o Trato'));
          expect(falas, 1);

          await t.pumpWidget(_app(_tela(
            _Servico(ContestacoesDoPedido(podeContestar: false, contestarAte: DateTime(2026, 1, 5))),
            chave: const Key('c'),
          )));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('prazo-encerrado')), findsOneWidget);
          expect(find.byKey(const Key('o-que-faltou')), findsNothing);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('3. Entrada no pedido', () {
    for (final profissional in [false, true]) {
      final quem = profissional ? 'profissional' : 'cliente';
      for (final (nome, estado, servico, aparece) in [
        ('com decisão', 'concluido', _Servico(_aberta()), true),
        ('cancelado com decisão', 'cancelado', _Servico(_aberta()), true),
        ('404/503', 'concluido', _Servico(null), false),
        (
          'sem decisão',
          'concluido',
          _Servico(const ContestacoesDoPedido(podeContestar: false)),
          false
        ),
        ('estado sem decisão possível', 'agendado', _Servico(_aberta()), false),
        (
          'falha passageira',
          'retrabalho',
          _Servico(null, falhaAoVer: StateError('rede')),
          true
        ),
      ]) {
        testWidgets('$quem, $nome: aparece = $aparece', (t) async {
          await _janela(t, const Size(320, 568), 1.3);
          RotasTrato.repos =
              repositoriosDemo(pedidos: _Pedidos(estado), contestacaoDecisao: servico);
          final nav = GlobalKey<NavigatorState>();
          await t.pumpWidget(_app(const Scaffold(), nav));
          RotasTrato.abrirDestino(nav.currentContext!, DestinoApp.pedido, 'ped-1',
              profissional: profissional);
          await t.pumpAndSettle();
          final entrada =
              find.byKey(const Key('abrir-contestacao-decisao'), skipOffstage: false);
          expect(entrada, aparece ? findsOneWidget : findsNothing);
          if (aparece) {
            await _tocar(t, entrada);
            expect(find.byType(ContestacaoDecisaoTela), findsOneWidget);
          }
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('menu do pedido do profissional tem a entrada', (t) async {
      await _janela(t, const Size(390, 844), 1);
      RotasTrato.repos = repositoriosDemo(contestacaoDecisao: _Servico(_aberta()));
      await t.pumpWidget(_app(Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () =>
                RotasTrato.acoesPedidoProfissionalParaTeste(c, estadoApi: 'concluido'),
            child: const Text('menu'),
          ),
        ),
      )));
      await _tocar(t, find.text('menu'));
      await _tocar(t, find.byKey(const Key('abrir-contestacao-decisao')));
      expect(t.widget<ContestacaoDecisaoTela>(find.byType(ContestacaoDecisaoTela)).pedidoId, 'p1');
      expect(t.takeException(), isNull);
    });
  });

  group('4. Avisos', () {
    for (final evento in ['disputa.contestada', 'disputa.contestacao_decidida']) {
      test('push e caixa: $evento abre a contestação', () {
        const esperado = ResultadoLink.valido(DestinoApp.contestacaoDecisao, 'ped-1');
        expect(
          resultadoDoPush({'evento': evento, 'tela': 'pedido', 'pedido_id': 'ped-1'}),
          esperado,
        );
        expect(
          resultadoDoPush({'evento': evento, 'tela': 'pedido', 'pedido_id': '../x'}).situacao,
          SituacaoLink.invalido,
        );
        for (final tela in ['pedido', null]) {
          final r = RotasTrato.destinoDaCaixa(
            Notificacao(
              id: 'n',
              titulo: 't',
              texto: 'x',
              quando: 'agora',
              tipo: TipoNotificacao.disputa,
              tipoApi: evento,
              destinoId: 'ped-1',
              tela: tela,
            ),
            modoAtualProfissional: true,
          );
          expect(r, esperado, reason: 'tela: $tela');
        }
      });
    }

    test('outro aviso com tela pedido segue abrindo o pedido', () {
      expect(
        resultadoDoPush({'evento': 'disputa.aberta', 'tela': 'pedido', 'pedido_id': 'ped-1'}),
        const ResultadoLink.valido(DestinoApp.pedido, 'ped-1'),
      );
    });

    for (final bloqueada in [false, true]) {
      testWidgets('push (conta bloqueada: $bloqueada)', (t) async {
        await _janela(t, const Size(390, 844), 1);
        RotasTrato.repos =
            repositoriosDemo(contestacaoDecisao: _Servico(_aberta()), sac: _Sac());
        final nav = GlobalKey<NavigatorState>();
        final anterior = DeepLinks.navegador;
        DeepLinks.navegador = () => nav.currentState;
        addTearDown(() => DeepLinks.navegador = anterior);
        await entrarNaContaDeTeste(ServicoAuthPadrao.atual);
        await t.pumpWidget(
            _app(bloqueada ? const Scaffold() : RotasTrato.cascaProfissionalParaTeste(), nav));
        await t.pumpAndSettle();
        if (bloqueada) {
          RotasTrato.contaFoiBloqueada(() => nav.currentState, null);
          await t.pumpAndSettle();
        }
        // Ids diferentes: o mesmo toque repetido em 2 s é ignorado.
        final id = bloqueada ? 'ped-bloq' : 'ped-push';
        DeepLinks.receberPush(
            {'evento': 'disputa.contestada', 'tela': 'pedido', 'pedido_id': id});
        await t.pumpAndSettle();
        // Termos 20.10: bloqueado também contesta a decisão do próprio pedido.
        expect(find.byType(AtendimentoTela), findsNothing);
        expect(
            t.widget<ContestacaoDecisaoTela>(find.byType(ContestacaoDecisaoTela)).pedidoId, id);
      });
    }
  });
}
