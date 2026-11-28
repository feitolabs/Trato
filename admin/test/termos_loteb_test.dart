import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/componentes/base.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/avisos_previos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 11.8 (aviso ao autor), 23.2 (mudança dos Termos) e 4.9 (conta sem uso).
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);
Finder _noDialogo(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _escrever(WidgetTester tester, String rotulo, String texto) async {
  final campo = _noDialogo(find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Future<void> _ocultar(WidgetTester tester, ApiFake api, {String? adiar}) async {
  await abrirPainel(tester, papel: 'mediador', api: api, secao: 'avaliacoes');
  await _clicar(tester, find.text('Ocultar avaliação'));
  await _escrever(tester, 'Código da avaliação', 'aval-1');
  await _escrever(tester, 'Explicação', 'Texto com ofensa direta');
  if (adiar != null) {
    await _clicar(tester, _noDialogo(find.text('Adiar o aviso ao autor')));
    await _escrever(tester, 'Justificativa do adiamento (auditoria)', adiar);
  }
  await _clicar(tester, _noDialogo(find.text('Revisar')));
}

Future<void> _escolherData(WidgetTester tester) async {
  await _clicar(tester, _noDialogo(find.byType(CampoData)));
  await _clicar(tester, find.text('OK'));
}

ApiAdminHttp _api(List<(String, Map<String, dynamic>)> chamadas) => ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"moderador"}', 200);
        chamadas.add((r.url.path, r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>));
        final corpo = r.url.path.endsWith('avisos-previos')
            ? {'antecedencia_minima_dias': 30, 'destinatarios': 1, 'avisos_novos': 1, 'falhas': 0}
            : {
                'id': 'o1',
                'avaliacao_id': 'a1',
                'motivo': 'ofensa_ou_ilegal',
                'explicacao': 'e',
                'analista_id': 'u',
                'ocultada_em': '2026-11-27T12:00:00Z',
                'status_anterior': 'publicada',
              };
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200);
      }),
    );

