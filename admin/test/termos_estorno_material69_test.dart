import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/materiais_contestacao_estorno.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 6.9: executar o estorno de material contestado já aprovado.
/// No computador o modal é uma janela; no celular, uma folha que sobe de baixo.
Finder modal() => find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet).last;
Finder noModal(String texto) => find.descendant(of: modal(), matching: find.text(texto));
Finder contem(String texto) => find.textContaining(texto, findRichText: true);

const motivo = 'Nota conferida e estorno aprovado.';

ApiFake _fake({String efeito = 'pendente_financeiro', String status = 'parcial'}) => ApiFake()
  ..contestacoesMaterial = [
    ApiFake.contestacaoMaterialDeExemplo(status: status, valorReconhecidoCentavos: 5000, efeitoFinanceiro: efeito),
  ];

/// Segura a resposta para dar tempo de tocar de novo.
class _ApiLenta extends ApiFake {
  final liberar = Completer<void>();

  @override
  Future<EstornoMaterial> executarEstornoMaterial(String contestacaoId,
      {required String motivo, required bool materialPagoNoApp}) async {
    final r = super.executarEstornoMaterial(contestacaoId, motivo: motivo, materialPagoNoApp: materialPagoNoApp);
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
  await rolarListaAte(tester, find.text('Executar estorno'));
  await clicar(tester, find.text('Executar estorno'));
}

Future<void> _revisar(WidgetTester tester, {bool marcar = true}) async {
  await tester.enterText(
      find.descendant(of: modal(), matching: find.widgetWithText(TextField, 'Motivo')), motivo);
  await tester.pumpAndSettle();
  if (marcar) await clicar(tester, noModal(kRotuloPagoNoApp));
  await clicar(tester, noModal('Revisar'));
}

bool _marcada(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(find.byKey(const ValueKey('material-pago-no-app'))).value!;

void main() {
  test('só líder de suporte e administrador executam', () {
    expect({for (final x in Papel.values) if (x.pode(Permissao.materiaisContestacaoAprovar)) x},
        {Papel.liderSuporte, Papel.administrador});
  });

  for (final papel in ['mediador', 'seguranca']) {
    testWidgets('$papel não vê o botão', (tester) async {
      await _abrirTela(tester, _fake(), papel: papel);
      await rolarListaAte(tester, contem('a decisão não pode ser mudada'));
      expect(find.text('Executar estorno'), findsNothing);
    });
  }

  for (final (efeito, status) in [('nenhum', 'parcial'), ('executado', 'parcial'), ('pendente_financeiro', 'improcedente')]) {
    testWidgets('sem botão para $status com efeito $efeito', (tester) async {
      await _abrirTela(tester, _fake(efeito: efeito, status: status));
      await rolarListaAte(tester, contem('a decisão não pode ser mudada'));
      expect(find.text('Executar estorno'), findsNothing);
    });
  }

  testWidgets('caixa nasce desmarcada, motivo curto não passa e nada vai sem confirmar', (tester) async {
    final api = _fake();
    await _abrirTela(tester, api);
    await _abrirModal(tester);
    expect(_marcada(tester), isFalse);
    expect(find.descendant(of: find.byType(Dialog), matching: contem('2 dias úteis')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), 'curto');
    await tester.pumpAndSettle();
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Confirmar estorno'), findsNothing);
    await _revisar(tester);
    expect(api.chamadasMaterial, isEmpty);
    // Reabrir não lembra a marca.
    await clicar(tester, noModal('Voltar'));
    await clicar(tester, noModal('Cancelar'));
    await _abrirModal(tester);
    expect(_marcada(tester), isFalse);
  });

  testWidgets('desmarcada envia false e mostra a recusa de análise manual', (tester) async {
    const recusa = 'Material pago fora do app não tem estorno automático: trate em análise manual.';
    final api = _fake()..falhaMaterial = const ErroApi(recusa, status: 409, codigo: 'analise_manual');
    await _abrirTela(tester, api);
    await _abrirModal(tester);
    await _revisar(tester, marcar: false);
    await clicar(tester, noModal('Confirmar estorno'));
    expect(api.chamadasMaterial.single.$2, {'id': 'cm-1', 'motivo': motivo, 'pago_no_app': false});
    expect(contem(recusa), findsOneWidget);
    expect(contem(kRepetirEstornoMaterial), findsNothing);
    expect(find.text(motivo), findsOneWidget);
  });

  for (final status in [403, 404, 422, 503, null]) {
    testWidgets('erro ${status ?? 'sem resposta'} aparece e preserva o motivo', (tester) async {
      final api = _fake()..falhaMaterial = ErroApi('Recusa de exemplo.', status: status);
      await _abrirTela(tester, api);
      await _abrirModal(tester);
      await _revisar(tester);
      await clicar(tester, noModal('Confirmar estorno'));
      expect(contem('Recusa de exemplo.'), findsOneWidget);
      expect(contem(kRepetirEstornoMaterial), status == null ? findsOneWidget : findsNothing);
      expect(find.text(motivo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('toque duplo envia uma vez só', (tester) async {
    final api = _ApiLenta()..contestacoesMaterial = _fake().contestacoesMaterial;
    await _abrirTela(tester, api);
    await _abrirModal(tester);
    await _revisar(tester);
    final botao = noModal('Confirmar estorno');
    await tester.ensureVisible(botao);
    await tester.pump();
    final onde = tester.getCenter(botao);
    await tester.tapAt(onde);
    await tester.tapAt(onde);
    await tester.pump();
    await tester.tapAt(onde);
    expect(api.chamadasMaterial, hasLength(1));
    api.liberar.complete();
    await tester.pumpAndSettle();
    expect(api.chamadasMaterial, hasLength(1));
  });

  for (final largura in [360.0, 1400.0]) {
    testWidgets('resultado em reais em ${largura.toInt()} px', (tester) async {
      final api = _fake();
      await _abrirTela(tester, api, largura: largura);
      await _abrirModal(tester);
      await _revisar(tester);
      await clicar(tester, noModal('Confirmar estorno'));
      expect(api.chamadasMaterial.single.$2['pago_no_app'], isTrue);
      for (final valor in [r'R$ 51,50', r'R$ 50,00', r'R$ 30,00', r'R$ 20,00', r'R$ 1,50']) {
        expect(find.descendant(of: modal(), matching: contem(valor)), findsWidgets, reason: valor);
      }
      expect(noModal('Confirmar estorno'), findsNothing);
      expect(noModal('Avisar profissional'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('já executada com aviso pendente oferece o reenvio', (tester) async {
    final api = _fake();
    api.estornoMaterial = EstornoMaterial(
      resultado: 'ja_executada',
      contestacao: api.contestacoesMaterial.single,
      valorReconhecidoCentavos: 5000,
      valorRetidoCentavos: 3000,
      valorCompensacaoCentavos: 2000,
      custoParcelamentoCentavos: 0,
      totalEstornadoCentavos: 5000,
      compensacaoId: 'comp-9',
      profissionalAvisado: false,
    );
    await _abrirTela(tester, api);
    await _abrirModal(tester);
    await _revisar(tester);
    await clicar(tester, noModal('Confirmar estorno'));
    expect(contem('já tinha sido executado'), findsOneWidget);
    expect(contem(kAvisoNaoSaiu), findsOneWidget);
    expect(noModal('Avisar profissional'), findsOneWidget);
  });

  test('API: corpo, leitura em centavos e erro com código', () async {
    final pedidos = <http.Request>[];
    var recusar = false;
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
        pedidos.add(r);
        if (recusar) {
          return http.Response.bytes(utf8.encode('{"detail":"Acima da alçada.","codigo":"acima_da_alcada"}'), 403);
        }
        return http.Response(
            jsonEncode({
              'resultado': 'ok',
              'contestacao': {
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
                'efeito_financeiro': 'executado',
              },
              'valor_reconhecido_centavos': 5000,
              'valor_retido_centavos': 5000,
              'valor_compensacao_centavos': 0,
              'custo_parcelamento_centavos': 0,
              'total_estornado_centavos': 5000,
              'compensacao_id': null,
              'profissional_avisado': null,
            }),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final r = await api.executarEstornoMaterial('cm-1', motivo: motivo, materialPagoNoApp: false);
    expect(pedidos.single.method, 'POST');
    expect(pedidos.single.url.path, '/v1/admin/materiais/contestacoes/cm-1/executar-estorno');
    expect(jsonDecode(pedidos.single.body), {'motivo': motivo, 'material_pago_no_app': false});
    expect(r.totalEstornadoCentavos, 5000);
    expect(r.compensacaoId, isNull);
    expect(r.profissionalAvisado, isNull);
    expect(r.contestacao.efeitoFinanceiro, 'executado');
    recusar = true;
    await expectLater(
      api.executarEstornoMaterial('cm-1', motivo: motivo, materialPagoNoApp: true),
      throwsA(isA<ErroApi>()
          .having((e) => e.codigo, 'codigo', 'acima_da_alcada')
          .having((e) => e.mensagem, 'mensagem', 'Acima da alçada.')),
    );
  });

  test('auditoria tem texto próprio, com o total em reais', () {
    final entrada = EntradaAuditoria(
        id: 1,
        ocorridaEm: DateTime(2026, 11, 28),
        ator: 'u1',
        acao: 'financeiro.material_estorno_executado',
        entidade: 'nota_material_contestacoes:cm-1',
        motivo: motivo,
        detalhes: const {'total_estornado_centavos': 5150});
    expect(descreverAcao(entrada), r'executou o estorno de material contestado (total de R$ 51,50)');
  });
}
