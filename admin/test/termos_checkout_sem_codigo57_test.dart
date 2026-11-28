import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/checkout_sem_codigo_tela.dart';

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

Future<ApiFake> _abrir(WidgetTester tester, {ApiFake? api, String papel = 'mediador'}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'checkout_sem_codigo');
  return fake;
}

List<Map<String, Object?>> _chamadas(ApiFake api, String acao) =>
    [for (final c in api.chamadasCheckoutSemCodigo) if (c.$1 == acao) c.$2];

void main() {
  test('só mediador, líder de suporte e administrador têm a permissão', () {
    expect(
      {for (final p in Papel.values) if (p.pode(Permissao.checkoutSemCodigoTratar)) p},
      {Papel.mediador, Papel.liderSuporte, Papel.administrador},
    );
  });

  testWidgets('sem a permissão a seção não aparece nem carrega', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'financeiro', api: api);
    expect(find.byKey(const ValueKey('menu-checkout_sem_codigo')), findsNothing);
    expect(api.chamadasCheckoutSemCodigo, isEmpty);
  });

  testWidgets('lista casos destacando vencidos e sem contato, com ações de contato e decisão', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'checkout_sem_codigo', altura: 1600);
    expect(_contem(kAvisoCheckoutSemCodigo), findsOneWidget);
    expect(find.text('Prazo vencido'), findsOneWidget);
    expect(find.text('Sem contato'), findsOneWidget);
    expect(find.text('Aguardando resposta'), findsOneWidget);
    expect(_contem('ped-csc-1'), findsWidgets);
    expect(_contem('App + e-mail'), findsOneWidget);
    expect(_contem('25/11/2026 10:00 (horário de Brasília)'), findsOneWidget);
    expect(_contem('Inicia após o contato'), findsOneWidget);
    // Só o caso sem contato oferece "Registrar contato"; "Decidir caso" só fica habilitado para contatado + vencido.
    expect(find.text('Registrar contato'), findsOneWidget);
    final botoesDecidir = tester.widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Decidir caso')).toList();
    expect(botoesDecidir, hasLength(3));
    expect(botoesDecidir[0].onPressed, isNotNull); // vencido + contatado
    expect(botoesDecidir[1].onPressed, isNull); // sem contato
    expect(botoesDecidir[2].onPressed, isNull); // contatado, mas prazo não vencido
    expect(find.text('Registre o contato e aguarde o fim do prazo de resposta para decidir.'), findsOneWidget);
    expect(find.text('Aguarde o fim do prazo de resposta para decidir.'), findsOneWidget);
    expect(_chamadas(api, 'listar').last, {'deslocamento': 0, 'limite': 20});
  });

  testWidgets('estado vazio de carregamento', (tester) async {
    await _abrir(tester, api: ApiFake(vazio: true));
    expect(find.text('Nenhum caso de check-out sem código na fila.'), findsOneWidget);
  });

  testWidgets('estado de erro de carregamento', (tester) async {
    await _abrir(tester, api: ApiFake(erro: true));
    expect(_contem('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('pagina resultados quando há mais de 20 casos', (tester) async {
    final api = ApiFake()
      ..casosCheckoutSemCodigo = [
        for (var i = 1; i <= 25; i++)
          CasoCheckoutSemCodigo(
            id: 'csc-$i',
            pedidoId: 'ped-$i',
            clienteId: 'cli-$i',
            profissionalId: 'pro-$i',
            checkOutEm: DateTime.utc(2026, 11, 27, 12, i),
          ),
      ];
    await _abrir(tester, api: api);
    final rolagem = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).last;
    await tester.scrollUntilVisible(find.text('Carregar mais'), 800, scrollable: rolagem, maxScrolls: 40);
    await tester.pumpAndSettle();
    expect(find.text('Mostrando 20 de 25 casos'), findsOneWidget);
    await _clicar(tester, find.text('Carregar mais'));
    expect(_chamadas(api, 'listar').last, {'deslocamento': 20, 'limite': 20});
    await tester.scrollUntilVisible(find.text('Todos os 25 casos'), 800, scrollable: rolagem, maxScrolls: 40);
    await tester.pumpAndSettle();
    expect(find.text('Todos os 25 casos'), findsOneWidget);
  });

  testWidgets('registrar contato exige canal e motivo >= 10, trata 404/409/503 preservando motivo e confirma',
      (tester) async {
    final api = ApiFake()..falhaCheckoutSemCodigo = const ErroApi('Caso não encontrado.', status: 404);
    await _abrir(tester, api: api);
    await rolarListaAte(tester, find.text('Registrar contato'));
    await _clicar(tester, find.text('Registrar contato'));

    // Sem canal e motivo curto: não avança para revisão.
    await _escrever(tester, 'Motivo', 'curto');
    await _clicar(tester, _noModal('Revisar'));
    expect(_noModal('Confirmar registro'), findsNothing);

    await _clicar(tester, _noModal('WhatsApp'));
    const motivoValido = 'Tentativa de contato realizada pelo WhatsApp oficial.';
    await _escrever(tester, 'Motivo', motivoValido);
    await _clicar(tester, _noModal('Revisar'));
    expect(_chamadas(api, 'contato'), isEmpty);

    // 404: mostra aviso claro e preserva motivo.
    await _clicar(tester, _noModal('Confirmar registro'));
    expect(_contem('Caso não encontrado.'), findsOneWidget);
    expect(_contem('Atualize a fila'), findsOneWidget);
    expect(find.text(motivoValido), findsOneWidget);

    // 409: mostra aviso claro e preserva motivo.
    api.falhaCheckoutSemCodigo = const ErroApi('O contato deste caso já foi registrado.', status: 409);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar registro'));
    expect(_contem('O contato deste caso já foi registrado.'), findsOneWidget);
    expect(find.text(motivoValido), findsOneWidget);

    // 503: mostra aviso claro e preserva motivo.
    api.falhaCheckoutSemCodigo = const ErroApi('A fila do check-out sem código ainda não está disponível.', status: 503);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar registro'));
    expect(_contem('ainda não está disponível'), findsOneWidget);
    expect(_contem('Tente novamente'), findsOneWidget);
    expect(find.text(motivoValido), findsOneWidget);

    // Sucesso: envia e atualiza a fila.
    api.falhaCheckoutSemCodigo = null;
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar registro'));
    expect(_chamadas(api, 'contato').last, {
      'caso_id': 'csc-sem-contato',
      'canal': 'whatsapp',
      'motivo': motivoValido,
    });
    expect(find.text('Contato registrado.'), findsOneWidget);
    expect(find.text('Registrar contato'), findsNothing);
  });

  testWidgets('decidir caso gera nova chave após 403/404/409/422 preservando texto, e conclui ao confirmar',
      (tester) async {
    final api = ApiFake()
      ..falhaDecisaoCheckoutSemCodigo = const ErroApi('Valor acima da sua alçada.', status: 403);
    await _abrir(tester, api: api);
    await _clicar(tester, find.text('Decidir caso').first);

    // Sem decisão e motivo curto: não revisa.
    await _escrever(tester, 'Motivo', 'curto');
    await _clicar(tester, _noModal('Revisar'));
    expect(_noModal('Confirmar decisão'), findsNothing);

    await _clicar(tester, _noModal('Liberar pagamento'));
    const motivo = 'Serviço comprovado por fotos e cliente não respondeu no prazo.';
    await _escrever(tester, 'Motivo', motivo);
    await _clicar(tester, _noModal('Revisar'));
    expect(_chamadas(api, 'decisao'), isEmpty);

    // 403: erro definitivo, gera nova chave e preserva texto.
    await _clicar(tester, _noModal('Confirmar decisão'));
    expect(_contem('Valor acima da sua alçada.'), findsOneWidget);
    expect(find.text(motivo), findsOneWidget);
    final chave403 = _chamadas(api, 'decisao').last['chave_idempotencia'] as String;

    // 409: erro definitivo, usa chave nova diferente da anterior e preserva texto.
    api.falhaDecisaoCheckoutSemCodigo = const ErroApi('Disputa aberta impede decisão.', status: 409);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    expect(_contem('Disputa aberta impede decisão.'), findsOneWidget);
    expect(find.text(motivo), findsOneWidget);
    final chave409 = _chamadas(api, 'decisao').last['chave_idempotencia'] as String;
    expect(chave409, isNot(chave403));

    // 422: erro definitivo, usa chave nova e preserva texto.
    api.falhaDecisaoCheckoutSemCodigo = const ErroApi('Motivo inválido.', status: 422);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    expect(_contem('Motivo inválido.'), findsOneWidget);
    expect(find.text(motivo), findsOneWidget);
    final chave422 = _chamadas(api, 'decisao').last['chave_idempotencia'] as String;
    expect(chave422, isNot(chave409));

    // Sucesso: permite trocar para estornar (pois não travou), envia chave nova e remove caso da fila.
    api.falhaDecisaoCheckoutSemCodigo = null;
    await _clicar(tester, _noModal('Estornar ao cliente'));
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    final ultima = _chamadas(api, 'decisao').last;
    expect(ultima['caso_id'], 'csc-vencido');
    expect(ultima['decisao'], 'estornar');
    expect(ultima['motivo'], motivo);
    expect(ultima['chave_idempotencia'], isNot(chave422));
    expect(find.text('Decisão registrada: estorno ao cliente.'), findsOneWidget);
    expect(find.text('Decidir caso'), findsNWidgets(2));
  });

  testWidgets('decidir caso mantém mesma chave e trava decisão/motivo após 503 ou erro sem resposta',
      (tester) async {
    final api = ApiFake()
      ..falhaDecisaoCheckoutSemCodigo = const ErroApi('Serviço temporariamente indisponível.', status: 503);
    await _abrir(tester, api: api);
    await _clicar(tester, find.text('Decidir caso').first);
    await _clicar(tester, _noModal('Liberar pagamento'));
    const motivo = 'Prazo vencido após contato manual e comprovação da execução.';
    await _escrever(tester, 'Motivo', motivo);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));

    expect(_contem('Serviço temporariamente indisponível.'), findsOneWidget);
    expect(_contem('Decisão e motivo travados.'), findsOneWidget);
    expect(find.text(motivo), findsOneWidget);
    final chave1 = _chamadas(api, 'decisao').last['chave_idempotencia'] as String;

    // Tentar trocar decisão não muda nada porque está travado.
    await _clicar(tester, _noModal('Estornar ao cliente'));
    final campoMotivo = tester.widget<TextField>(
      find.descendant(of: _modal(), matching: find.widgetWithText(TextField, 'Motivo')),
    );
    expect(campoMotivo.readOnly, isTrue);

    // Fechar e reabrir o modal preserva a mesma chave, decisão e motivo travados.
    await _clicar(tester, _noModal('Cancelar'));
    await _clicar(tester, find.text('Decidir caso').first);
    expect(_contem('Decisão e motivo travados.'), findsOneWidget);
    expect(find.text(motivo), findsOneWidget);

    // Repetir com sucesso idempotente usa exatamente a mesma chave e decisão.
    api
      ..falhaDecisaoCheckoutSemCodigo = null
      ..decisaoCheckoutIdempotente = true;
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    final segunda = _chamadas(api, 'decisao').last;
    expect(segunda['chave_idempotencia'], chave1);
    expect(segunda['decisao'], 'liberar');
    expect(segunda['motivo'], motivo);
    expect(_contem('Essa decisão já estava registrada'), findsOneWidget);
  });

  test('auditoria descreve contato manual e decisão do check-out sem código', () {
    final contato = EntradaAuditoria(
      id: 1,
      ocorridaEm: DateTime.utc(2026, 11, 28, 3, 0),
      ator: 'mediador@trato.local',
      acao: 'checkout_sem_codigo.contato_manual',
      entidade: 'pedidos:ped-csc-2',
      entidadeNome: 'ped-csc-2',
      motivo: 'Contato feito por telefone com o cliente.',
      detalhes: const {'caso_id': 'csc-2', 'canal': 'telefone'},
    );
    expect(
      descreverAcao(contato),
      'registrou contato manual de check-out sem código no pedido ped-csc-2 (Telefone)',
    );
    expect(filtrosDeAcao.any((f) => f.$1 == 'checkout_sem_codigo.'), isTrue);

    final decisao = EntradaAuditoria(
      id: 2,
      ocorridaEm: DateTime.utc(2026, 11, 28, 4, 0),
      ator: 'lider@trato.local',
      acao: 'financeiro.checkout_sem_codigo_decidido',
      entidade: 'pedidos:ped-csc-1',
      entidadeNome: 'ped-csc-1',
      motivo: 'Prazo vencido e serviço comprovado.',
      detalhes: const {'caso_id': 'csc-1', 'decisao': 'liberar', 'estado': 'concluido'},
    );
    expect(
      descreverAcao(decisao),
      'decidiu o check-out sem código do pedido ped-csc-1 (Liberar pagamento)',
    );
  });

  test('API HTTP: rotas, payload exato e parse de contato e decisão', () async {
    final pedidos = <http.Request>[];
    var status = 200;
    final item = {
      'id': 'csc-1',
      'pedido_id': 'ped-1',
      'cliente_id': 'cli-1',
      'profissional_id': 'pro-1',
      'check_out_em': '2026-11-27T15:00:00+00:00',
      'contatado_em': '2026-11-27T16:00:00+00:00',
      'canal': 'email',
      'responder_ate': '2026-11-29T16:00:00+00:00',
      'vencido': false,
    };
    final decisaoOut = {
      'id': 'csc-1',
      'pedido_id': 'ped-1',
      'estado_pedido': 'concluido',
      'decisao': 'liberar',
      'analista_id': 'u',
      'justificativa': 'Serviço concluído e comprovado.',
      'decidido_em': '2026-11-28T04:00:00+00:00',
      'chave_idempotencia': 'csc-12345678',
      'idempotente': false,
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        if (status >= 400) {
          return http.Response.bytes(utf8.encode('{"detail":"Este caso não está mais aberto."}'), status);
        }
        final Object corpo = r.method == 'GET'
            ? {'itens': [item], 'total': 1, 'limite': 20, 'deslocamento': 0}
            : (r.url.path.endsWith('/decisao') ? decisaoOut : item);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status);
      }),
    );

    await api.entrar('m@teste.local', 'senha-de-teste');
    final pagina = await api.listarCheckoutSemCodigo(deslocamento: 0, limite: 20);
    expect(pedidos.last.url.path, '/v1/admin/checkout-sem-codigo');
    expect(pedidos.last.url.queryParameters, {'limite': '20', 'deslocamento': '0'});
    expect(pagina.total, 1);
    expect(pagina.itens.single.pedidoId, 'ped-1');

    await api.registrarContatoCheckoutSemCodigo(
      'csc-1',
      canal: 'email',
      motivo: 'Contato enviado para o e-mail cadastrado.',
    );
    expect(pedidos.last.url.path, '/v1/admin/checkout-sem-codigo/csc-1/contato');
    expect(jsonDecode(pedidos.last.body), {
      'canal': 'email',
      'motivo': 'Contato enviado para o e-mail cadastrado.',
    });

    final decidido = await api.decidirCheckoutSemCodigo(
      'csc-1',
      decisao: 'liberar',
      motivo: 'Serviço concluído e comprovado.',
      chaveIdempotencia: 'csc-12345678',
    );
    expect(pedidos.last.url.path, '/v1/admin/checkout-sem-codigo/csc-1/decisao');
    expect(jsonDecode(pedidos.last.body), {
      'decisao': 'liberar',
      'motivo': 'Serviço concluído e comprovado.',
      'chave_idempotencia': 'csc-12345678',
    });
    expect(decidido.estadoPedido, 'concluido');
    expect(decidido.decisao, 'liberar');
    expect(decidido.idempotente, isFalse);

    status = 409;
    await expectLater(
      api.decidirCheckoutSemCodigo(
        'csc-1',
        decisao: 'liberar',
        motivo: 'Serviço concluído e comprovado.',
        chaveIdempotencia: 'csc-12345678',
      ),
      throwsA(
        isA<ErroApi>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.mensagem, 'mensagem', 'Este caso não está mais aberto.'),
      ),
    );
  });
}
