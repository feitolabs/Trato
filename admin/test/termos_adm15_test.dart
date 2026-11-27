import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder campo(String rotulo) =>
    find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> escrever(WidgetTester tester, String rotulo, String texto) async {
  await tester.ensureVisible(campo(rotulo));
  await tester.enterText(campo(rotulo), texto);
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'seguranca', double largura = 1400}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: largura < 700 ? null : 'incidentes', largura: largura);
  return fake;
}

final umaMedida = [
  MedidaIncidente(
      id: 'm1', tipo: 'preservar_registros', descricao: 'Registros guardados', origem: 'analista', aplicadaEm: DateTime(2026, 11, 20)),
];

void main() {
  test('permissões', () {
    Set<Papel> quem(Permissao p) => {for (final x in Papel.values) if (x.pode(p)) x};
    const trata = {Papel.mediador, Papel.liderSuporte, Papel.seguranca, Papel.administrador};
    expect(quem(Permissao.incidentesVer), trata);
    expect(quem(Permissao.incidentesTratar), trata);
    expect(quem(Permissao.incidentesEncerrar), {Papel.liderSuporte, Papel.seguranca, Papel.administrador});
  });

  testWidgets('cautela vencida é destacada; filtro de situação vai ao servidor', (tester) async {
    final api = await abrir(tester,
        api: ApiFake()..incidentes = [ApiFake.incidenteDeExemplo(cautelaAte: DateTime(2020), atrasada: true)]);
    expect(find.text('Cautela vencida'), findsWidgets);
    expect(find.textContaining('a cautela não foi adotada', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('incidente-situacao')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Em apuração').last);
    await tester.pumpAndSettle();
    expect(api.ultimoStatusIncidente, 'em_apuracao');
  });

  testWidgets('no prazo não há destaque', (tester) async {
    await abrir(tester);
    expect(find.text('Cautela vencida'), findsNothing);
  });

  testWidgets('vazio', (tester) async {
    await abrir(tester, api: ApiFake()..incidentes = []);
    expect(find.text('Nenhum incidente com esse filtro.'), findsOneWidget);
  });

  testWidgets('erro de carga', (tester) async {
    await abrir(tester, api: ApiFake(erro: true));
    expect(find.text('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('registrar: pessoa diferente exige pedido e só envia ao confirmar', (tester) async {
    final api = await abrir(tester);
    await tester.tap(find.text('Registrar incidente'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Outro')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pessoa diferente da verificada').last);
    await tester.pumpAndSettle();
    await escrever(tester, 'O que aconteceu', 'Chegou outra pessoa');
    await escrever(tester, 'Contato de quem relatou', '31 0000-0000');
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Confirmar registro'), findsNothing);
    expect(find.text('Pessoa diferente exige o pedido'), findsOneWidget);
    await escrever(tester, 'Código do pedido', 'ped-1');
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasIncidente, isEmpty);
    await clicar(tester, noModal('Confirmar registro'));
    expect(api.chamadasIncidente.single.$2, {
      'tipo': 'pessoa_diferente',
      'descricao': 'Chegou outra pessoa',
      'contato': '31 0000-0000',
      'canal': 'telefone',
      'pedido': 'ped-1',
    });
  });

  testWidgets('200 (toque repetido) avisa que nada novo foi criado', (tester) async {
    await abrir(tester, api: ApiFake()..incidenteRepetido = true);
    await tester.tap(find.text('Registrar incidente'));
    await tester.pumpAndSettle();
    await escrever(tester, 'O que aconteceu', 'Relato');
    await escrever(tester, 'Contato de quem relatou', '31 0000-0000');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar registro'));
    expect(find.textContaining('Nada novo foi criado'), findsOneWidget);
  });

  testWidgets('limites do servidor nos campos; a medida diz que só registra', (tester) async {
    await abrir(tester);
    int? limite(String rotulo) => tester.widget<TextField>(campo(rotulo)).maxLength;
    await tester.tap(find.text('Registrar incidente'));
    await tester.pumpAndSettle();
    expect((limite('O que aconteceu'), limite('Contato de quem relatou')), (4000, 320));
    await clicar(tester, noModal('Cancelar'));
    await tocar(tester, find.text('Adicionar medida'));
    expect(limite('O que foi feito'), 1000);
    expect(find.textContaining('Adia a exclusão de conta', findRichText: true), findsOneWidget);
    await clicar(tester, noModal('Cancelar'));
    await tocar(tester, find.text('Encerrar incidente'));
    expect(limite('Desfecho'), 4000);
  });

  testWidgets('cautela adotada fica desabilitada sem medida; suspender conta não é oferecida', (tester) async {
    final api = await abrir(tester);
    await rolarListaAte(tester, find.text('Marcar cautela adotada'));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Marcar cautela adotada')).onPressed, isNull);
    expect(find.textContaining('registre uma medida antes'), findsOneWidget);
    await tocar(tester, find.text('Adicionar medida'));
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Preservar os registros do pedido')));
    await tester.pumpAndSettle();
    expect(find.text('Suspender a conta'), findsNothing);
    await tester.tap(find.text('Reter o valor ainda não liberado').last);
    await tester.pumpAndSettle();
    await escrever(tester, 'O que foi feito', 'Valor segurado');
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasIncidente, isEmpty);
    await clicar(tester, noModal('Confirmar medida'));
    expect(api.chamadasIncidente.single.$2, {'tipo': 'reter_valor', 'descricao': 'Valor segurado'});
  });

  testWidgets('com medida, mudar situação pede confirmação', (tester) async {
    final api = ApiFake()..incidentes = [ApiFake.incidenteDeExemplo(medidas: umaMedida)];
    await abrir(tester, api: api);
    await tocar(tester, find.text('Marcar cautela adotada'));
    expect(api.chamadasIncidente, isEmpty);
    await clicar(tester, noModal('Mudar situação'));
    expect(api.chamadasIncidente.single.$2, {'status': 'cautela_adotada'});
  });

  testWidgets('encerrar: exige desfecho, avisa do dinheiro e confirma', (tester) async {
    final api = await abrir(tester);
    await tocar(tester, find.text('Encerrar incidente'));
    expect(find.textContaining('soltar a retenção do dinheiro', findRichText: true), findsOneWidget);
    await escrever(tester, 'Desfecho', 'curto');
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Encerrar incidente'), findsNothing);
    await escrever(tester, 'Desfecho', 'Objeto encontrado pela cliente');
    await clicar(tester, noModal('Revisar'));
    expect(find.textContaining('soltar a retenção do dinheiro', findRichText: true), findsOneWidget);
    expect(api.chamadasIncidente, isEmpty);
    await clicar(tester, noModal('Encerrar incidente'));
    expect(api.chamadasIncidente.single.$2, {'desfecho': 'Objeto encontrado pela cliente'});
  });

  testWidgets('erro do servidor fica no modal', (tester) async {
    await abrir(tester,
        api: ApiFake()..falhaIncidente = const ErroApi('Incidente já encerrado.', status: 409));
    await tocar(tester, find.text('Encerrar incidente'));
    await escrever(tester, 'Desfecho', 'Objeto encontrado pela cliente');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Encerrar incidente'));
    expect(find.textContaining('Incidente já encerrado.', findRichText: true), findsOneWidget);
  });

  testWidgets('mediador trata, mas não encerra; encerrado não tem ações', (tester) async {
    await abrir(tester, papel: 'mediador');
    await rolarListaAte(tester, find.text('Adicionar medida'));
    expect(find.text('Encerrar incidente'), findsNothing);
  });

  testWidgets('encerrado não tem ações', (tester) async {
    await abrir(tester, api: ApiFake()..incidentes = [ApiFake.incidenteDeExemplo(status: 'encerrado')]);
    await rolarListaAte(tester, find.textContaining('não recebe mudanças', findRichText: true));
    expect(find.text('Adicionar medida'), findsNothing);
    expect(find.text('Encerrar incidente'), findsNothing);
  });

  testWidgets('sem permissão não há seção', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2');
    expect(find.byKey(const ValueKey('menu-incidentes')), findsNothing);
  });

  test('API: rotas e corpos do contrato', () async {
    final pedidos = <http.Request>[];
    var statusDoRegistro = 201;
    (int, String)? recusa;
    const item = {
      'id': 'i1',
      'protocolo': 'P',
      'canal': 'app',
      'tipo': 'outro',
      'descricao': 'd',
      'status': 'aberto',
      'aberto_em': '2026-11-20T10:00:00Z',
      'cautela_ate': '2026-11-21T10:00:00Z',
      'medidas': [
        {'id': 'm', 'tipo': 'outro', 'descricao': 'x', 'origem': 'analista', 'aplicada_em': '2026-11-20T11:00:00Z'}
      ],
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"seguranca"}', 200);
        pedidos.add(r);
        final lista = r.method == 'GET' && r.url.path == '/v1/admin/incidentes';
        final novo = r.method == 'POST' && r.url.path == '/v1/admin/incidentes';
        if (r.headers['x-teste-falha'] == null && recusa != null) {
          return http.Response.bytes(utf8.encode(jsonEncode({'detail': recusa.$2})), recusa.$1);
        }
        return http.Response(
            jsonEncode(lista ? {'itens': [item], 'total': 1} : item), novo ? statusDoRegistro : 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    expect((await api.listarIncidentes(status: 'aberto', pedidoId: 'p1')).itens.single.medidas.single.id, 'm');
    expect(pedidos.last.url.queryParameters,
        {'status': 'aberto', 'pedido_id': 'p1', 'limite': '50', 'deslocamento': '0'});
    Future<void> confere(Future<Object?> chamada, String rota, Object? corpo) async {
      await chamada;
      expect('${pedidos.last.method} ${pedidos.last.url.path}', rota);
      if (corpo != null) expect(jsonDecode(pedidos.last.body), corpo);
    }

    await confere(api.obterIncidente('i1'), 'GET /v1/admin/incidentes/i1', null);
    Future<bool> repetido() async =>
        (await api.registrarIncidente(tipo: 'outro', descricao: 'd', contato: 'c', canal: 'email')).repetido;
    expect(await repetido(), isFalse); // 201
    statusDoRegistro = 200;
    expect(await repetido(), isTrue);
    await confere(api.registrarIncidente(tipo: 'outro', descricao: 'd', contato: 'c', canal: 'email'),
        'POST /v1/admin/incidentes', {'tipo': 'outro', 'descricao': 'd', 'contato': 'c', 'canal': 'email'});
    await confere(api.adicionarMedidaIncidente('i1', tipo: 'outro', descricao: 'x'),
        'POST /v1/admin/incidentes/i1/medidas', {'tipo': 'outro', 'descricao': 'x'});
    await confere(api.mudarStatusIncidente('i1', 'em_apuracao'), 'POST /v1/admin/incidentes/i1/status',
        {'status': 'em_apuracao'});
    await confere(api.encerrarIncidente('i1', desfecho: 'desfecho longo'), 'POST /v1/admin/incidentes/i1/encerrar',
        {'desfecho': 'desfecho longo'});

    for (final (status, texto) in [
      (409, 'Registre uma medida antes de marcar a cautela como adotada.'),
      (503, 'Incidentes indisponíveis: as tabelas ainda não existem no banco de dados.'),
    ]) {
      recusa = (status, texto);
      await expectLater(api.mudarStatusIncidente('i1', 'cautela_adotada'),
          throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', texto).having((e) => e.status, 'status', status)));
    }
  });
}
