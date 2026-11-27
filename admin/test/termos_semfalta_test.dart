import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/medidas_modais.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 13.10 (encerramento sem falta) e 3.7 (sem serviço remoto).
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

Future<ApiFake> _preencherEncerramento(WidgetTester tester, {ApiFake? api}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: 'mediador', api: fake, secao: 'medidas');
  await tester.tap(find.text('Aplicar medida'));
  await tester.pumpAndSettle();
  await _escrever(tester, 'Código da conta', 'u-101');
  await _clicar(tester, find.byType(DropdownButtonFormField<String>));
  await tester.tap(find.text('Encerramento').last);
  await tester.pumpAndSettle();
  await _escrever(tester, 'Motivo (o usuário lê)', 'Encerramento do serviço na região');
  await _escrever(tester, 'Cláusulas dos Termos', '20.8');
  return fake;
}

Medida _encerramento(bool? semFalta) => Medida(
      id: 'med-e',
      usuarioId: 'u-101',
      tipo: 'encerramento',
      motivoAoUsuario: 'Texto (exemplo)',
      motivoCompleto: 'Texto (exemplo)',
      clausulas: const ['20.8'],
      inicioEm: DateTime(2026, 11, 20),
      efeito: 'Efeito (exemplo)',
      comoContestar: 'Como contestar (exemplo)',
      vigente: true,
      semFalta: semFalta,
    );

class _ApiRemoto extends ApiFake {
  bool? remotoEnviado = false;
  var editou = false;

  @override
  Future<List<CategoriaAdmin>> listarCategorias() async => const [
        CategoriaAdmin(id: 'c1', nome: 'Design', slug: 'design', ativa: true, profissionais: 1, aceitaRemoto: true),
      ];

  @override
  Future<CategoriaAdmin> editarCategoria(String id,
      {String? nome,
      String? slug,
      String? icone,
      int? garantiaDias,
      int? ordem,
      bool? ativa,
      bool? aceitaRemoto,
      required String motivo}) async {
    editou = true;
    remotoEnviado = aceitaRemoto;
    return (await listarCategorias()).first;
  }
}

void main() {
  for (final (rotulo, valor) in const [('Sim, sem falta', true), ('Não, por falta', false)]) {
    testWidgets('encerramento exige a escolha e envia sem_falta=$valor', (tester) async {
      final api = await _preencherEncerramento(tester);
      for (final chip in tester.widgetList<ChoiceChip>(_noDialogo(find.byType(ChoiceChip)))) {
        expect(chip.selected, isFalse);
      }
      await _clicar(tester, _noDialogo(find.text('Revisar medida')));
      expect(_noDialogo(find.text('Confirmar e aplicar')), findsNothing);
      await _clicar(tester, _noDialogo(find.text(rotulo)));
      await _clicar(tester, _noDialogo(find.text('Revisar medida')));
      expect(_contem(kSemFaltaDefinitivo), valor ? findsNothing : findsOneWidget);
      expect(_contem(kEfeitoSemFalta), valor ? findsOneWidget : findsNothing);
      expect(api.ultimaMedida, isNull);
      await _clicar(tester, _noDialogo(find.text('Confirmar e aplicar')));
      expect(api.ultimaMedida!.semFalta, valor);
    });
  }

  testWidgets('422 sem_falta_invalida aparece no modal', (tester) async {
    const erro = 'Infração grave não é encerramento sem falta.';
    final api = ApiFake()..falhaMedida = const ErroApi(erro, status: 422, codigo: 'sem_falta_invalida');
    await _preencherEncerramento(tester, api: api);
    await _clicar(tester, _noDialogo(find.text('Sim, sem falta')));
    await _clicar(tester, _noDialogo(find.text('Infração grave (Termos 20.9)')));
    await _clicar(tester, _noDialogo(find.text('Revisar medida')));
    await _clicar(tester, _noDialogo(find.text('Confirmar e aplicar')));
    expect((api.ultimaMedida!.semFalta, api.ultimaMedida!.infracaoGrave), (true, true));
    expect(_noDialogo(_contem(erro)), findsOneWidget);
  });

  testWidgets('outros tipos não perguntam sem falta', (tester) async {
    await abrirPainel(tester, papel: 'mediador', secao: 'medidas');
    await tester.tap(find.text('Aplicar medida'));
    await tester.pumpAndSettle();
    expect(_contem('Foi sem falta do usuário?'), findsNothing);
  });

  for (final (valor, texto) in <(bool?, String)>[
    (true, 'guardados por 90 dias'),
    (false, 'Não'),
    (null, 'Não informado'),
  ]) {
    testWidgets('detalhe mostra sem_falta=$valor', (tester) async {
      await abrirPainel(tester, papel: 'mediador', api: ApiFake()..medidas = [_encerramento(valor)], secao: 'medidas');
      await rolarListaAte(tester, find.text('Sem falta do usuário'));
      expect(find.textContaining(texto), findsWidgets);
    });
  }

  testWidgets('categoria com remoto gravado: opção desativada e salvar não envia o campo', (tester) async {
    final api = _ApiRemoto();
    await abrirPainel(tester, papel: 'moderador', api: api, secao: 'busca');
    await tester.tap(find.text('Categorias'));
    await tester.pumpAndSettle();
    expect(find.text('Remoto marcado'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar Design'));
    await tester.pumpAndSettle();
    final chave = tester.widget<SwitchListTile>(find.byKey(const ValueKey('aceita-remoto')));
    expect((chave.value, chave.onChanged), (true, null));
    await _escrever(tester, 'Motivo', 'Ajuste de garantia');
    await _clicar(tester, _noDialogo(find.text('Salvar categoria')));
    expect((api.editou, api.remotoEnviado), (true, null));
  });

  test('API: sem_falta só vai quando escolhido e é lido da resposta', () async {
    final pedidos = <http.Request>[];
    Object? devolvido = false;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'id': 'm1',
              'usuario_id': 'u1',
              'tipo': 'encerramento',
              'motivo': 'm',
              'motivo_completo': 'm',
              'clausulas': ['20.8'],
              'inicio_em': '2026-11-25T10:00:00Z',
              'efeito_pedidos_valores': 'e',
              'como_contestar': 'c',
              'vigente': true,
              'sem_falta': devolvido,
            })),
            201);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    Map<String, dynamic> enviado() => jsonDecode(pedidos.last.body) as Map<String, dynamic>;
    NovaMedida nova(bool? v) => NovaMedida(
        usuarioId: 'u1', tipo: 'encerramento', motivo: 'motivo longo', clausulas: const ['20.8'], semFalta: v);

    expect((await api.aplicarMedida(nova(false))).medida.semFalta, isFalse);
    expect(enviado()['sem_falta'], false);
    devolvido = null;
    expect((await api.aplicarMedida(nova(null))).medida.semFalta, isNull);
    expect(enviado().containsKey('sem_falta'), isFalse);
  });
}
