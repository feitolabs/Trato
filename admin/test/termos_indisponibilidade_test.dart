import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/indisponibilidades_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Finder _modal() => find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet);

Finder _noModal(String texto) => find.descendant(of: _modal(), matching: find.text(texto));

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _escrever(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.descendant(of: _modal(), matching: find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pump();
}

Future<ApiFake> _abrir(WidgetTester tester, {ApiFake? api, String papel = 'lider_suporte'}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'indisponibilidades');
  return fake;
}

List<Map<String, Object?>> _chamadas(ApiFake api, String acao) =>
    [for (final c in api.chamadasIndisponibilidade) if (c.$1 == acao) c.$2];

void main() {
  test('só líder de suporte e administrador têm a permissão', () {
    expect({for (final p in Papel.values) if (p.pode(Permissao.indisponibilidadesGerenciar)) p},
        {Papel.liderSuporte, Papel.administrador});
  });

  testWidgets('sem a permissão a seção não aparece nem carrega', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'financeiro', api: api);
    expect(find.byKey(const ValueKey('menu-indisponibilidades')), findsNothing);
    expect(api.chamadasIndisponibilidade, isEmpty);
  });

  test('data e hora de Brasília: estrita e com fuso', () {
    expect(lerDataHoraDeBrasilia('27/11/2026 14:30'), '2026-11-27T14:30:00-03:00');
    for (final ruim in ['', '31/02/2026 10:00', '27/11/2026 24:00', '27/11/2026', '27/11/26 10:00']) {
      expect(lerDataHoraDeBrasilia(ruim), isNull, reason: ruim);
    }
  });

  test('aviso do alcance: o que a falha prorroga, o que não muda e o que não é citado', () {
    for (final trecho in [
      'justificativa', 'orçamento', 'congelamento do repasse', 'avaliação', 'contestação de medida', 'exclusividade',
      'reserva de Tratinhos do Pix', 'visita recorrente', 'QR do Pix', 'avisos já enviados', 'já venceu',
      'a de pagamento, só a expiração de pagamento, o orçamento, a reserva do Pix e a visita recorrente',
    ]) {
      expect(kAlcanceDaProrrogacao, contains(trecho));
    }
    expect(kAlcanceDaProrrogacao, contains('expiração do pedido sem orçamento'));
    expect(kRiscoDaFalhaAberta, contains('Encerre assim que'));
  });

  testWidgets('lista em horário de Brasília, com o aviso e os filtros', (tester) async {
    final api = await _abrir(tester);
    expect(_contem(kAlcanceDaProrrogacao), findsOneWidget);
    expect(_contem(kRiscoDaFalhaAberta), findsOneWidget);
    expect(_contem('27/11/2026 14:30 (horário de Brasília)'), findsOneWidget);
    expect(find.text('Ativa'), findsOneWidget);
    await _clicar(tester, find.text('Aplicativo'));
    expect(find.text('Nenhuma falha com esse filtro.'), findsOneWidget);
    await _clicar(tester, find.text('Só abertas'));
    final ultima = _chamadas(api, 'listar').last;
    expect((ultima['origem'], ultima['abertas'], ultima['limite']), ('app', true, 20));
  });

  testWidgets('erro de carga aparece com tentar de novo', (tester) async {
    await _abrir(tester, api: ApiFake(erro: true));
    expect(_contem('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('registrar exige motivo, revisa antes e mantém o modal na recusa', (tester) async {
    final api = ApiFake()
      ..falhaIndisponibilidade = const ErroApi('Já existe uma janela desta origem nesse período.', status: 409);
    await _abrir(tester, api: api);
    await _clicar(tester, find.text('Registrar falha'));
    await _clicar(tester, _noModal('Pagamento'));
    await _escrever(tester, 'Início da falha', '27/11/2026 14:30');
    await _escrever(tester, 'Motivo', 'curto');
    await _clicar(tester, _noModal('Revisar'));
    expect(_noModal('Confirmar registro'), findsNothing);
    await _escrever(tester, 'Motivo', 'Provedor fora do ar');
    await _clicar(tester, _noModal('Revisar'));
    expect(_chamadas(api, 'registrar'), isEmpty);
    await _clicar(tester, _noModal('Confirmar registro'));
    expect(_contem('Já existe uma janela desta origem'), findsOneWidget);
    expect(find.text('Provedor fora do ar'), findsOneWidget);

    api.falhaIndisponibilidade = null;
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar registro'));
    expect(_chamadas(api, 'registrar').last, {
      'origem': 'pagamento',
      'inicio_em': '2026-11-27T14:30:00-03:00',
      'fim_em': null,
      'motivo': 'Provedor fora do ar',
    });
    expect(find.text('Falha registrada.'), findsOneWidget);
    expect(find.text('Confirmar registro'), findsNothing);
  });

  testWidgets('registro repetido avisa que nada novo foi criado', (tester) async {
    await _abrir(tester, api: ApiFake()..indisponibilidadeRepetida = true);
    await _clicar(tester, find.text('Registrar falha'));
    await _clicar(tester, _noModal('Aplicativo'));
    await _escrever(tester, 'Início da falha', '27/11/2026 10:00');
    await _escrever(tester, 'Motivo', 'Aplicativo não abria');
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar registro'));
    expect(_contem('Nada novo foi criado'), findsOneWidget);
  });

  testWidgets('encerrar no celular: fim vazio vai nulo e só depois de confirmar', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'lider_suporte', api: api, largura: 360, altura: 740);
    await tester.tap(find.byKey(const ValueKey('menu-mais')));
    await tester.pumpAndSettle();
    await tocarNoMais(tester, 'indisponibilidades');
    await rolarListaAte(tester, find.text('Encerrar falha'));
    await _clicar(tester, find.text('Encerrar falha'));
    await _escrever(tester, 'Motivo', 'Provedor voltou ao normal');
    await _clicar(tester, _noModal('Revisar'));
    expect(_noModal('Agora'), findsOneWidget);
    expect(find.descendant(of: _modal(), matching: _contem(kRiscoDaFalhaAberta)), findsOneWidget);
    expect(_chamadas(api, 'encerrar'), isEmpty);
    await _clicar(tester, _noModal('Confirmar encerramento'));
    expect(_chamadas(api, 'encerrar').single,
        {'id': 'jan-1', 'fim_em': null, 'motivo': 'Provedor voltou ao normal'});
    expect(tester.takeException(), isNull);
  });

  test('API: rotas, corpo, 200 como repetição e erro do servidor', () async {
    final pedidos = <http.Request>[];
    var status = 201;
    final item = {
      'id': 'j1',
      'origem': 'app',
      'inicio_em': '2026-11-27T17:30:00+00:00',
      'fim_em': null,
      'ativa': true,
      'motivo': 'motivo de teste',
      'criada_por': 'op',
      'encerrada_por': null,
      'criada_em': '2026-11-27T17:31:00+00:00',
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
        pedidos.add(r);
        if (status >= 400) return http.Response.bytes(utf8.encode('{"detail":"Sem a tabela."}'), status);
        final corpo = r.method == 'GET' ? {'itens': [item], 'total': 1} : item;
        return http.Response(jsonEncode(corpo), status);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final novo = await api.registrarIndisponibilidade(
        origem: 'app', inicioEm: '2026-11-27T14:30:00-03:00', motivo: 'motivo de teste');
    expect(novo.repetida, isFalse);
    expect(jsonDecode(pedidos.last.body), {
      'origem': 'app',
      'inicio_em': '2026-11-27T14:30:00-03:00',
      'fim_em': null,
      'motivo': 'motivo de teste',
    });
    status = 200;
    expect(
        (await api.registrarIndisponibilidade(origem: 'app', inicioEm: 'x', motivo: 'motivo de teste')).repetida,
        isTrue);
    final pagina = await api.listarIndisponibilidades(abertas: true);
    expect(pagina.total, 1);
    expect(pagina.itens.single.inicioEm.toUtc(), DateTime.utc(2026, 11, 27, 17, 30));
    expect(pedidos.last.url.queryParameters, {'abertas': 'true', 'limite': '20', 'deslocamento': '0'});
    await api.encerrarIndisponibilidade('j1', motivo: 'motivo de teste');
    expect(pedidos.last.url.path, '/v1/admin/indisponibilidades/j1/encerrar');
    expect(jsonDecode(pedidos.last.body), {'motivo': 'motivo de teste', 'fim_em': null});
    status = 503;
    await expectLater(api.listarIndisponibilidades(),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Sem a tabela.')));
  });
}
