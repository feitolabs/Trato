import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder campoNoModal(String rotulo) =>
    find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));

Future<void> escrever(WidgetTester tester, Finder campo, String texto) async {
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pump();
}

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'mediador'}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'medidas');
  return fake;
}

Future<void> preencherMedida(WidgetTester tester) async {
  await tester.tap(find.text('Aplicar medida'));
  await tester.pumpAndSettle();
  await escrever(tester, campoNoModal('Código da conta'), 'u-101');
  await escrever(tester, campoNoModal('Motivo (o usuário lê)'), 'Ofensa registrada na conversa');
  await escrever(tester, campoNoModal('Cláusulas dos Termos'), '9.2, 20.3');
  await escrever(tester, campoNoModal('Nota interna (opcional)'), 'Ver alerta antigo');
}

ContestacaoMedida contestacaoAberta() => ContestacaoMedida(
      status: 'aberta',
      versao: 'Não fui eu (exemplo)',
      canal: 'app',
      abertaEm: DateTime(2026, 11, 21),
      responderAte: DateTime(2026, 12, 5),
    );

Future<void> responder(WidgetTester tester, String decisao) async {
  await tocar(tester, find.text(decisao));
  final campo = find.widgetWithText(TextField, 'Resposta que o usuário vai ler');
  await rolarListaAte(tester, campo);
  await tester.enterText(campo, 'Analisamos a sua versão e as provas');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('aplicar: revisão separa o que o usuário lê do interno e só envia ao confirmar', (tester) async {
    final api = await abrir(tester);
    await preencherMedida(tester);
    await clicar(tester, noModal('Revisar medida'));
    expect(api.ultimaMedida, isNull);
    expect(noModal('O usuário vai ler'), findsOneWidget);
    expect(noModal('Só a equipe vê'), findsOneWidget);
    expect(noModal('Texto padrão do servidor'), findsNWidgets(2));
    await clicar(tester, noModal('Confirmar e aplicar'));
    final n = api.ultimaMedida!;
    expect((n.usuarioId, n.tipo, n.dias, n.detalheAdiado), ('u-101', 'aviso', null, false));
    expect(n.clausulas, ['9.2', '20.3']);
    expect((n.efeito, n.comoContestar, n.notaInterna), (null, null, 'Ver alerta antigo'));
    expect(find.textContaining('Medida aplicada. Protocolo MED-EXEMPLO-1'), findsOneWidget);
  });

  testWidgets('aplicar avisa que pedidos e valores pedem conferência manual (20.6)', (tester) async {
    final api = await abrir(tester);
    final aviso = find.descendant(
      of: find.byType(Dialog),
      matching: find.textContaining('não são tratados automaticamente', findRichText: true),
    );
    await preencherMedida(tester);
    expect(aviso, findsOneWidget);
    await clicar(tester, noModal('Revisar medida'));
    expect(aviso, findsOneWidget);
    expect(api.ultimaMedida, isNull);
  });

  testWidgets('adiar o detalhe exige justificativa e avisa que o texto não vai', (tester) async {
    final api = await abrir(tester);
    await preencherMedida(tester);
    await clicar(tester, noModal('Adiar o detalhe do motivo para o usuário'));
    await clicar(tester, noModal('Revisar medida'));
    expect(noModal('Confirmar e aplicar'), findsNothing);
    await escrever(tester, campoNoModal('Justificativa do adiamento (interna)'), 'Apuração em andamento');
    await clicar(tester, noModal('Revisar medida'));
    expect(find.textContaining('O seu texto não vai'), findsOneWidget);
    await clicar(tester, noModal('Confirmar e aplicar'));
    expect(api.ultimaMedida!.justificativaAdiamento, 'Apuração em andamento');
  });

  testWidgets('repetição em 5 minutos avisa que nada novo foi criado', (tester) async {
    await abrir(tester, api: ApiFake()..medidaRepetida = true);
    await preencherMedida(tester);
    await clicar(tester, noModal('Revisar medida'));
    await clicar(tester, noModal('Confirmar e aplicar'));
    expect(find.textContaining('Nada novo foi criado'), findsOneWidget);
  });

  testWidgets('503 mostra o texto do servidor e mantém o preenchimento', (tester) async {
    final api = ApiFake()
      ..falhaMedida = const ErroApi('A tabela de medidas ainda não está disponível.', status: 503, codigo: 'indisponivel');
    await abrir(tester, api: api);
    await preencherMedida(tester);
    await clicar(tester, noModal('Revisar medida'));
    await clicar(tester, noModal('Confirmar e aplicar'));
    expect(find.textContaining('A tabela de medidas ainda não está disponível.', findRichText: true), findsOneWidget);
    expect(noModal('Ofensa registrada na conversa'), findsOneWidget);
  });

  testWidgets('detalhe separa os blocos; reverter pede motivo e confirmação', (tester) async {
    final api = await abrir(tester);
    expect(find.text('O que o usuário lê'), findsOneWidget);
    await tocar(tester, find.text('Reverter medida'));
    expect(api.chamadasMedida, isEmpty);
    await confirmarMotivo(tester, 'Reverter medida', motivo: 'Aplicada por engano');
    expect(api.chamadasMedida.single.$2, {'motivo': 'Aplicada por engano'});
  });

  testWidgets('registrar contestação do atendimento', (tester) async {
    final api = await abrir(tester);
    await tocar(tester, find.text('Registrar contestação'));
    await escrever(tester, campoNoModal('Versão do usuário, nas palavras dele'), 'Disse que não foi ele');
    await clicar(tester, noModal('Registrar'));
    expect(api.chamadasMedida.single, isNotNull);
    expect(api.chamadasMedida.single.$2, {'versao': 'Disse que não foi ele', 'anexos': <String>[]});
  });

  testWidgets('decidir: encurtar exige dias e confirmação', (tester) async {
    final api = ApiFake()..medidas = [ApiFake.medidaDeExemplo(contestacao: contestacaoAberta())];
    await abrir(tester, api: api);
    await responder(tester, 'Encurtar');
    await tocar(tester, find.text('Revisar decisão'));
    expect(find.byType(Dialog), findsNothing);
    final dias = find.widgetWithText(TextField, 'Novo prazo (dias a partir de hoje)');
    await rolarListaAte(tester, find.text('Revisar decisão'));
    await tester.ensureVisible(dias);
    await tester.enterText(dias, '3');
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Revisar decisão'));
    expect(api.chamadasMedida, isEmpty);
    await clicar(tester, noModal('Enviar decisão'));
    expect(api.chamadasMedida.single.$2, {
      'resultado': 'alterada',
      'resposta': 'Analisamos a sua versão e as provas',
      'dias': 3,
      'justificativa': null,
    });
  });

  testWidgets('422 mesmo_analista faz aparecer a justificativa interna', (tester) async {
    final api = ApiFake()
      ..medidas = [ApiFake.medidaDeExemplo(contestacao: contestacaoAberta())]
      ..falhaMedida = const ErroApi('Você aplicou a medida: justifique.', status: 422, codigo: 'mesmo_analista');
    await abrir(tester, api: api);
    await responder(tester, 'Manter');
    await tocar(tester, find.text('Revisar decisão'));
    await clicar(tester, noModal('Enviar decisão'));
    final campo = find.widgetWithText(TextField, 'Por que você mesmo decide (só a equipe vê)');
    await rolarListaAte(tester, campo);
    api.falhaMedida = null;
    await tester.enterText(campo, 'Não há outro analista hoje');
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Revisar decisão'));
    await clicar(tester, noModal('Enviar decisão'));
    expect(api.chamadasMedida.last.$2['justificativa'], 'Não há outro analista hoje');
  });

  testWidgets('sem medidas_aplicar não há seção nem botão no usuário', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2', secao: 'busca');
    expect(find.byKey(const ValueKey('menu-medidas')), findsNothing);
    expect(find.text('Aplicar medida'), findsNothing);
  });

  testWidgets('bloquear pelo Risco pede texto ao usuário e cláusulas e envia os dois', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'seguranca', api: api, secao: 'risco');
    await tocar(tester, find.text('Bloquear conta'));
    await escrever(tester, campoNoModal('Motivo interno (o usuário não vê)'), 'Padrão de fraude no alerta');
    await clicar(tester, noModal('Bloquear conta'));
    expect(api.acoesDeConta, isEmpty); // falta o que o usuário lê
    await escrever(tester, campoNoModal('Motivo que o usuário vai ler'), 'Atividade fora do padrão na conta');
    await escrever(tester, campoNoModal('Cláusulas dos Termos'), '20.3');
    await clicar(tester, noModal('Bloquear conta'));
    expect(api.acoesDeConta.single.acao, 'aplicarBloqueioPreventivo');
    expect(api.acoesDeConta.single.motivoUsuario, 'Atividade fora do padrão na conta');
    expect(api.acoesDeConta.single.clausulas, ['20.3']);
  });

  test('API: ações antigas, medidas (201 e 200), recusa com código e exclusividades', () async {
    final pedidos = <http.Request>[];
    var status = 201;
    Object? corpoForcado;
    const medida = {
      'id': 'm1',
      'usuario_id': 'u1',
      'tipo': 'aviso',
      'motivo': 'm',
      'motivo_completo': 'm',
      'clausulas': ['9.2'],
      'inicio_em': '2026-11-25T10:00:00Z',
      'efeito_pedidos_valores': 'e',
      'como_contestar': 'c',
      'vigente': true,
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        final lista = r.method == 'GET';
        final corpo = corpoForcado ?? (lista ? {'itens': [], 'total': 0} : medida);
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), lista && corpoForcado == null ? 200 : status);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    Map<String, dynamic> enviado() => jsonDecode(pedidos.last.body) as Map<String, dynamic>;

    const nova = NovaMedida(usuarioId: 'u1', tipo: 'aviso', motivo: 'motivo longo', clausulas: ['9.2']);
    expect((await api.aplicarMedida(nova)).repetida, isFalse);
    expect(enviado(), {
      'usuario_id': 'u1',
      'tipo': 'aviso',
      'motivo': 'motivo longo',
      'clausulas': ['9.2'],
      'dias': null,
      'detalhe_adiado': false,
    });
    status = 200;
    expect((await api.aplicarMedida(nova)).repetida, isTrue);

    await api.decidirContestacaoMedida('m1', resultado: 'mantida', resposta: 'resposta longa');
    expect(pedidos.last.url.path, '/v1/admin/medidas/m1/contestacao/decisao');
    await api.listarMedidas(const FiltroMedidas(vigentes: true, contestacaoAberta: true));
    expect(pedidos.last.url.queryParameters,
        {'vigentes': 'true', 'contestacao_aberta': 'true', 'limite': '50', 'deslocamento': '0'});
    await api.listarExclusividades(pedidoId: 'p', status: 'ativa');
    expect(pedidos.last.url.path, '/v1/admin/exclusividades');
    expect(pedidos.last.url.queryParameters, {'pedido_id': 'p', 'status': 'ativa', 'limite': '20', 'deslocamento': '0'});

    corpoForcado = {'mensagem': 'ok'};
    expect(
        await api.travarSaque('u1', motivo: 'interno', motivoUsuario: 'para o usuário', clausulas: ['20.1']), 'ok');
    expect(enviado()['motivo_usuario'], 'para o usuário');
    expect(enviado()['clausulas'], ['20.1']);
    await api.destravarSaque('u1', motivo: 'interno');
    expect(enviado().containsKey('motivo_usuario'), isFalse);
    expect(enviado().containsKey('clausulas'), isFalse);
    await api.alterarStatusUsuario('u1', status: 'bloqueado', motivo: 'interno', motivoUsuario: 'texto', clausulas: ['9']);
    expect(enviado()['motivo_usuario'], 'texto');
    await api.aplicarBloqueioPreventivo('u1', motivo: 'interno', motivoUsuario: 'texto', clausulas: ['9']);
    expect(enviado()['clausulas'], ['9']);

    status = 422;
    corpoForcado = {'detail': 'Você aplicou a medida.', 'codigo': 'mesmo_analista'};
    await expectLater(
      api.decidirContestacaoMedida('m1', resultado: 'mantida', resposta: 'resposta longa'),
      throwsA(isA<ErroApi>()
          .having((e) => e.codigo, 'codigo', 'mesmo_analista')
          .having((e) => e.mensagem, 'mensagem', 'Você aplicou a medida.')),
    );
  });
}
