// TERMOS-APP9: provas e contestação da ausência (Termos 7.6 e 8.7).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/abrir_link.dart';
import 'package:trato/telas/ausencia/ausencia_tela.dart';
import 'package:trato/telas/ausencia/modelos.dart';
import 'package:trato/tema/tema.dart';

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

final _prazo = DateTime.now().add(const Duration(days: 5));

CasoAusencia _caso({DateTime? ate, ContestacaoAusencia? contestacao}) => CasoAusencia(
      status: 'justificativa_recusada',
      justificativaTexto: 'Texto do cliente',
      decisao: 'Sem comprovação.',
      retencaoCentavos: 3000,
      retencaoJustificativa: 'Deslocamento.',
      cancelamentoStatus: 'proposta_retencao_enviada',
      contestarAte: ate ?? _prazo,
      contestacao: contestacao,
    );

const _anexos = [
  AnexoAusencia(tipo: 'registro_ausencia', arquivoId: 'a1', enviadoPor: 'profissional'),
  AnexoAusencia(tipo: 'comprovante_retencao', arquivoId: 'a2', enviadoPor: 'equipe'),
  AnexoAusencia(tipo: 'justificativa', arquivoId: 'a3', enviadoPor: 'cliente'),
];

(ClienteApi, List<(String, Object?)>) _api(Map<String, (int, Object)> respostas) {
  final chamadas = <(String, Object?)>[];
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((req) async {
      final chave = '${req.method} ${req.url.path}';
      chamadas.add((chave, req.body.isEmpty ? null : jsonDecode(req.body)));
      final (status, corpo) = respostas[chave] ?? (404, {'detail': 'Not Found'});
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return (api, chamadas);
}

void main() {
  setUpAll(carregarFontesTrato);

  group('API', () {
    test('lê prazo, contestação e anexos; 404/503 não quebram', () async {
      final (api, chamadas) = _api({
        'GET /v1/pedidos/p1/ausencia/anexos': (
          200,
          [
            {
              'tipo': 'comprovante_retencao',
              'arquivo_id': 'x',
              'enviado_por': 'equipe',
              'url': 'https://a/x',
              'expira_em_segundos': 300,
            }
          ]
        ),
        'GET /v1/pedidos/p3/ausencia/anexos': (503, {'detail': 'x'}),
        'GET /v1/pedidos/p4/ausencia/anexos': (403, {'detail': 'não'}),
        'POST /v1/pedidos/p1/ausencia/contestacao': (200, {'status': 'justificativa_recusada'}),
        'POST /v1/pedidos/p3/ausencia/contestacao': (503, {'detail': 'x'}),
      });
      final repo = RepositorioPedidosApi(api);
      expect((await repo.anexosDaAusencia('p1'))!.single.url, 'https://a/x');
      expect(await repo.anexosDaAusencia('p2'), isNull);
      expect(await repo.anexosDaAusencia('p3'), isNull);
      await expectLater(repo.anexosDaAusencia('p4'), throwsA(isA<ErroTrato>()));
      await repo.contestarAusencia('p1', ' Avisei antes ', const []);
      expect(chamadas.last.$2, {'texto': 'Avisei antes', 'anexos': <Object?>[]});
      await expectLater(
        repo.contestarAusencia('p3', 'x', const []),
        throwsA(predicate((e) => e is ErroTrato && e.mensagem.contains('Fale com o suporte'))),
      );

      final caso = CasoAusencia.deJson(const {
        'status': 'em_analise',
        'contestar_ate': '2026-12-03T02:59:59Z',
        'contestacao': {'status': 'aberta', 'protocolo': 'C-1'},
      });
      expect(caso.contestarAte, isNotNull);
      expect(caso.contestacao!.protocolo, 'C-1');
      final antigo = CasoAusencia.deJson(const {'status': 'em_analise'});
      expect((antigo.contestarAte, antigo.contestacao), (null, null));
    });
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('cliente vê as provas e contesta até o prazo ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final enviadas = <String>[];
        var falhar = true;
        await t.pumpWidget(_app(AusenciaTela(
          carregar: () async => _caso(),
          profissional: false,
          carregarAnexos: () async => _anexos,
          contestar: (texto, fotos) async {
            if (falhar) {
              throw const ErroTrato(TipoErro.recusado, 'O prazo para contestar terminou.');
            }
            enviadas.add(texto);
            return _caso(
                contestacao: ContestacaoAusencia(
                    status: 'aberta', protocolo: 'C-7', texto: texto, responderAte: _prazo));
          },
        )));
        await t.pumpAndSettle();
        await _ver(t, find.textContaining('Você pode contestar até'));
        await _ver(t, find.text('Comprovante de custo'));
        expect(find.text('Arquivo indisponível.', skipOffstage: false), findsWidgets);

        final enviar = find.byKey(const Key('enviar-contestacao'));
        await _tocar(t, enviar);
        await _ver(t, find.byKey(const Key('erro-contestacao')));
        await _ver(t, find.byKey(const Key('texto-contestacao')));
        await t.enterText(find.byKey(const Key('texto-contestacao')), 'Eu estava no local');
        await _tocar(t, enviar);
        await _ver(t, find.text('O prazo para contestar terminou.'));

        falhar = false;
        await _tocar(t, enviar);
        expect(enviadas, ['Eu estava no local']);
        await t.drag(find.byType(Scrollable).first, const Offset(0, 4000));
        await t.pumpAndSettle();
        await _ver(t, find.text('Contestação em análise'));
        await _ver(t, find.text('Nada é cobrado até a resposta.'));
        expect(enviar, findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('prazo vencido: sem formulário ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(AusenciaTela(
          carregar: () async => _caso(ate: DateTime(2026, 1, 5)),
          profissional: false,
          carregarAnexos: () async => const [],
          contestar: (_, __) async => _caso(),
        )));
        await t.pumpAndSettle();
        await _ver(t, find.textContaining('O prazo para contestar terminou em 05/01'));
        await _ver(t, find.text('Nenhuma foto anexada.'));
        expect(find.byKey(const Key('enviar-contestacao')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('profissional vê só o que enviou e a situação ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(AusenciaTela(
          carregar: () async => _caso(
              contestacao: const ContestacaoAusencia(
                  status: 'mantida', texto: 'Texto da contestação', resposta: 'Mantida.')),
          profissional: true,
          carregarAnexos: () async => _anexos,
          contestar: (_, __) async => _caso(),
        )));
        await t.pumpAndSettle();
        await _ver(t, find.text('Contestação analisada: retenção mantida'));
        expect(find.textContaining('Texto do cliente', skipOffstage: false), findsNothing);
        expect(find.textContaining('Texto da contestação', skipOffstage: false), findsNothing);
        await _ver(t, find.text('Registro no local'));
        await _ver(t, find.byKey(const Key('atualizar-provas')));
        expect(find.text('Comprovante de custo', skipOffstage: false), findsNothing);
        expect(find.text('Justificativa', skipOffstage: false), findsNothing);
        expect(find.byKey(const Key('enviar-contestacao')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('servidor antigo esconde as provas; falha tem nova tentativa ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        await t.pumpWidget(_app(AusenciaTela(
          carregar: () async => const CasoAusencia(status: 'em_analise'),
          profissional: false,
          carregarAnexos: () async => null,
        )));
        await t.pumpAndSettle();
        expect(find.text('Fotos e comprovantes'), findsNothing);
        expect(find.byKey(const Key('prazo-contestacao')), findsNothing);

        var tentativas = 0;
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(_app(AusenciaTela(
          carregar: () async => const CasoAusencia(status: 'em_analise'),
          profissional: false,
          carregarAnexos: () async {
            if (tentativas++ == 0) throw Exception('rede');
            return const [];
          },
        )));
        await t.pumpAndSettle();
        await _tocar(t, find.text('Tentar de novo'));
        await _ver(t, find.text('Nenhuma foto anexada.'));
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('"Abrir arquivo" usa o link; link vencido é buscado de novo', (t) async {
    await _janela(t, const Size(390, 1600), 1);
    final abertos = <String>[];
    final anterior = abrirLink;
    addTearDown(() => abrirLink = anterior);
    abrirLink = (u) async {
      abertos.add('$u');
      return true;
    };
    var leituras = 0;
    await t.pumpWidget(_app(AusenciaTela(
      carregar: () async => const CasoAusencia(status: 'em_analise'),
      profissional: false,
      carregarAnexos: () async {
        leituras++;
        return [
          AnexoAusencia(
            tipo: 'registro_ausencia',
            arquivoId: 'a1',
            url: 'arquivo://v$leituras',
            expiraEmSegundos: 20, // menor que a folga: já conta como vencido
          ),
        ];
      },
    )));
    await t.pumpAndSettle();
    await _tocar(t, find.byKey(const Key('abrir-anexo-a1')));
    expect(leituras, 2);
    expect(abertos, ['arquivo://v2']);
    expect(t.takeException(), isNull);
  });
}
