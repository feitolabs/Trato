import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/campos_trava.dart';
import 'package:trato_admin/telas/medidas_modais.dart';
import 'package:trato_admin/telas/medidas_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 20.8: encerramento sem falta fica agendado.
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
  await tester.pump();
}

Medida _encerramento({bool vigente = false, DateTime? revertida, DateTime? inicio}) => Medida(
      id: 'med-a',
      protocolo: 'MED-EXEMPLO-A',
      usuarioId: 'u-101',
      tipo: 'encerramento',
      motivoAoUsuario: 'Texto (exemplo)',
      motivoCompleto: 'Texto (exemplo)',
      clausulas: const ['20.8'],
      avisadoEm: DateTime.utc(2026, 11, 27, 12),
      inicioEm: inicio ?? DateTime.utc(2026, 12, 28, 2, 30),
      efeito: 'Efeito (exemplo)',
      comoContestar: 'Como contestar (exemplo)',
      vigente: vigente,
      revertidaEm: revertida,
      semFalta: true,
    );

const _inicioEmBrasilia = '27/12/2026 23:30 (horário de Brasília)';

Future<void> _aplicarSemFalta(WidgetTester tester, ApiFake api) async {
  await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
  await tester.tap(find.text('Aplicar medida'));
  await tester.pumpAndSettle();
  await _escrever(tester, 'Código da conta', 'u-101');
  await _clicar(tester, find.byType(DropdownButtonFormField<String>));
  await tester.tap(find.text('Encerramento').last);
  await tester.pumpAndSettle();
  await _escrever(tester, 'Motivo (o usuário lê)', 'Encerramento do serviço na região');
  await _escrever(tester, 'Cláusulas dos Termos', '20.8');
  await _clicar(tester, _noDialogo(find.text('Sim, sem falta')));
  await _clicar(tester, _noDialogo(find.text('Revisar medida')));
}

void main() {
  test('situação da medida', () {
    expect(chipDaMedida(_encerramento()).$1, 'Agendado');
    expect(chipDaMedida(_encerramento(vigente: true)).$1, 'Em vigor');
    expect(chipDaMedida(_encerramento(revertida: DateTime(2026, 11, 28))).$1, 'Revertida');
    // Começou no próprio aviso: não é agendada.
    expect(_encerramento(inicio: DateTime.utc(2026, 11, 27, 12)).agendada, isFalse);
  });

  testWidgets('confirmação diz que não vale na hora; sucesso mostra a data', (tester) async {
    final api = ApiFake()..medidas = [_encerramento()];
    await _aplicarSemFalta(tester, api);
    expect(_noDialogo(_contem(kSemFaltaAgendado)), findsWidgets);
    expect(_noDialogo(_contem('A conta muda na hora')), findsNothing);
    expect(api.ultimaMedida, isNull);
    await _clicar(tester, _noDialogo(find.text('Confirmar e aplicar')));
    expect(_contem('Encerramento agendado para $_inicioEmBrasilia'), findsOneWidget);
  });

  testWidgets('se o servidor não agendar, não diz que a conta segue ativa', (tester) async {
    final api = ApiFake()..medidas = [_encerramento(vigente: true)];
    await _aplicarSemFalta(tester, api);
    await _clicar(tester, _noDialogo(find.text('Confirmar e aplicar')));
    expect(_contem('não confirmou o agendamento'), findsOneWidget);
    expect(_contem('A conta segue ativa até lá'), findsNothing);
  });

  testWidgets('lista e detalhe mostram Agendado; reverter cancela o agendamento', (tester) async {
    final api = ApiFake()..medidas = [_encerramento()];
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
    expect(find.text('Agendado'), findsWidgets);
    expect(find.text('Encerrada'), findsNothing);
    expect(_contem('Começa em $_inicioEmBrasilia'), findsWidgets);
    expect(_contem('não cancela'), findsOneWidget);
    await rolarListaAte(tester, find.text('Reverter medida'));
    await _clicar(tester, find.text('Reverter medida'));
    expect(_noDialogo(_contem('Cancela o encerramento agendado')), findsOneWidget);
    await confirmarMotivo(tester, 'Reverter medida', motivo: 'Decisão revista');
    expect(api.chamadasMedida.single.$1, 'reverter');
  });

  testWidgets('risco avisa que as ações são imediatas', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'risco');
    await tester.tap(find.textContaining(RegExp(r'^Todos \d+$')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Troca de chave PIX').first);
    await tester.pumpAndSettle();
    await rolarListaAte(tester, _contem(kAcoesImediatas));
    expect(_contem(kAcoesImediatas), findsOneWidget);
  });

  testWidgets('alterar status avisa que não cancela o agendado', (tester) async {
    await abrirPainel(tester, papel: 'administrador', secao: 'busca');
    await tester.tap(find.text('Alterar status').first);
    await tester.pumpAndSettle();
    expect(_noDialogo(_contem(kAcoesImediatas)), findsOneWidget);
  });

  test('API lê avisado_em e reconhece o agendado', () async {
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'id': 'm1',
              'usuario_id': 'u1',
              'tipo': 'encerramento',
              'motivo': 'm',
              'motivo_completo': 'm',
              'clausulas': ['20.8'],
              'avisado_em': '2026-11-27T12:00:00Z',
              'inicio_em': '2026-12-28T02:30:00Z',
              'efeito_pedidos_valores': 'e',
              'como_contestar': 'c',
              'vigente': false,
              'sem_falta': true,
            })),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    expect((await api.obterMedida('m1')).agendada, isTrue);
  });
}
