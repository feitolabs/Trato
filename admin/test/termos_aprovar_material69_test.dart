import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';
import 'package:trato_admin/telas/materiais_contestacao_modais.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 6.9: aprovação financeira por segunda pessoa, antes de executar o estorno.
const botao = 'Aprovar efeito financeiro';
const motivo = 'Análise conferida por segunda pessoa.';

/// No computador o modal é uma janela; no celular, uma folha que sobe de baixo.
Finder modal() => find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet).last;
Finder noModal(String texto) => find.descendant(of: modal(), matching: find.text(texto));
Finder contem(String texto) => find.textContaining(texto, findRichText: true);

List<ContestacaoMaterial> _itens({String status = 'parcial', String efeito = 'nenhum'}) => [
      ApiFake.contestacaoMaterialDeExemplo(status: status, valorReconhecidoCentavos: 5000, efeitoFinanceiro: efeito),
    ];

/// Segura a resposta para dar tempo de tocar de novo.
class _ApiLenta extends ApiFake {
  final liberar = Completer<void>();

  @override
  Future<ContestacaoMaterial> aprovarFinanceiroContestacaoMaterial(String contestacaoId,
      {required String motivo}) async {
    final r = super.aprovarFinanceiroContestacaoMaterial(contestacaoId, motivo: motivo);
    await liberar.future;
    return r;
  }
}

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _abrirTela(WidgetTester tester, ApiFake api, {String papel = 'lider_suporte', double largura = 1400}) async {
  await abrirPainel(tester, papel: papel, api: api, largura: largura);
  if (largura < 600) {
    await tester.tap(find.byKey(const ValueKey('menu-mais')));
    await tester.pumpAndSettle();
    await tocarNoMais(tester, 'materiais');
    await tester.tap(find.textContaining('MAT-2026-0001').first);
    await tester.pumpAndSettle();
  } else {
    await irPara(tester, 'materiais');
  }
}

Future<void> _abrirModal(WidgetTester tester) async {
  await rolarListaAte(tester, find.text(botao));
  await clicar(tester, find.text(botao));
}

