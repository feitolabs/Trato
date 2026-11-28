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

const motivo = 'Serviço refeito por outra pessoa';
const daEquipe = 'Conta da equipe: só um administrador pode fazer isto.';

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
  await tester.pump();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<ApiFake> abrir(WidgetTester tester, {ApiFake? api, String papel = 'mediador'}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'compensacoes');
  return fake;
}

Future<void> preencherERevisar(WidgetTester tester, {String valor = '1.234,56'}) async {
  await tester.tap(find.text('Registrar compensação'));
  await tester.pumpAndSettle();
  await escrever(tester, campoNoModal('Código do pedido'), 'ped-1');
  await escrever(tester, campoNoModal('Valor a compensar'), valor);
  await escrever(tester, campoNoModal('Motivo (o profissional lê)'), motivo);
  await clicar(tester, noModal('Revisar'));
}

void main() {
  test('permissão de cancelar: só líder de suporte e administrador', () {
    final quem = [for (final p in Papel.values) if (p.pode(Permissao.compensacoesCancelar)) p];
    expect(quem.toSet(), {Papel.liderSuporte, Papel.administrador});
  });

  testWidgets('lista mostra os valores do servidor, filtro de situação e selo sem aviso', (tester) async {
    final api = await abrir(tester);
    expect(find.text('R\$ 150,50 · falta R\$ 100,50'), findsOneWidget);
    expect(find.text('Sem aviso'), findsOneWidget);
    expect(find.text('R\$ 50,00'), findsOneWidget); // já descontado
    await tester.tap(find.text('Todas').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitada').last);
    await tester.pumpAndSettle();
    expect(api.ultimoStatusCompensacao, 'quitada');
  });

  testWidgets('estados vazio e erro', (tester) async {
    await abrir(tester, api: ApiFake()..compensacoes = []);
    expect(find.text('Nenhuma compensação com esse filtro.'), findsOneWidget);
  });

  testWidgets('erro de carga mostra o texto', (tester) async {
    await abrir(tester, api: ApiFake(erro: true));
    expect(find.text('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('registrar: revisa e só envia ao confirmar, em centavos', (tester) async {
    final api = await abrir(tester);
    await preencherERevisar(tester);
    expect(api.chamadasCompensacao, isEmpty);
    expect(noModal('R\$ 1.234,56'), findsOneWidget);
    await clicar(tester, noModal('Confirmar compensação'));
    expect(api.chamadasCompensacao.single.$2,
        {'pedido': 'ped-1', 'contestacao': null, 'valor': 123456, 'motivo': motivo});
  });

  testWidgets('"12.50" não passa da revisão', (tester) async {
    final api = await abrir(tester);
    await preencherERevisar(tester, valor: '12.50');
    expect(noModal('Confirmar compensação'), findsNothing);
    expect(find.textContaining('Valor inválido. Use vírgula'), findsOneWidget);
    expect(api.chamadasCompensacao, isEmpty);
  });

  testWidgets('duplo clique registra uma vez', (tester) async {
    final api = ApiFake(atraso: const Duration(milliseconds: 200));
    await abrir(tester, api: api);
    await preencherERevisar(tester);
    final botao = noModal('Confirmar compensação');
    await tester.ensureVisible(botao);
    await tester.tap(botao);
    await tester.tap(botao, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.chamadasCompensacao.length, 1);
  });

  testWidgets('ja_registrada e aviso que não saiu são ditos', (tester) async {
    final api = ApiFake()
      ..resultadoCompensacao = 'ja_registrada'
      ..avisoDaCompensacao = false;
    await abrir(tester, api: api);
    await preencherERevisar(tester);
    await clicar(tester, noModal('Confirmar compensação'));
    expect(find.textContaining('Nada novo foi criado'), findsOneWidget);
    expect(find.textContaining('sem aviso, nada é descontado'), findsOneWidget);
  });

  for (final (erro, frase) in [
    (const ErroApi('O valor passa do que pode ser compensado.', status: 422, codigo: 'acima_do_devido', maximoCentavos: 9900),
        'O máximo é R\$ 99,00.'),
    (const ErroApi('Esta decisão já tem compensação com outro valor.', status: 409, codigo: 'conflito'), 'outro valor'),
    (const ErroApi('Não há decisão final que permita compensar.', status: 409, codigo: 'origem_nao_decidida'),
        'Não há decisão final'),
    (const ErroApi('A decisão foi mudada por contestação: informe a contestação.', status: 409,
        codigo: 'decisao_substituida'), 'informe a contestação'),
    (const ErroApi('Pedido sem contrato.', status: 404, codigo: 'contrato_nao_encontrado'), 'Pedido sem contrato'),
    (const ErroApi('Explique o motivo.', status: 422, codigo: 'motivo_invalido'), 'Explique o motivo'),
    (const ErroApi('Só alguém ativo da equipe pode fazer isto.', proibido: true, status: 403, codigo: 'analista_invalido'),
        'Só alguém ativo'),
    (const ErroApi('A compensação ainda não está disponível.', status: 503, codigo: 'indisponivel'),
        'ainda não está disponível'),
    (const ErroApi('O servidor demorou para responder. Tente de novo.'), 'Confira a lista antes de repetir'),
  ]) {
    testWidgets('recusa ${erro.codigo ?? 'sem resposta'} fica no modal', (tester) async {
      await abrir(tester, api: ApiFake()..falhaCompensacao = erro);
      await preencherERevisar(tester);
      await clicar(tester, noModal('Confirmar compensação'));
      expect(find.textContaining(frase, findRichText: true), findsOneWidget);
      expect(noModal(motivo), findsOneWidget); // o preenchimento continua
    });
  }

  testWidgets('avisar pede confirmação', (tester) async {
    final api = await abrir(tester);
    await tocar(tester, find.text('Avisar profissional'));
    expect(api.chamadasCompensacao, isEmpty);
    await clicar(tester, noModal('Enviar aviso'));
    expect(api.chamadasCompensacao.single.$1, 'avisar');
    expect(find.textContaining('Profissional avisado'), findsOneWidget);
  });

  testWidgets('mediador não cancela; líder cancela com motivo e vê o devolvido', (tester) async {
    await abrir(tester, api: ApiFake()..compensacoes = [ApiFake.compensacaoDeExemplo(podeCancelar: false)]);
    expect(find.text('Cancelar compensação'), findsNothing);
    expect(find.textContaining('só para líder de suporte'), findsOneWidget);
  });

  testWidgets('cancelar pelo líder', (tester) async {
    final api = await abrir(tester, papel: 'lider_suporte');
    await tocar(tester, find.text('Cancelar compensação'));
    expect(api.chamadasCompensacao, isEmpty);
    await confirmarMotivo(tester, 'Cancelar compensação', motivo: 'Contestação do profissional aceita');
    expect(api.chamadasCompensacao.single.$2, {'id': 'comp-div-1', 'motivo': 'Contestação do profissional aceita'});
    expect(find.textContaining('Devolvido ao profissional: R\$ 50,00'), findsOneWidget);
  });

  testWidgets('sem disputas_decidir não há a seção', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2');
    expect(find.byKey(const ValueKey('menu-compensacoes')), findsNothing);
  });

  testWidgets('conta da equipe: bloqueio recusado mostra o texto do servidor', (tester) async {
    final api = _RiscoRecusa();
    await abrirPainel(tester, papel: 'seguranca', api: api, secao: 'risco');
    await tocar(tester, find.text('Bloquear conta'));
    await escrever(tester, campoNoModal('Motivo interno (o usuário não vê)'), 'Padrão de fraude no alerta');
    await escrever(tester, campoNoModal('Motivo que o usuário vai ler'), 'Atividade fora do padrão na conta');
    await escrever(tester, campoNoModal('Cláusulas dos Termos'), '20.3');
    await clicar(tester, noModal('Bloquear conta'));
    expect(find.textContaining(daEquipe), findsOneWidget);
  });

  testWidgets('conta da equipe: reverter medida recusado mostra o texto do servidor', (tester) async {
    final api = ApiFake()..falhaMedida = const ErroApi(daEquipe, proibido: true, status: 403);
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'medidas');
    await tocar(tester, find.text('Reverter medida'));
    await confirmarMotivo(tester, 'Reverter medida', motivo: 'Aplicada por engano');
    expect(find.textContaining(daEquipe, findRichText: true), findsWidgets);
  });

  Future<void> abrirAsBases(WidgetTester tester, String papel, {ApiFake? api}) async {
    await abrirPainel(tester, papel: papel, api: api ?? ApiFake(), secao: 'disputas');
    await tocar(tester, find.text('Ver conversa'));
  }

  for (final (papel, ve) in [('mediador', false), ('lider_suporte', false), ('administrador', true)]) {
    testWidgets('ordem judicial para $papel: ${ve ? 'aparece' : 'escondida'}', (tester) async {
      await abrirAsBases(tester, papel);
      await tester.tap(find.text('Disputa').last);
      await tester.pumpAndSettle();
      expect(find.text('Autorização do usuário'), findsWidgets);
      expect(find.text('Ordem judicial'), ve ? findsWidgets : findsNothing);
    });
  }

  testWidgets('resposta de conversas vazia tem estado claro', (tester) async {
    await abrirAsBases(tester, 'mediador', api: ApiFake()..conversaVazia = true);
    await escrever(tester, campoNoModal('Motivo'), 'Apurando a disputa aberta');
    await clicar(tester, noModal('Ler mensagens'));
    expect(find.textContaining('Nenhuma conversa para mostrar.', findRichText: true), findsOneWidget);
    expect(find.textContaining('acesso ficou registrado', findRichText: true), findsOneWidget);
    expect(noModal('Ler mensagens'), findsNothing);
  });

  test('API: rotas, corpos, centavos, maximo_centavos e 403 sem codigo', () async {
    final pedidos = <http.Request>[];
    var status = 200;
    Object? forcado;
    const item = {
      'id': 'c1',
      'pedido_id': 'p1',
      'origem': 'disputa',
      'valor_centavos': 15050,
      'compensado_centavos': 0,
      'restante_centavos': 15050,
      'motivo': 'm',
      'status': 'aberta',
      'criada_em': '2026-11-25T10:00:00Z',
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        final Object corpo = forcado ??
            (r.method == 'GET'
                ? {'itens': [item], 'total': 1}
                : {'resultado': 'ok', 'compensacao': item, 'avisado': true, 'devolvido_centavos': 700});
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');

    final pagina = await api.listarCompensacoes(profissionalId: 'pro', pedidoId: 'p1', status: 'aberta');
    expect(pagina.itens.single.valorCentavos, 15050);
    expect(pedidos.last.url.queryParameters,
        {'profissional_id': 'pro', 'pedido_id': 'p1', 'status': 'aberta', 'limite': '50', 'deslocamento': '0'});
    await api.registrarCompensacao(pedidoId: 'p1', valorCentavos: 15050, motivo: motivo);
    expect(pedidos.last.url.path, '/v1/admin/compensacoes');
    expect(jsonDecode(pedidos.last.body),
        {'pedido_id': 'p1', 'contestacao_id': null, 'valor_centavos': 15050, 'motivo': motivo});
    expect(pedidos.last.body, contains('"valor_centavos":15050'));
    await api.avisarCompensacao('c1');
    expect('${pedidos.last.method} ${pedidos.last.url.path}', 'POST /v1/admin/compensacoes/c1/avisar');
    final r = await api.cancelarCompensacao('c1', motivo: motivo);
    expect(pedidos.last.url.path, '/v1/admin/compensacoes/c1/cancelar');
    expect(jsonDecode(pedidos.last.body), {'motivo': motivo});
    expect(r.devolvidoCentavos, 700);

    status = 422;
    forcado = {'detail': 'Passa.', 'codigo': 'acima_do_devido', 'maximo_centavos': 9900};
    await expectLater(
      api.registrarCompensacao(pedidoId: 'p1', valorCentavos: 99999, motivo: motivo),
      throwsA(isA<ErroApi>()
          .having((e) => e.codigo, 'codigo', 'acima_do_devido')
          .having((e) => e.maximoCentavos, 'maximo', 9900)),
    );
    status = 403;
    forcado = {'detail': daEquipe};
    await expectLater(
      api.reverterMedida('m1', motivo: motivo),
      throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', daEquipe).having((e) => e.codigo, 'codigo', null)),
    );
    await expectLater(api.travarSaque('u1', motivo: motivo),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', daEquipe)));
  });
}

/// Servidor que recusa o bloqueio de uma conta da equipe.
class _RiscoRecusa extends ApiFake {
  @override
  Future<void> aplicarBloqueioPreventivo(String usuarioId,
          {required String motivo, String? motivoUsuario, List<String> clausulas = const []}) async =>
      throw const ErroApi(daEquipe, proibido: true, status: 403);
}
