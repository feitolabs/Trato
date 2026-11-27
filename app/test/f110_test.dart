// TERMOS-APP12: provas na contestação de medida (20.5) e aviso do atendimento abrindo o chamado.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/atendimento/atendimento_tela.dart';
import 'package:trato/telas/atendimento/modelos.dart';
import 'package:trato/telas/fluxo/deep_link.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/medidas/medidas_tela.dart';
import 'package:trato/telas/medidas/modelos.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
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

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  final lista = find.byType(Scrollable).first;
  if (alvo.evaluate().isEmpty) {
    await t.drag(lista, const Offset(0, 4000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(alvo, 120, scrollable: lista);
  }
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

Uint8List _pdf([int tamanho = 2048]) =>
    Uint8List(tamanho)..setRange(0, 5, '%PDF-'.codeUnits);

Uint8List _png() => Uint8List(64)..setRange(0, 4, const [0x89, 0x50, 0x4E, 0x47]);

class _Servidor {
  _Servidor({this.semRotaDeAnexo = false});
  final bool semRotaDeAnexo;
  final chamadas = <(String, Object?)>[];
  final puts = <(String, String, int, String?)>[];
  var falhaNoPut = false;
  (int, Map<String, Object>)? falhaNaContestacao;
  var _n = 0;

  late final servico = ServicoMedidasApi(
    ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        final corpo = req.body.isEmpty ? null : jsonDecode(req.body);
        chamadas.add(('${req.method} ${req.url.path}', corpo));
        (int, Object) r;
        if (req.url.path.endsWith('/contestacao/anexos')) {
          r = semRotaDeAnexo
              ? (404, {'detail': 'Not Found'})
              : (201, {'anexo_id': 'a${++_n}', 'url': 'https://arquivos/a$_n'});
        } else if (falhaNaContestacao != null) {
          r = falhaNaContestacao!;
        } else {
          r = (
            200,
            {
              'id': 'm1',
              'tipo': 'aviso',
              'contestacao': {
                'status': 'aberta',
                'versao': 'v',
                'anexos': [
                  {'anexo_id': 'a1', 'content_type': 'application/pdf', 'tamanho_bytes': 2048}
                ],
              },
            }
          );
        }
        return http.Response.bytes(utf8.encode(jsonEncode(r.$2)), r.$1,
            headers: const {'content-type': 'application/json'});
      }),
    ),
    cliente: MockClient((req) async {
      puts.add((
        req.method,
        '${req.url}',
        req.bodyBytes.length,
        req.headers['Authorization'],
      ));
      return http.Response('', falhaNoPut ? 500 : 200);
    }),
  );

  List<String> get rotas => [for (final c in chamadas) c.$1.split('/').last];
}

Matcher _erro(String parte) =>
    throwsA(predicate((e) => e is ErroTrato && e.mensagem.contains(parte)));

class _Sac implements ServicoSac {
  final vistos = <String>[];

  @override
  Future<PaginaDeChamados?> listar({int deslocamento = 0}) async =>
      const PaginaDeChamados(itens: [], total: 0);

  @override
  Future<Chamado> ver(String id) async {
    vistos.add(id);
    return Chamado(id: id, protocolo: 'TR-9', assunto: 'Assunto $id', status: 'respondido');
  }

  @override
  Object? noSuchMethod(Invocation i) => super.noSuchMethod(i);
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

