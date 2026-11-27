import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/componentes/base.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/escopo.dart';
import 'package:trato_admin/telas/provas_modal.dart';
import 'package:trato_admin/telas/seletor_arquivo.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const motivo = 'Conferir os custos informados';

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder campoNoModal(String rotulo) =>
    find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> escrever(WidgetTester tester, Finder campo, String texto) async {
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pump();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

/// Troca o seletor de arquivo do navegador por um arquivo de teste.
void escolher(String nome, String tipo, {int tamanho = 3}) {
  final original = seletorDeArquivo;
  seletorDeArquivo = (_, _) async => (nome: nome, tipo: tipo, tamanho: tamanho, bytes: [1, 2, 3]);
  addTearDown(() => seletorDeArquivo = original);
}

Future<ApiFake> abrirComprovantesDaTela(WidgetTester tester, {ApiFake? api}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: 'mediador', api: fake, secao: 'ausencias');
  await tester.tap(find.text('PED-AUSANALI').first);
  await tester.pumpAndSettle();
  await tocar(tester, find.text('Recusar'));
  final valor = find.widgetWithText(TextField, 'Retenção por custos comprovados (opcional)');
  await rolarListaAte(tester, valor);
  await tester.enterText(valor, '10,00');
  await tester.pumpAndSettle();
  await tocar(tester, find.text('Escolher comprovantes'));
  return fake;
}

Future<ApiFake> abrirRegistro(WidgetTester tester, {ApiFake? api}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: 'mediador', api: fake, secao: 'medidas');
  await tocar(tester, find.text('Registrar contestação'));
  return fake;
}