Future<void> _escrever(WidgetTester tester, String texto) async {
  final campo = find.descendant(of: modal(), matching: find.byType(TextField));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Future<void> _revisar(WidgetTester tester) async {
  await _escrever(tester, motivo);
  await clicar(tester, noModal('Revisar'));
}

void main() {
  for (final papel in ['mediador', 'seguranca']) {
    testWidgets('$papel não vê o botão', (tester) async {
      await _abrirTela(tester, ApiFake()..contestacoesMaterial = _itens(), papel: papel);
      await rolarListaAte(tester, contem('a decisão não pode ser mudada'));
      expect(find.text(botao), findsNothing);
    });
  }

  for (final (status, efeito) in [
    ('improcedente', 'nenhum'),
    ('parcial', 'pendente_financeiro'),
    ('parcial', 'executado'),
  ]) {
    testWidgets('sem botão para $status com efeito $efeito', (tester) async {
      await _abrirTela(tester, ApiFake()..contestacoesMaterial = _itens(status: status, efeito: efeito));
      await rolarListaAte(tester, contem('a decisão não pode ser mudada'));
      expect(find.text(botao), findsNothing);
    });
  }

  for (final largura in [360.0, 1400.0]) {
    testWidgets('confirma antes de enviar em ${largura.toInt()} px', (tester) async {
      final api = ApiFake()..contestacoesMaterial = _itens(status: 'procedente');
      await _abrirTela(tester, api, largura: largura);
      await _abrirModal(tester);
      expect(find.descendant(of: modal(), matching: contem(kSegundaPessoaMaterial)), findsOneWidget);
      expect(find.descendant(of: modal(), matching: contem(r'R$ 50,00')), findsOneWidget);
      await _escrever(tester, 'curto');
      await clicar(tester, noModal('Revisar'));
      expect(noModal('Confirmar aprovação'), findsNothing);
      await _revisar(tester);
      expect(api.chamadasMaterial, isEmpty);
      await clicar(tester, noModal('Confirmar aprovação'));
      expect(api.chamadasMaterial.single.$1, 'aprovar-financeiro');
      expect(api.chamadasMaterial.single.$2, {'id': 'cm-1', 'motivo': motivo});
      expect(find.text('Confirmar aprovação'), findsNothing);
      expect(contem('Falta executar o estorno'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('depois de aprovar, a fila relida mostra Executar estorno', (tester) async {
    final api = ApiFake()..contestacoesMaterial = _itens();
    await _abrirTela(tester, api);
    await _abrirModal(tester);
    await _revisar(tester);
    api.contestacoesMaterial = _itens(efeito: 'pendente_financeiro');
    await clicar(tester, noModal('Confirmar aprovação'));
    await rolarListaAte(tester, find.text('Executar estorno'));
    expect(find.text('Executar estorno'), findsOneWidget);
    expect(find.text(botao), findsNothing);
  });

  for (final status in [403, 404, 409, 422, 503, null]) {
    testWidgets('erro ${status ?? 'sem resposta'} aparece e preserva o motivo', (tester) async {
      final api = ApiFake()
        ..contestacoesMaterial = _itens()
        ..falhaMaterial = ErroApi('Recusa de exemplo.', status: status);
      await _abrirTela(tester, api);
      await _abrirModal(tester);
      await _revisar(tester);
      await clicar(tester, noModal('Confirmar aprovação'));
      expect(contem('Recusa de exemplo.'), findsOneWidget);
      expect(contem(kRepetirAprovacaoMaterial), status == null ? findsOneWidget : findsNothing);
      expect(find.text(motivo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('toque duplo envia uma vez só', (tester) async {
    final api = _ApiLenta()..contestacoesMaterial = _itens();
    await _abrirTela(tester, api);
    await _abrirModal(tester);
    await _revisar(tester);
    final alvo = noModal('Confirmar aprovação');
    await tester.ensureVisible(alvo);
    await tester.pump();
    final onde = tester.getCenter(alvo);
    await tester.tapAt(onde);
    await tester.tapAt(onde);
    await tester.pump();
    await tester.tapAt(onde);
    expect(api.chamadasMaterial, hasLength(1));
    api.liberar.complete();
    await tester.pumpAndSettle();
    expect(api.chamadasMaterial, hasLength(1));
  });

  test('API: rota, corpo e recusa do servidor', () async {
    final pedidos = <http.Request>[];
    var recusar = false;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"lider_suporte"}', 200);
        pedidos.add(r);
        if (recusar) {
          return http.Response.bytes(utf8.encode('{"detail":"Exige segunda pessoa."}'), 403);
        }
        return http.Response(
            jsonEncode({
              'id': 'cm-1',
              'protocolo': 'MAT-1',
              'pedido_id': 'p1',
              'nota_id': 'n1',
              'cliente_id': 'c1',
              'motivo': 'nao_comprovado',
              'valor_contestado_centavos': 9000,
              'aberta_em': '2026-11-20T10:00:00Z',
              'responder_ate': '2026-11-27T10:00:00Z',
              'status': 'parcial',
              'efeito_financeiro': 'pendente_financeiro',
            }),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final r = await api.aprovarFinanceiroContestacaoMaterial('cm-1', motivo: motivo);
    expect(pedidos.single.method, 'POST');
    expect(pedidos.single.url.path, '/v1/admin/materiais/contestacoes/cm-1/aprovar-financeiro');
    expect(jsonDecode(pedidos.single.body), {'motivo': motivo});
    expect(r.efeitoFinanceiro, 'pendente_financeiro');
    recusar = true;
    await expectLater(
      api.aprovarFinanceiroContestacaoMaterial('cm-1', motivo: motivo),
      throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Exige segunda pessoa.')),
    );
  });

  test('auditoria tem texto próprio', () {
    final entrada = EntradaAuditoria(
        id: 1,
        ocorridaEm: DateTime(2026, 11, 28),
        ator: 'u1',
        acao: 'material.contestacao_financeiro_aprovado',
        entidade: 'nota_material_contestacoes:cm-1',
        motivo: motivo);
    expect(descreverAcao(entrada), 'aprovou o efeito financeiro de uma contestação de material');
  });
}