  group('1. Provas: envio', () {
    test('pede o link, faz o PUT sem a sessão e contesta com os anexo_id', () async {
      final s = _Servidor();
      await s.servico.contestar('m1', ' Minha versão ',
          provas: [ProvaEscolhida(nome: 'nota.pdf', bytes: _pdf()),
            ProvaEscolhida(nome: 'foto.png', bytes: _png())]);
      expect(s.rotas, ['anexos', 'anexos', 'contestacao']);
      expect(s.chamadas[0].$2,
          {'nome_arquivo': 'nota.pdf', 'content_type': 'application/pdf', 'tamanho_bytes': 2048});
      expect((s.chamadas[1].$2! as Map)['content_type'], 'image/png');
      expect(s.puts, [
        ('PUT', 'https://arquivos/a1', 2048, null),
        ('PUT', 'https://arquivos/a2', 64, null),
      ]);
      expect(s.chamadas.last.$2, {
        'versao': 'Minha versão',
        'anexos': ['a1', 'a2'],
      });
    });

    test('sem arquivo (e no servidor antigo) vai só o texto', () async {
      final s = _Servidor(semRotaDeAnexo: true);
      await s.servico.contestar('m1', 'Só texto');
      expect(s.rotas, ['contestacao']);
      expect(s.chamadas.single.$2, {'versao': 'Só texto'});
      await expectLater(
        s.servico.contestar('m1', 'x', provas: [ProvaEscolhida(nome: 'n.pdf', bytes: _pdf())]),
        _erro('só com o texto'),
      );
    });

    test('falha no PUT; retentativa não repete o que já subiu', () async {
      final s = _Servidor();
      final provas = [ProvaEscolhida(nome: 'n.pdf', bytes: _pdf())];
      s.falhaNoPut = true;
      await expectLater(
          s.servico.contestar('m1', 'x', provas: provas), _erro('"n.pdf"'));
      expect(s.rotas, ['anexos']);
      s.falhaNoPut = false;
      s.falhaNaContestacao = (503, {'detail': 'x', 'codigo': 'indisponivel'});
      await expectLater(
          s.servico.contestar('m1', 'x', provas: provas), _erro('indisponíveis'));
      expect(provas.single.anexoId, 'a2');
      s.falhaNaContestacao = null;
      await s.servico.contestar('m1', 'x', provas: provas);
      expect(s.puts.length, 2, reason: 'um que falhou e um que valeu');
      expect((s.chamadas.last.$2! as Map)['anexos'], ['a2']);
    });

    test('códigos: o recusado sobe de novo; os outros têm texto claro', () async {
      for (final (status, codigo, texto, sobeDeNovo) in [
        (409, 'anexo_nao_enviado', 'não chegou', true),
        (422, 'arquivo_invalido', 'detalhe', true),
        (422, 'anexo_invalido', 'detalhe', true),
        (409, 'prazo_encerrado', '30 dias', false),
        (409, 'ja_contestada', 'já foi contestada', false),
        (404, 'nao_encontrada', 'não encontrada', false),
      ]) {
        final s = _Servidor()
          ..falhaNaContestacao = (status, {'detail': 'detalhe', 'codigo': codigo});
        final provas = [ProvaEscolhida(nome: 'n.pdf', bytes: _pdf())];
        await expectLater(s.servico.contestar('m1', 'x', provas: provas), _erro(texto),
            reason: codigo);
        expect(provas.single.anexoId == null, sobeDeNovo, reason: codigo);
      }
    });

    test('tipo pelo conteúdo; a saída lista o que foi enviado', () {
      expect(tipoDaProva(_pdf()), 'application/pdf');
      expect(tipoDaProva(_png()), 'image/png');
      expect(tipoDaProva(Uint8List.fromList('oi.pdf'.codeUnits)), isNull);
      final c = ContestacaoDeMedida.deJson(const {
        'status': 'aberta',
        'anexos': [
          {'anexo_id': 'a', 'content_type': 'image/jpeg', 'tamanho_bytes': 1572864}
        ],
      });
      expect(nomeDoTipo(c.anexos.single.contentType), 'Foto JPG');
      expect(tamanhoLegivel(c.anexos.single.tamanhoBytes), '1,5 MB');
    });
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('1. tela: recusa arquivo ruim; erro não perde texto nem arquivos ($r)',
          (t) async {
        await _janela(t, tamanho, fonte);
        final s = _Servidor();
        final fila = [
          ProvaEscolhida(nome: 'texto.txt', bytes: Uint8List.fromList('oi'.codeUnits)),
          ProvaEscolhida(nome: 'enorme.pdf', bytes: _pdf(tamanhoMaximoDaProva + 1)),
          ProvaEscolhida(nome: 'nota.pdf', bytes: _pdf()),
          ProvaEscolhida(nome: 'foto.png', bytes: _png()),
        ];
        await t.pumpWidget(_app(ContestarMedidaTela(
          servico: s.servico,
          medida: const MedidaDeConta(id: 'm1', tipo: 'aviso'),
          escolherProva: () async => fila.removeAt(0),
        )));
        await t.pumpAndSettle();
        final adicionar = find.byKey(const Key('adicionar-prova'));
        await _tocar(t, adicionar);
        expect(find.text(textoProvaRecusada, skipOffstage: false), findsOneWidget);
        await _tocar(t, adicionar);
        expect(find.textContaining('passa de 10 MB', skipOffstage: false), findsOneWidget);
        await _tocar(t, adicionar);
        await _tocar(t, adicionar);
        await _tocar(t, find.byKey(const ValueKey('remover-prova-1')));
        expect(find.textContaining('foto.png', skipOffstage: false), findsNothing);

        final campo = find.byKey(const Key('versao-contestacao'));
        await t.drag(find.byType(Scrollable).first, const Offset(0, 4000));
        await t.pumpAndSettle();
        await t.enterText(campo, 'Não fui eu.');
        s.falhaNoPut = true;
        final enviar = find.byKey(const Key('enviar-contestacao-medida'));
        await _tocar(t, enviar);
        expect(find.byKey(const Key('erro-contestacao-medida'), skipOffstage: false),
            findsOneWidget);
        expect(find.textContaining('nota.pdf · 2 KB', skipOffstage: false), findsOneWidget);
        expect(t.widget<TextField>(find.byType(TextField, skipOffstage: false)).controller!.text,
            'Não fui eu.');

        s.falhaNoPut = false;
        await _tocar(t, enviar);
        expect((s.chamadas.last.$2! as Map)['anexos'], hasLength(1));
        expect(find.byKey(const Key('contestacao-recebida'), skipOffstage: false),
            findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('1. lista mostra as provas enviadas ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(MedidasTela(servico: _Lista())));
        await t.pumpAndSettle();
        final provas = find.textContaining('1. PDF · 2 KB');
        await t.scrollUntilVisible(provas, 150, scrollable: find.byType(Scrollable).first);
        expect(provas, findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('1. conta bloqueada: contestação com prova a partir do bloqueio', (t) async {
    await _janela(t, const Size(390, 2400), 1);
    RotasTrato.repos = repositoriosDemo(medidas: _Lista(contestada: false));
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(const Scaffold(), nav));
    RotasTrato.contaFoiBloqueada(() => nav.currentState, null);
    await t.pumpAndSettle();
    await _tocar(t, find.byKey(const Key('bloqueio-medidas')));
    await _tocar(t, find.byKey(const ValueKey('contestar-m1')));
    expect(find.byKey(const Key('adicionar-prova')), findsOneWidget);
  });

  group('2. Aviso do atendimento abre o chamado', () {
    test('push e caixa levam o chamado_id; sem ele (ou ruim), a lista', () {
      ResultadoLink push(Object? id) => resultadoDoPush(
          {'tela': 'suporte', 'evento': 'suporte.chamado_resposta', 'chamado_id': id});
      expect(push('c-123'), const ResultadoLink.valido(DestinoApp.suporte, 'c-123'));
      for (final ruim in [null, '', '../x', 7]) {
        expect(push(ruim), const ResultadoLink.valido(DestinoApp.suporte, null), reason: '$ruim');
      }
      for (final tipo in ['aberto', 'resposta', 'prazo']) {
        final r = RotasTrato.destinoDaCaixa(
          Notificacao(
              id: 'n',
              titulo: 't',
              texto: 'x',
              quando: 'agora',
              tipo: TipoNotificacao.sistema,
              tipoApi: 'suporte.chamado_$tipo',
              chamadoId: 'c9'),
          modoAtualProfissional: false,
        );
        expect(r, const ResultadoLink.valido(DestinoApp.suporte, 'c9'), reason: tipo);
      }
    });

    test('a caixa lê dados.chamado_id da API', () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((_) async => http.Response(
              jsonEncode([
                {
                  'id': 'n1',
                  'tipo': 'suporte.chamado_resposta',
                  'titulo': 't',
                  'criada_em': '2026-11-26T09:00:00Z',
                  'dados': {'tela': 'suporte', 'chamado_id': 'c42'},
                }
              ]),
              200,
              headers: const {'content-type': 'application/json'},
            )),
      );
      final lista =
          await ServicoNotificacoesRepositorio(RepositorioNotificacoesApi(api)).listar();
      expect(lista.single.chamadoId, 'c42');
    });

    for (final bloqueada in [false, true]) {
      testWidgets('push abre o chamado certo (bloqueada: $bloqueada)', (t) async {
        final sac = _Sac();
        RotasTrato.repos = repositoriosDemo(sac: sac);
        final nav = GlobalKey<NavigatorState>();
        final anterior = DeepLinks.navegador;
        DeepLinks.navegador = () => nav.currentState;
        addTearDown(() => DeepLinks.navegador = anterior);
        await entrarNaContaDeTeste(ServicoAuthPadrao.atual);
        await t.pumpWidget(_app(const Scaffold(), nav));
        if (bloqueada) {
          RotasTrato.contaFoiBloqueada(() => nav.currentState, null);
          await t.pumpAndSettle();
          DeepLinks.receberPush({'tela': 'suporte', 'chamado_id': 'c7'});
        } else {
          RotasTrato.abrirDestino(nav.currentContext!, DestinoApp.suporte, 'c7',
              profissional: false);
        }
        await t.pumpAndSettle();
        expect(find.byType(ChamadoTela), findsOneWidget);
        expect(sac.vistos, ['c7']);
        expect(find.text('Assunto c7'), findsOneWidget);
      });
    }
  });
}

class _Lista implements ServicoMedidas {
  _Lista({this.contestada = true});
  final bool contestada;

  @override
  Future<List<MedidaDeConta>?> listar() async => [
        MedidaDeConta(
          id: 'm1',
          tipo: 'aviso',
          contestavelAte: DateTime.now().add(const Duration(days: 10)),
          contestacao: contestada
              ? const ContestacaoDeMedida(status: 'aberta', versao: 'v', anexos: [
                  AnexoDaContestacao(
                      anexoId: 'a', contentType: 'application/pdf', tamanhoBytes: 2048)
                ])
              : null,
        ),
      ];

  @override
  Object? noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