void main() {
  testWidgets('comprovantes: nada carrega sem motivo e não há campo de código', (tester) async {
    final api = await abrirComprovantesDaTela(tester);
    expect(api.chamadasArquivo, isEmpty);
    await clicar(tester, noModal('Listar arquivos do pedido'));
    expect(api.chamadasArquivo, isEmpty);
    await escrever(tester, campoNoModal('Motivo do acesso'), motivo);
    await clicar(tester, noModal('Listar arquivos do pedido'));
    expect(api.chamadasArquivo.single.$2['motivo'], motivo);
    expect(find.textContaining('pelo profissional'), findsOneWidget);
    expect(find.textContaining('um por linha'), findsNothing);
  });

  testWidgets('enviar novo: pedir, PUT e concluir nessa ordem, já marcado', (tester) async {
    escolher('nota.jpg', 'image/jpeg');
    final api = await abrirComprovantesDaTela(tester);
    await escrever(tester, campoNoModal('Motivo do acesso'), motivo);
    await clicar(tester, noModal('Enviar foto nova'));
    expect([for (final c in api.chamadasArquivo) c.$1], ['pedir', 'put', 'concluir']);
    expect(api.chamadasArquivo[2].$2, {'envio': 'envio-1', 'motivo': motivo});
    expect(noModal('Escolhidos: 1 de 10'), findsOneWidget);
    await clicar(tester, noModal('Usar escolhidos'));
    await rolarListaAte(tester, find.textContaining('• foto enviada'));
    expect(find.textContaining('pela equipe'), findsOneWidget);
  });

  testWidgets('PDF não serve de comprovante: nada é enviado', (tester) async {
    escolher('nota.pdf', 'application/pdf');
    final api = await abrirComprovantesDaTela(tester);
    await escrever(tester, campoNoModal('Motivo do acesso'), motivo);
    await clicar(tester, noModal('Enviar foto nova'));
    expect(api.chamadasArquivo, isEmpty);
    expect(find.textContaining('não é aceito', findRichText: true), findsOneWidget);
  });

  testWidgets('falha ao concluir permite concluir de novo sem reenviar', (tester) async {
    escolher('nota.jpg', 'image/jpeg');
    final api = ApiFake()..falhaConcluir = const ErroApi('O arquivo não foi enviado.', status: 409);
    await abrirComprovantesDaTela(tester, api: api);
    await escrever(tester, campoNoModal('Motivo do acesso'), motivo);
    await clicar(tester, noModal('Enviar foto nova'));
    expect(find.textContaining('O arquivo não foi enviado.', findRichText: true), findsOneWidget);
    api.falhaConcluir = null;
    await clicar(tester, noModal('Concluir envio'));
    expect([for (final c in api.chamadasArquivo) c.$1], ['pedir', 'put', 'concluir', 'concluir']);
    expect(noModal('Concluir envio'), findsNothing);
  });

  testWidgets('comprovantes: link abre, vence em 300 s e some se a sessão cair', (tester) async {
    final abertas = <String>[];
    final original = abridorDeProva;
    abridorDeProva = (u) {
      abertas.add(u);
      return true;
    };
    addTearDown(() => abridorDeProva = original);
    await abrirComprovantesDaTela(tester);
    await escrever(tester, campoNoModal('Motivo do acesso'), motivo);
    await clicar(tester, noModal('Listar arquivos do pedido'));
    await clicar(tester, noModal('Abrir'));
    expect(abertas, ['https://exemplo.supabase.co/ver/comp-1']);
    await tester.pump(const Duration(seconds: 301));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsNothing);
    expect(find.textContaining('links venceram', findRichText: true), findsOneWidget);
    tester.element(find.byType(CorpoModal)).sessao.saiu();
    await tester.pumpAndSettle();
    expect(find.byType(CorpoModal), findsNothing);
  });

  testWidgets('contestação por atendimento envia o anexo e manda o id', (tester) async {
    escolher('prova.pdf', 'application/pdf');
    final api = await abrirRegistro(tester);
    await clicar(tester, noModal('Anexar arquivo'));
    expect([for (final c in api.chamadasArquivo) c.$1], ['pedirAnexo', 'put']);
    expect(find.textContaining('prova.pdf'), findsOneWidget);
    await escrever(tester, campoNoModal('Versão do usuário, nas palavras dele'), 'Não fui eu');
    await clicar(tester, noModal('Registrar'));
    expect(api.chamadasMedida.single.$2, {'versao': 'Não fui eu', 'anexos': ['anexo-1.pdf']});
  });

  testWidgets('anexo acima de 10 MB e PUT que falha não entram na lista', (tester) async {
    escolher('grande.pdf', 'application/pdf', tamanho: 11 * 1024 * 1024);
    final api = await abrirRegistro(tester);
    await clicar(tester, noModal('Anexar arquivo'));
    expect(api.chamadasArquivo, isEmpty);
    expect(find.textContaining('passa de 10 MB', findRichText: true), findsOneWidget);

    escolher('prova.png', 'image/png');
    api.falhaEnvio = const ErroApi('O envio do arquivo foi recusado (400). Tente de novo.');
    await clicar(tester, noModal('Anexar arquivo'));
    expect(find.textContaining('foi recusado', findRichText: true), findsOneWidget);
    expect(find.textContaining('prova.png'), findsNothing);
  });

  testWidgets('provas da contestação: motivo antes, link curto; nomes dos analistas', (tester) async {
    final api = ApiFake();
    api.medidas = [
      Medida(
        id: 'med-1',
        usuarioId: 'u-1',
        tipo: 'aviso',
        motivoAoUsuario: 'm',
        motivoCompleto: 'm',
        clausulas: const ['9.2'],
        inicioEm: DateTime(2026, 11, 20),
        efeito: 'e',
        comoContestar: 'c',
        vigente: true,
        aplicadaPorNome: 'Dora (exemplo)',
        contestacaoAnalistaNome: 'Eli (exemplo)',
        contestacao: ContestacaoMedida(
          status: 'mantida',
          versao: 'v',
          canal: 'sac',
          abertaEm: DateTime(2026, 11, 21),
          responderAte: DateTime(2026, 12, 5),
          anexos: const [AnexoContestacao(anexoId: 'a.pdf', tipoConteudo: 'application/pdf', tamanhoBytes: 5000)],
        ),
      )
    ];
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
    expect(find.text('Dora (exemplo)'), findsOneWidget);
    await rolarListaAte(tester, find.text('Eli (exemplo)'));
    await tocar(tester, find.text('Abrir provas'));
    expect(api.chamadasArquivo, isEmpty);
    await escrever(tester, campoNoModal('Motivo do acesso'), motivo);
    await clicar(tester, noModal('Ver provas do caso'));
    expect(api.chamadasArquivo.single, isNotNull);
    expect(api.chamadasArquivo.single.$2, {'medida': 'med-1', 'motivo': motivo});
    expect(noModal('Prova 1 · PDF · 5 KB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 301));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsNothing);
  });

  group('API', () {
    final pedidos = <http.Request>[];
    var statusDoPut = 200;
    Future<ApiAdminHttp> criar() async {
      pedidos.clear();
      const arquivo = {
        'arquivo_id': 'f1',
        'finalidade': 'disputa',
        'enviado_por': 'equipe',
        'content_type': 'image/png',
        'tamanho_bytes': 10,
        'enviado_em': '2026-11-25T10:00:00Z',
        'url': 'https://x.supabase.co/v',
        'expira_em_segundos': 300,
      };
      final api = ApiAdminHttp(
        urlApi: 'http://api.teste',
        urlSupabase: 'http://supa.teste',
        chaveAnonSupabase: 'anon',
        cliente: MockClient((r) async {
          if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
          if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
          pedidos.add(r);
          if (r.method == 'PUT') return http.Response('', statusDoPut);
          final p = r.url.path;
          final Object corpo = p.endsWith('/arquivos')
              ? [arquivo]
              : p.endsWith('/envio')
                  ? {'envio_id': 'e1', 'url': 'https://x.supabase.co/put', 'expira_em_segundos': 300}
                  : p.endsWith('/concluir')
                      ? arquivo
                      : p.endsWith('/abrir')
                          ? [
                              {'anexo_id': 'a.pdf', 'content_type': 'application/pdf', 'tamanho_bytes': 1}
                            ]
                          : p.endsWith('/contestacao/anexos')
                              ? {'anexo_id': 'a.pdf', 'url': 'https://x.supabase.co/put', 'expira_em_segundos': 300}
                              : {
                                  'id': 'c1',
                                  'protocolo': 'P',
                                  'assunto': 'a',
                                  'status': 'aberto',
                                  'aberto_em': '2026-11-25T10:00:00Z',
                                  'categoria': 'contestacao',
                                  'canal': 'app',
                                  'responder_ate': '2026-12-01T10:00:00Z',
                                  'responsavel_nome': 'Carla',
                                  'contestacao_retencao': true,
                                  'usuario_id': 'u1',
                                  'tipo': 'aviso',
                                  'motivo': 'm',
                                  'motivo_completo': 'm',
                                  'clausulas': ['1'],
                                  'inicio_em': '2026-11-25T10:00:00Z',
                                  'efeito_pedidos_valores': 'e',
                                  'como_contestar': 'c',
                                  'aplicada_por_nome': 'Dora',
                                  'contestacao_analista_nome': 'Eli',
                                  'contestacao': {
                                    'status': 'aberta',
                                    'versao': 'v',
                                    'canal': 'sac',
                                    'aberta_em': '2026-11-25T10:00:00Z',
                                    'responder_ate': '2026-12-01T10:00:00Z',
                                    'anexos': [
                                      {'anexo_id': 'a.pdf', 'content_type': 'application/pdf', 'tamanho_bytes': 7}
                                    ],
                                  },
                                };
          return http.Response(jsonEncode(corpo), 200);
        }),
      );
      await api.entrar('a@teste.local', 'senha-de-teste');
      return api;
    }

    test('comprovantes: rotas, motivo sempre no corpo e nada na URL', () async {
      final api = await criar();
      await api.listarComprovantes('p1', motivo: motivo);
      await api.pedirEnvioComprovante('p1',
          motivo: motivo, nomeArquivo: 'n.png', tipoConteudo: 'image/png', tamanhoBytes: 10);
      await api.concluirComprovante('p1', 'e1', motivo: motivo);
      expect([for (final r in pedidos) '${r.method} ${r.url.path}'], [
        'POST /v1/admin/ausencias/p1/arquivos',
        'POST /v1/admin/ausencias/p1/arquivos/envio',
        'POST /v1/admin/ausencias/p1/arquivos/envio/e1/concluir',
      ]);
      for (final r in pedidos) {
        expect(r.url.hasQuery, isFalse);
        expect(jsonDecode(r.body)['motivo'], motivo);
      }
      expect(jsonDecode(pedidos[1].body),
          {'motivo': motivo, 'nome_arquivo': 'n.png', 'content_type': 'image/png', 'tamanho_bytes': 10});
    });

    test('PUT vai ao link sem o token de login; http e recusa não passam', () async {
      final api = await criar();
      await api.enviarArquivo('https://x.supabase.co/put', tipoConteudo: 'image/png', bytes: [1, 2]);
      final put = pedidos.single;
      expect(put.method, 'PUT');
      expect(put.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(put.headers['Content-Type'], 'image/png');
      expect(put.bodyBytes, [1, 2]);
      await expectLater(api.enviarArquivo('http://x.supabase.co/put', tipoConteudo: 'image/png', bytes: [1]),
          throwsA(isA<ErroApi>()));
      expect(pedidos.length, 1);
      statusDoPut = 400;
      await expectLater(api.enviarArquivo('https://x.supabase.co/put', tipoConteudo: 'image/png', bytes: [1]),
          throwsA(isA<ErroApi>()));
      statusDoPut = 200;
    });

    test('anexos da contestação e campos novos', () async {
      final api = await criar();
      await api.pedirAnexoContestacao('m1', nomeArquivo: 'p.pdf', tipoConteudo: 'application/pdf', tamanhoBytes: 7);
      expect(jsonDecode(pedidos.last.body),
          {'nome_arquivo': 'p.pdf', 'content_type': 'application/pdf', 'tamanho_bytes': 7});
      final medida = await api.registrarContestacaoMedida('m1', versao: 'v', anexos: ['a.pdf']);
      expect(jsonDecode(pedidos.last.body), {'versao': 'v', 'anexos': ['a.pdf']});
      expect(medida.aplicadaPorNome, 'Dora');
      expect(medida.contestacaoAnalistaNome, 'Eli');
      expect(medida.contestacao!.anexos.single.tamanhoBytes, 7);
      await api.abrirAnexosContestacao('m1', motivo: motivo);
      expect(pedidos.last.url.path, '/v1/admin/medidas/m1/contestacao/anexos/abrir');
      expect(pedidos.last.url.hasQuery, isFalse);
      expect(jsonDecode(pedidos.last.body), {'motivo': motivo});
      final chamado = await api.obterChamado('c1');
      expect(chamado.responsavelNome, 'Carla');
      expect(chamado.contestacaoRetencao, isTrue);
    });
  });
}
