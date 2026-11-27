import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/formato.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

const resposta = 'Revimos as fotos enviadas pelas partes';

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder campoNoModal(String rotulo) =>
    find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));

Future<void> clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> escrever(WidgetTester tester, Finder campo, String texto) async {
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> digitar(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.widgetWithText(TextField, rotulo);
  await rolarListaAte(tester, campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

Future<ApiFake> abrir(WidgetTester tester,
    {ApiFake? api, String papel = 'mediador', ContestacaoDisputa? caso}) async {
  final fake = api ?? ApiFake();
  if (caso != null) fake.contestacoesDisputa = [caso];
  await abrirPainel(tester, papel: papel, api: fake, secao: 'contestacoes');
  return fake;
}

Future<void> escolherNova(WidgetTester tester, String rotulo) async {
  final campo = find.text('Nova decisão');
  await rolarListaAte(tester, campo);
  await tester.tap(campo);
  await tester.pumpAndSettle();
  await tester.tap(find.text(rotulo).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fila e detalhe: selos, valores do servidor e filtros enviados', (tester) async {
    final api = await abrir(tester, caso: ApiFake.contestacaoDeExemplo(vigente: 10050));
    expect(find.text('CD-EXEMPLO-1 · cliente'), findsOneWidget);
    expect(find.text('Atrasada'), findsWidgets);
    expect(find.text('R\$ 300,00'), findsOneWidget);
    await rolarListaAte(tester, find.textContaining('volta ao cliente R\$ 100,50'));
    await tester.tap(find.text('Só atrasadas'));
    await tester.pumpAndSettle();
    expect(api.ultimoFiltroContestacoes!.atrasadas, isTrue);
  });

  testWidgets('estado vazio', (tester) async {
    await abrir(tester, api: ApiFake()..contestacoesDisputa = []);
    expect(find.text('Nenhuma contestação com esse filtro.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrir(tester, api: ApiFake(erro: true));
    expect(find.text('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('manter: confirma antes e não manda decisão nem valor', (tester) async {
    final api = await abrir(tester);
    await tocar(tester, find.text('Manter'));
    await digitar(tester, 'Resposta que as duas partes vão ler', resposta);
    await tocar(tester, find.text('Revisar decisão'));
    expect(api.chamadasContestacao, isEmpty);
    expect(find.textContaining('Nenhum dinheiro é movimentado'), findsOneWidget);
    await clicar(tester, noModal('Enviar decisão'));
    expect(api.chamadasContestacao.single.$2,
        {'resultado': 'mantida', 'resposta': resposta, 'nova': null, 'valor': null});
  });

  testWidgets('alterar para parcial: leitura estrita e centavos inteiros', (tester) async {
    final api = await abrir(tester);
    await tocar(tester, find.text('Alterar'));
    await escolherNova(tester, 'Reembolso parcial');
    await digitar(tester, 'Resposta que as duas partes vão ler', resposta);
    await digitar(tester, 'Novo valor do reembolso', '100.50');
    expect(find.text(kErroReais), findsOneWidget);
    await tocar(tester, find.text('Revisar decisão'));
    expect(find.byType(Dialog), findsNothing);
    await digitar(tester, 'Novo valor do reembolso', '100,50');
    await tocar(tester, find.text('Revisar decisão'));
    expect(find.textContaining('R\$ 100,50'), findsWidgets);
    await clicar(tester, noModal('Enviar decisão'));
    expect(api.chamadasContestacao.single.$2,
        {'resultado': 'alterada', 'resposta': resposta, 'nova': 'reembolso_parcial', 'valor': 10050});
  });

  testWidgets('quem decidiu a disputa não vê o formulário', (tester) async {
    await abrir(tester, caso: ApiFake.contestacaoDeExemplo(decididaPor: 'eq-mediador'));
    await rolarListaAte(tester, find.textContaining('outra pessoa analisa', findRichText: true));
    expect(find.text('Revisar decisão'), findsNothing);
  });

  testWidgets('quem analisou não aprova a própria decisão', (tester) async {
    await abrir(tester,
        papel: 'lider_suporte',
        caso: ApiFake.contestacaoDeExemplo(status: 'aguardando_aprovacao', analistaId: 'eq-lider_suporte'));
    await rolarListaAte(tester, find.textContaining('precisa ser de outra pessoa', findRichText: true));
    expect(find.text('Aprovar decisão'), findsNothing);
  });

  for (final (erro, frase) in [
    (const ErroApi('Quem decidiu, aprovou ou é parte da disputa não pode analisar.', proibido: true, status: 403,
        codigo: 'analista_impedido'), 'não pode analisar'),
    (const ErroApi('Esta contestação já mudou. Atualize e confira.', status: 409, codigo: 'mudou'), 'já mudou'),
    (const ErroApi('A nova decisão é igual à que vale hoje.', status: 422, codigo: 'sem_mudanca'), 'igual à que vale'),
    (const ErroApi('Use revertida só quando tudo muda de lado.', status: 422, codigo: 'resultado_incoerente'),
        'tudo muda de lado'),
    (const ErroApi('Confira a nova decisão.', status: 422, codigo: 'decisao_invalida'), 'Confira a nova decisão'),
    (const ErroApi('Contestação não encontrada.', status: 404, codigo: 'nao_encontrada'), 'não encontrada'),
    (const ErroApi('A contestação ainda não está disponível.', status: 503, codigo: 'indisponivel'),
        'ainda não está disponível'),
  ]) {
    testWidgets('recusa ${erro.codigo} fica no detalhe e o texto continua', (tester) async {
      await abrir(tester, api: ApiFake()..falhaContestacao = erro);
      await tocar(tester, find.text('Manter'));
      await digitar(tester, 'Resposta que as duas partes vão ler', resposta);
      await tocar(tester, find.text('Revisar decisão'));
      await clicar(tester, noModal('Enviar decisão'));
      expect(find.textContaining(frase, findRichText: true), findsWidgets);
      expect(find.text(resposta), findsOneWidget);
    });
  }

  testWidgets('segunda pessoa aprova com motivo', (tester) async {
    final api = await abrir(tester,
        papel: 'lider_suporte',
        caso: ApiFake.contestacaoDeExemplo(
            status: 'aguardando_aprovacao', analistaId: 'outra', novaDecisao: 'reembolso_total', resposta: resposta));
    await tocar(tester, find.text('Aprovar decisão'));
    expect(api.chamadasContestacao, isEmpty);
    await confirmarMotivo(tester, 'Aprovar', motivo: 'Conferi as provas do caso');
    expect(api.chamadasContestacao.single.$2, {'aprovar': true, 'motivo': 'Conferi as provas do caso'});
  });

  testWidgets('segunda pessoa devolve; erro de alçada aparece', (tester) async {
    final api = ApiFake()
      ..falhaContestacao = const ErroApi('O valor da disputa está acima da alçada de quem aprova.',
          proibido: true, status: 403, codigo: 'alcada');
    await abrir(tester, api: api, papel: 'lider_suporte', caso: ApiFake.contestacaoDeExemplo(status: 'aguardando_aprovacao'));
    await tocar(tester, find.text('Devolver para análise'));
    await confirmarMotivo(tester, 'Devolver', motivo: 'Faltou olhar o orçamento');
    expect(api.chamadasContestacao.single.$2, {'aprovar': false, 'motivo': 'Faltou olhar o orçamento'});
    expect(find.textContaining('acima da alçada', findRichText: true), findsWidgets);
  });

  testWidgets('sem disputas_segunda_pessoa não há aprovação', (tester) async {
    await abrir(tester, caso: ApiFake.contestacaoDeExemplo(status: 'aguardando_aprovacao'));
    expect(find.text('Aprovar decisão'), findsNothing);
    await rolarListaAte(tester, find.textContaining('Aguarda a aprovação', findRichText: true));
  });

  testWidgets('pendente financeiro: nada movimentado e atalho já preenchido, sem valor', (tester) async {
    final api = await abrir(tester,
        caso: ApiFake.contestacaoDeExemplo(status: 'alterada', efeito: 'pendente_financeiro', vigente: 10050));
    expect(find.textContaining('Nada foi movimentado.', findRichText: true), findsOneWidget);
    expect(find.text('Dinheiro pendente'), findsWidgets);
    await tocar(tester, find.text('Registrar compensação'));
    String texto(String rotulo) => tester.widget<TextField>(campoNoModal(rotulo)).controller!.text;
    expect(texto('Código do pedido'), 'ped-exemplo-1');
    expect(texto('Código da contestação (opcional)'), 'cd-1');
    expect(texto('Valor a compensar'), '');
    await escrever(tester, campoNoModal('Valor a compensar'), '100,50');
    await escrever(tester, campoNoModal('Motivo (o profissional lê)'), 'Decisão revista a favor do cliente');
    await clicar(tester, noModal('Revisar'));
    await clicar(tester, noModal('Confirmar compensação'));
    expect(api.chamadasCompensacao.single.$2['contestacao'], 'cd-1');
    expect(api.chamadasCompensacao.single.$2['pedido'], 'ped-exemplo-1');
  });

  testWidgets('pendente que devolve menos ao cliente: sem atalho de compensação', (tester) async {
    await abrir(tester,
        caso: ApiFake.contestacaoDeExemplo(
            status: 'alterada', efeito: 'pendente_financeiro', original: 20000, vigente: 5000));
    expect(find.textContaining('Nada foi movimentado.', findRichText: true), findsOneWidget);
    expect(find.text('Registrar compensação'), findsNothing);
    expect(find.textContaining('compensação não se aplica'), findsOneWidget);
  });

  group('registro pelo atendimento', () {
    Chamado chamado({String? usuario = 'cli-1', bool retencao = false}) => Chamado(
          id: 'ch-1',
          protocolo: 'SAC-EXEMPLO-1',
          assunto: 'a',
          solicitante: 'Ana (exemplo)',
          status: 'aberto',
          categoria: 'contestacao',
          canal: 'telefone',
          abertoEm: DateTime(2026, 11, 20),
          responderAte: DateTime(2026, 11, 27),
          usuarioId: usuario,
          pedidoId: 'ped-exemplo-1',
          contestacaoRetencao: retencao,
        );

    testWidgets('a partir do chamado: conta, chamado e pedido vão preenchidos', (tester) async {
      final api = ApiFake()..chamados = [chamado()];
      await abrirPainel(tester, papel: 'atendente_n1', api: api, secao: 'atendimento');
      await tocar(tester, find.text('Registrar contestação de disputa'));
      await clicar(tester, noModal('Revisar'));
      expect(noModal('Confirmar registro'), findsNothing); // falta o texto
      await escrever(tester, campoNoModal('O que a análise não considerou'), 'Não olharam as fotos do antes');
      await escrever(tester, campoNoModal('Códigos dos anexos (opcional)'), 'a1, a2');
      await clicar(tester, noModal('Revisar'));
      expect(api.chamadasContestacao, isEmpty);
      await clicar(tester, noModal('Confirmar registro'));
      expect(api.chamadasContestacao.single.$2, {
        'pedido': 'ped-exemplo-1',
        'contestante': 'cli-1',
        'chamado': 'ch-1',
        'texto': 'Não olharam as fotos do antes',
        'anexos': ['a1', 'a2'],
      });
    });

    for (final codigo in ['chamado_invalido', 'nao_e_parte']) {
      testWidgets('recusa $codigo fica no modal', (tester) async {
        final api = ApiFake()
          ..chamados = [chamado()]
          ..falhaContestacao = ErroApi('Recusa $codigo do servidor.', status: 422, codigo: codigo);
        await abrirPainel(tester, papel: 'atendente_n1', api: api, secao: 'atendimento');
        await tocar(tester, find.text('Registrar contestação de disputa'));
        await escrever(tester, campoNoModal('O que a análise não considerou'), 'Não olharam as fotos do antes');
        await clicar(tester, noModal('Revisar'));
        await clicar(tester, noModal('Confirmar registro'));
        expect(find.textContaining('Recusa $codigo do servidor.', findRichText: true), findsOneWidget);
        expect(noModal('Não olharam as fotos do antes'), findsOneWidget);
      });
    }

    testWidgets('chamado sem conta ou de retenção não oferece o registro', (tester) async {
      final api = ApiFake()..chamados = [chamado(usuario: null)];
      await abrirPainel(tester, papel: 'atendente_n1', api: api, secao: 'atendimento');
      expect(find.text('Registrar contestação de disputa'), findsNothing);
    });
  });

  test('API: rotas, filtros, corpos, 200 repetida e centavos', () async {
    final pedidos = <http.Request>[];
    var status = 201;
    const item = {
      'id': 'c1',
      'protocolo': 'P',
      'pedido_id': 'p1',
      'disputa_id': 'd1',
      'contestante_id': 'u1',
      'contestante_papel': 'cliente',
      'o_que_faltou': 't',
      'anexos': ['a'],
      'canal': 'sac',
      'status': 'aguardando_aprovacao',
      'aberta_em': '2026-11-20T10:00:00Z',
      'contestar_ate': '2026-11-27T10:00:00Z',
      'responder_ate': '2026-12-04T10:00:00Z',
      'atrasada': false,
      'efeito_financeiro': 'nenhum',
      'novo_valor_reembolso_centavos': 10050,
      'valor_congelado_centavos': 30000,
      'decisao_original': {'resultado': 'liberar_tudo', 'reembolso_centavos': 0},
      'decisao_vigente': {'resultado': 'liberar_tudo', 'reembolso_centavos': 0},
      'decidida_por': 'x',
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        final lista = r.method == 'GET' && r.url.path == '/v1/admin/contestacoes-disputa';
        return http.Response(jsonEncode(lista ? {'itens': [item], 'total': 1} : item), lista ? 200 : status);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    const base = '/v1/admin/contestacoes-disputa';

    await api.listarContestacoesDisputa(const FiltroContestacoes(
        status: 'aberta', efeito: 'pendente_financeiro', pedidoId: 'p1', atrasadas: true));
    expect(pedidos.last.url.queryParameters, {
      'status': 'aberta',
      'efeito_financeiro': 'pendente_financeiro',
      'pedido_id': 'p1',
      'atrasadas': 'true',
      'limite': '50',
      'deslocamento': '0',
    });
    final d = await api.obterContestacaoDisputa('c1');
    expect((d.valorCongeladoCentavos, d.decisaoOriginal!.reembolsoCentavos, d.novoValorReembolsoCentavos),
        (30000, 0, 10050));
    Future<({ContestacaoDisputa contestacao, bool repetida})> registrar() => api.registrarContestacaoDisputa(
        pedidoId: 'p1', contestanteId: 'u1', chamadoId: 'ch', oQueFaltou: 'texto longo');
    expect((await registrar()).repetida, isFalse);
    expect(jsonDecode(pedidos.last.body),
        {'pedido_id': 'p1', 'contestante_id': 'u1', 'chamado_id': 'ch', 'o_que_faltou': 'texto longo', 'anexos': []});
    status = 200;
    expect((await registrar()).repetida, isTrue);
    await api.decidirContestacaoDisputa('c1',
        resultado: 'alterada', resposta: resposta, novaDecisao: 'reembolso_parcial', novoValorReembolsoCentavos: 10050);
    expect(pedidos.last.url.path, '$base/c1/decisao');
    expect(pedidos.last.body, contains('"novo_valor_reembolso_centavos":10050'));
    await api.aprovarContestacaoDisputa('c1', aprovar: false, motivo: 'motivo longo');
    expect(pedidos.last.url.path, '$base/c1/aprovacao');
    expect(jsonDecode(pedidos.last.body), {'aprovar': false, 'motivo': 'motivo longo'});
  });
}