void main() {
  testWidgets('ocultar: o padrão é avisar', (tester) async {
    final api = ApiFake();
    await _ocultar(tester, api);
    expect(_noDialogo(_contem('Enviado agora')), findsOneWidget);
    await _clicar(tester, _noDialogo(find.text('Confirmar ocultação')));
    expect(api.chamadasAvaliacao.single.$1, 'ocultar');
    expect(api.ultimoAdiamento, isNull);
  });

  testWidgets('ocultar: adiar exige justificativa de 10 caracteres', (tester) async {
    final api = ApiFake();
    await _ocultar(tester, api, adiar: 'curta');
    expect(_noDialogo(find.text('Confirmar ocultação')), findsNothing);
    await _escrever(tester, 'Justificativa do adiamento (auditoria)', 'Há investigação em andamento');
    await _clicar(tester, _noDialogo(find.text('Revisar')));
    await _clicar(tester, _noDialogo(find.text('Confirmar ocultação')));
    expect(api.ultimoAdiamento, 'Há investigação em andamento');
    expect(_contem('O aviso ao autor foi adiado'), findsOneWidget);
  });

  testWidgets('decidir revisão que oculta oferece o adiamento', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'avaliacoes');
    await _clicar(tester, find.text(api.revisoesAvaliacao.first.protocolo).first);
    await rolarListaAte(tester, find.text('Decidir revisão'));
    await _clicar(tester, find.text('Decidir revisão'));
    await _escrever(tester, 'Resposta', 'Pedido procede, texto ofensivo');
    await _clicar(tester, _noDialogo(find.text('Adiar o aviso ao autor')));
    await _escrever(tester, 'Justificativa do adiamento (auditoria)', 'Há risco para uma pessoa');
    await _clicar(tester, _noDialogo(find.text('Revisar')));
    await _clicar(tester, _noDialogo(find.text('Confirmar decisão')));
    expect(api.ultimoAdiamento, 'Há risco para uma pessoa');
  });

  testWidgets('avisar o autor: confirma e mostra o erro do servidor', (tester) async {
    final api = ApiFake()..falhaAvaliacao = const ErroApi('Esta avaliação não tem ocultação ativa.', status: 409);
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'avaliacoes');
    await _clicar(tester, find.text('Avisar o autor'));
    await _escrever(tester, 'Código da avaliação', 'aval-9');
    await _clicar(tester, _noDialogo(find.text('Revisar')));
    expect(api.chamadasAvaliacao, isEmpty);
    await _clicar(tester, _noDialogo(find.text('Enviar aviso')));
    expect(_noDialogo(_contem('não tem ocultação ativa')), findsOneWidget);
  });

  testWidgets('aviso dos Termos: link https, confirmação e repetir com falhas', (tester) async {
    final api = ApiFake()..falhasDoAviso = [2];
    await abrirPainel(tester, papel: 'moderador', api: api, secao: 'notificacoes');
    await rolarListaAte(tester, find.text('Aviso de mudança dos Termos'));
    await _clicar(tester, find.text('Aviso de mudança dos Termos'));
    await _escrever(tester, 'Referência do aviso', 'termos-2');
    await _escolherData(tester);
    await _escrever(tester, 'Resumo que o usuário vai ler', 'Muda a regra de ausências');
    await _escrever(tester, 'Motivo da mudança (o usuário lê)', 'Adequação das regras');
    await _escrever(tester, 'Link da versão completa', 'http://exemplo.test/termos');
    await _clicar(tester, _noDialogo(find.text('Revisar aviso')));
    expect(_noDialogo(find.text('Enviar aos usuários')), findsNothing);
    await _escrever(tester, 'Link da versão completa', 'https://exemplo.test/termos');
    await _clicar(tester, _noDialogo(find.text('Revisar aviso')));
    expect(api.outrosAvisosPrevios, isEmpty);
    await _clicar(tester, _noDialogo(find.text('Enviar aos usuários')));
    expect(_noDialogo(_contem('O aviso não vale')), findsOneWidget);
    await _clicar(tester, _noDialogo(find.text('Repetir envio')));
    expect(_noDialogo(_contem('Aviso enviado')), findsOneWidget);
    expect(api.outrosAvisosPrevios.length, 2);
    expect(api.outrosAvisosPrevios.last['link'], 'https://exemplo.test/termos');
  });

  testWidgets('aviso de conta sem uso não promete inativar', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'moderador', api: api, secao: 'notificacoes');
    await rolarListaAte(tester, find.text('Aviso de conta sem uso'));
    await _clicar(tester, find.text('Aviso de conta sem uso'));
    expect(_noDialogo(_contem(kInatividadeSoAvisa)), findsOneWidget);
    await _escrever(tester, 'Código da conta', 'u-101');
    await _escrever(tester, 'Referência do aviso', 'inativa-1');
    await _escolherData(tester);
    await _clicar(tester, _noDialogo(find.text('Revisar aviso')));
    expect(_noDialogo(_contem(kInatividadeSoAvisa)), findsOneWidget);
    await _clicar(tester, _noDialogo(find.text('Enviar ao usuário')));
    expect(api.outrosAvisosPrevios.single['usuario_id'], 'u-101');
    expect(_noDialogo(_contem(kInatividadeSoAvisa)), findsOneWidget);
  });

  test('API: campos enviados em cada rota', () async {
    final chamadas = <(String, Map<String, dynamic>)>[];
    final api = _api(chamadas);
    await api.entrar('a@teste.local', 'senha-de-teste');
    await api.ocultarAvaliacao('a1', motivo: 'ofensa_ou_ilegal', explicacao: 'explicação longa');
    await api.ocultarAvaliacao('a1',
        motivo: 'ofensa_ou_ilegal', explicacao: 'explicação longa', justificativaAdiamento: 'justificativa longa');
    await api.avisarAutorAvaliacao('a1');
    await api.enviarAvisoInatividade(usuarioId: 'u1', referencia: 'r1', vigencia: DateTime(2027, 1, 5));
    await api.enviarAvisoTermos(
        referencia: 'r2', vigencia: DateTime(2027, 1, 5), resumo: 'resumo', motivo: 'motivo', link: 'https://x.test');
    expect(chamadas[0].$2.containsKey('adiar_aviso'), isFalse);
    expect(chamadas[1].$2['adiar_aviso'], isTrue);
    expect(chamadas[1].$2['justificativa_adiamento'], 'justificativa longa');
    expect(chamadas[2].$1, '/v1/admin/avaliacoes/a1/avisar-autor');
    expect(chamadas[3].$2, {'tipo': 'inatividade', 'referencia': 'r1', 'vigencia': '2027-01-05', 'usuario_id': 'u1'});
    expect(chamadas[4].$2['tipo'], 'termos');
    expect(chamadas[4].$2['link'], 'https://x.test');
  });
}
