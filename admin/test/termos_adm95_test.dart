import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/incidentes_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 9.5 e 9.6: cautela atrasada, efeito real das medidas e o que o encerramento libera.
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);
Finder _noDialogo(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Incidente _inc({String tipo = 'pessoa_diferente', String? pedido = 'ped-1', List<String> medidas = const []}) =>
    Incidente(
      id: 'inc-9',
      protocolo: 'INC-EXEMPLO-9',
      canal: 'telefone',
      tipo: tipo,
      descricao: 'Exemplo',
      status: 'aberto',
      pedidoId: pedido,
      abertoEm: DateTime(2026, 11, 20),
      cautelaAte: DateTime(2099),
      medidas: [
        for (final m in medidas)
          MedidaIncidente(id: m, tipo: m, descricao: 'Exemplo', origem: 'analista', aplicadaEm: DateTime(2026, 11, 20)),
      ],
    );

Future<ApiFake> _abrirMedida(WidgetTester tester, Incidente i, {ApiFake? api}) async {
  final fake = (api ?? ApiFake())..incidentes = [i];
  await abrirPainel(tester, papel: 'seguranca', api: fake, secao: 'incidentes', largura: 1400);
  await rolarListaAte(tester, find.text('Adicionar medida'));
  await _clicar(tester, find.text('Adicionar medida'));
  return fake;
}

Future<void> _escolher(WidgetTester tester, String rotulo) async {
  await _clicar(tester, _noDialogo(find.byType(DropdownButtonFormField<String>)));
  await tester.tap(find.text(rotulo).last);
  await tester.pumpAndSettle();
}

Future<void> _revisar(WidgetTester tester) async {
  await tester.enterText(_noDialogo(find.widgetWithText(TextField, 'O que foi feito')), 'Conferido com o cliente');
  await tester.pumpAndSettle();
  await _clicar(tester, _noDialogo(find.text('Revisar')));
}

void main() {
  testWidgets('pessoa diferente: cancelar avisa, pede confirmação e mostra o 409', (tester) async {
    const recusa = 'O serviço já começou (exemplo).';
    final api = ApiFake()..falhaIncidente = const ErroApi(recusa, status: 409);
    await _abrirMedida(tester, _inc(), api: api);
    await _escolher(tester, 'Cancelar o pedido com reembolso');
    expect(_contem('CANCELA o pedido de verdade'), findsOneWidget);
    await _revisar(tester);
    expect(_noDialogo(find.text('Cancelar o pedido com reembolso integral?')), findsOneWidget);
    expect(_contem('Não dá para desfazer'), findsOneWidget);
    expect(api.chamadasIncidente, isEmpty);
    await _clicar(tester, _noDialogo(find.text('Cancelar e reembolsar')));
    expect(api.chamadasIncidente.single.$2['tipo'], 'cancelar_pedido_reembolso');
    expect(_noDialogo(_contem(recusa)), findsOneWidget);
    expect(find.textContaining('Medida registrada'), findsNothing);
  });

  testWidgets('outro tipo de incidente: cancelar só registra', (tester) async {
    await _abrirMedida(tester, _inc(tipo: 'furto_roubo'));
    await _escolher(tester, 'Cancelar o pedido com reembolso');
    expect(_contem('Só registra: o sistema não cancela'), findsOneWidget);
    expect(_contem('CANCELA o pedido de verdade'), findsNothing);
    await _revisar(tester);
    expect(_noDialogo(find.text('Confirmar medida')), findsOneWidget);
    expect(_noDialogo(find.text('Cancelar e reembolsar')), findsNothing);
  });

  test('textos do efeito por medida', () {
    final i = _inc();
    expect(efeitoDaMedida(i, 'bloquear_contato'), contains('Não esconde telefone nem endereço'));
    expect(efeitoDaMedida(i, 'preservar_registros'), contains('Adia a exclusão de conta'));
    expect(efeitoDaMedida(i, 'reter_valor'), startsWith('Só registra'));
    expect(efeitoDaMedida(_inc(pedido: null), 'bloquear_contato'), contains('só registra'));
    expect(medidaCancelaDeVerdade(_inc(pedido: null), 'cancelar_pedido_reembolso'), isFalse);
    expect(liberadoAoEncerrar(_inc(medidas: ['reter_valor'])), isNull);
    expect(liberadoAoEncerrar(_inc(pedido: null, medidas: ['bloquear_contato'])), isNull);
  });

  testWidgets('encerrar avisa o que libera, também na confirmação', (tester) async {
    final api = ApiFake()..incidentes = [_inc(medidas: ['bloquear_contato', 'preservar_registros'])];
    await abrirPainel(tester, papel: 'seguranca', api: api, secao: 'incidentes', largura: 1400);
    await rolarListaAte(tester, find.text('Encerrar incidente'));
    await _clicar(tester, find.text('Encerrar incidente'));
    expect(_contem('o contato entre as partes volta a ser permitido'), findsOneWidget);
    expect(_contem('deixam de ser adiadas'), findsOneWidget);
    await tester.enterText(_noDialogo(find.widgetWithText(TextField, 'Desfecho')), 'Apuração concluída no exemplo');
    await tester.pumpAndSettle();
    await _clicar(tester, _noDialogo(find.text('Revisar')));
    expect(_contem('o contato entre as partes volta a ser permitido'), findsOneWidget);
  });

  testWidgets('sem cautela_atrasada nada é destacado, mesmo com prazo antigo', (tester) async {
    await abrirPainel(tester,
        papel: 'seguranca',
        api: ApiFake()..incidentes = [ApiFake.incidenteDeExemplo(cautelaAte: DateTime(2020))],
        secao: 'incidentes');
    expect(find.text('Cautela vencida'), findsNothing);
  });

  test('API: cautela_atrasada (ausente = falso) e a ação nova do histórico em português', () async {
    Object? atrasada = true;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"seguranca"}', 200);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'id': 'i1',
              'protocolo': 'P',
              'canal': 'app',
              'tipo': 'outro',
              'status': 'aberto',
              'aberto_em': '2026-11-20T10:00:00Z',
              'cautela_ate': '2026-11-21T10:00:00Z',
              'cautela_atrasada': ?atrasada,
            })),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    expect((await api.obterIncidente('i1')).cautelaAtrasada, isTrue);
    atrasada = null;
    expect((await api.obterIncidente('i1')).cautelaAtrasada, isFalse);
  });
}
