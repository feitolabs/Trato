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

Future<ApiFake> abrirRetorno(WidgetTester tester, {ApiFake? api, String papel = 'lider_suporte'}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'retorno_conta', largura: 1400);
  return fake;
}

void main() {
  test('permissões 20.9 correspondem ao backend', () {
    Set<Papel> quem(Permissao p) => {for (final x in Papel.values) if (x.pode(p)) x};
    expect(quem(Permissao.contaRetornoAnalisar),
        {Papel.mediador, Papel.liderSuporte, Papel.seguranca, Papel.administrador});
    expect(quem(Permissao.contaRetornoAprovar), {Papel.liderSuporte, Papel.administrador});
  });

  testWidgets('mediador/segurança não veem aprovar nem revogar; líder vê', (tester) async {
    await abrirRetorno(tester, papel: 'mediador');
    await rolarListaAte(tester, find.text('Recusar retorno'));
    expect(find.text('Aprovar retorno'), findsNothing);

    await tester.tap(find.text('Impedimentos de cadastro'));
    await tester.pumpAndSettle();
    expect(find.text('Revogar impedimento'), findsNothing);
  });

  testWidgets('líder aprova retorno (exige confirmar sem risco) e revoga impedimento', (tester) async {
    final api = await abrirRetorno(tester, papel: 'lider_suporte');
    await rolarListaAte(tester, find.text('Aprovar retorno'));
    await tester.tap(find.text('Aprovar retorno'));
    await tester.pumpAndSettle();
    await escrever(tester, 'Motivo da aprovação', 'Análise concluída sem indícios de risco.');
    // Sem marcar a confirmação de ausência de risco, Revisar fica desabilitado
    await clicar(tester, noModal('Revisar'));
    expect(noModal('Confirmar aprovação'), findsNothing);
    await clicar(tester, noModal('Confirmo que não há risco identificado (Termos 20.9)'));
    await clicar(tester, noModal('Revisar'));
    expect(api.chamadasRetorno, isEmpty);
    await clicar(tester, noModal('Confirmar aprovação'));
    expect(api.chamadasRetorno.single.$1, 'aprovar');
    expect(api.chamadasRetorno.single.$2, {
      'id': 'ret-1',
      'motivo': 'Análise concluída sem indícios de risco.',
      'risco_identificado': false,
    });

    api.chamadasRetorno.clear();
    await tester.tap(find.text('Impedimentos de cadastro'));
    await tester.pumpAndSettle();
    await rolarListaAte(tester, find.text('Revogar impedimento'));
    await tester.tap(find.text('Revogar impedimento'));
    await tester.pumpAndSettle();
    await escrever(tester, 'Motivo da revogação', 'Impedimento aplicado por engano na medida.');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar revogação'));
    expect(api.chamadasRetorno.single.$1, 'revogar');
    expect(api.chamadasRetorno.single.$2, {
      'id': 'imp-1',
      'motivo': 'Impedimento aplicado por engano na medida.',
    });
  });

  testWidgets('iniciar análise e recusar retorno com risco_identificado', (tester) async {
    final api = await abrirRetorno(tester, papel: 'seguranca');
    await rolarListaAte(tester, find.text('Iniciar análise'));
    await tester.tap(find.text('Iniciar análise'));
    await tester.pumpAndSettle();
    await clicar(tester, noModal('Iniciar análise'));
    expect(api.chamadasRetorno.single.$1, 'analisar');
    expect(api.chamadasRetorno.single.$2, {'id': 'ret-1'});

    api.chamadasRetorno.clear();
    await rolarListaAte(tester, find.text('Recusar retorno'));
    await tester.tap(find.text('Recusar retorno'));
    await tester.pumpAndSettle();
    await escrever(tester, 'Motivo da recusa', 'Risco recorrente identificado na análise.');
    await clicar(tester, noModal('Risco identificado'));
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar recusa'));
    expect(api.chamadasRetorno.single.$1, 'recusar');
    expect(api.chamadasRetorno.single.$2, {
      'id': 'ret-1',
      'motivo': 'Risco recorrente identificado na análise.',
      'risco_identificado': true,
    });
  });

  testWidgets('erro 503 na listagem de retornos aparece na tela', (tester) async {
    await abrirRetorno(
      tester,
      api: ApiFake()
        ..falhaListaRetorno = const ErroApi(
          'Retorno/impedimento indisponível: as tabelas ainda não existem no banco de dados.',
          status: 503,
        ),
    );
    expect(find.textContaining('Retorno/impedimento indisponível', findRichText: true), findsWidgets);
  });

  testWidgets('medida de encerramento permite infracao_grave e impedir_nova_conta', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'administrador', api: api, secao: 'medidas', largura: 1400);
    await tester.tap(find.text('Aplicar medida'));
    await tester.pumpAndSettle();
    await escrever(tester, 'Código da conta', 'usr-99');
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Aviso')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encerramento').last);
    await tester.pumpAndSettle();
    await escrever(tester, 'Motivo (o usuário lê)', 'Conduta grave comprovada contra cliente.');
    await escrever(tester, 'Cláusulas dos Termos', '20.9');
    await clicar(tester, noModal('Infração grave (Termos 20.9)'));
    await clicar(tester, noModal('Impedir criação de nova conta'));
    await clicar(tester, noModal('Não, por falta'));
    await clicar(tester, noModal('Revisar medida'));
    await clicar(tester, noModal('Confirmar e aplicar'));
    expect(api.ultimaMedida?.infracaoGrave, isTrue);
    expect(api.ultimaMedida?.impedirNovaConta, isTrue);
    expect(api.ultimaMedida?.semFalta, isFalse);
  });

  test('API: rotas 20.9, encerramento com infração grave e erros 403/409/422/503', () async {
    final pedidos = <http.Request>[];
    (int, String)? recusa;
    const retJson = {
      'id': 'ret-1',
      'protocolo': 'RET-1',
      'usuario_id': 'usr-1',
      'medida_id': 'med-1',
      'justificativa_usuario': 'Peço retorno',
      'canal': 'app',
      'status': 'aberto',
      'solicitado_em': '2026-11-20T10:00:00Z',
      'prazo_dias_aplicado': 180,
      'elegivel_a_partir_de': '2026-11-01T10:00:00Z',
      'risco_identificado': false,
    };
    const impJson = {
      'id': 'imp-1',
      'medida_id': 'med-1',
      'tipo_identificador': 'cpf',
      'criado_por': 'u1',
      'criado_em': '2026-10-01T10:00:00Z',
    };
    const medJson = {
      'id': 'med-1',
      'usuario_id': 'usr-1',
      'tipo': 'encerramento',
      'motivo': 'Conduta grave.',
      'motivo_completo': 'Conduta grave.',
      'clausulas': ['20.9'],
      'inicio_em': '2026-11-20T10:00:00Z',
      'efeito_pedidos_valores': 'Conta encerrada.',
      'como_contestar': 'Pelo suporte.',
      'vigente': true,
      'infracao_grave': true,
      'impedir_nova_conta': true,
    };
    http.Response okJson(Object body, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status);
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return okJson({'access_token': 't'});
        if (r.url.path == '/v1/admin/eu') return okJson({'id': 'u1', 'papel': 'administrador'});
        pedidos.add(r);
        if (recusa != null) return okJson({'detail': recusa.$2}, recusa.$1);
        if (r.url.path == '/v1/admin/medidas') return okJson(medJson, 201);
        if (r.method == 'GET' && r.url.path == '/v1/admin/conta/retornos') {
          return okJson({'itens': [retJson], 'total': 1});
        }
        if (r.method == 'GET' && r.url.path == '/v1/admin/conta/impedimentos') {
          return okJson({'itens': [impJson], 'total': 1});
        }
        if (r.url.path.contains('/impedimentos/')) return okJson(impJson);
        return okJson(retJson);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');

    final med = (await api.aplicarMedida(const NovaMedida(
      usuarioId: 'usr-1',
      tipo: 'encerramento',
      motivo: 'Conduta grave comprovada.',
      clausulas: ['20.9'],
      infracaoGrave: true,
      impedirNovaConta: true,
    )))
        .medida;
    expect(med.infracaoGrave, isTrue);
    expect(med.impedirNovaConta, isTrue);
    expect(jsonDecode(pedidos.last.body)['infracao_grave'], isTrue);
    expect(jsonDecode(pedidos.last.body)['impedir_nova_conta'], isTrue);

    expect((await api.listarRetornosConta(status: 'aberto', usuarioId: 'usr-1')).itens.single.protocolo, 'RET-1');
    await api.analisarRetornoConta('ret-1');
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/conta/retornos/ret-1/analisar');

    await api.aprovarRetornoConta('ret-1', motivo: 'Sem risco identificado.');
    expect(jsonDecode(pedidos.last.body), {'motivo': 'Sem risco identificado.', 'risco_identificado': false});

    await api.recusarRetornoConta('ret-1', motivo: 'Risco ativo.', riscoIdentificado: true);
    expect(jsonDecode(pedidos.last.body), {'motivo': 'Risco ativo.', 'risco_identificado': true});

    expect((await api.listarImpedimentosConta(medidaId: 'med-1', apenasAtivos: true)).itens.single.id, 'imp-1');
    await api.revogarImpedimentoConta('imp-1', motivo: 'Revogado por revisão.');
    expect(jsonDecode(pedidos.last.body), {'motivo': 'Revogado por revisão.'});

    for (final (status, texto) in [
      (403, 'Apenas líder de suporte ou administrador pode aprovar.'),
      (409, 'Este pedido de retorno já foi decidido.'),
      (422, 'Não é permitido aprovar pedido de retorno com risco identificado (20.9).'),
      (503, 'Retorno/impedimento indisponível: as tabelas ainda não existem no banco de dados.'),
    ]) {
      recusa = (status, texto);
      await expectLater(
        api.aprovarRetornoConta('ret-1', motivo: 'Motivo de teste válido.'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', texto).having((e) => e.status, 'status', status)),
      );
    }
  });
}
