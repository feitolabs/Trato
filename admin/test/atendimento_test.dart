import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Chamado exemplo({
  String status = 'aberto',
  String categoria = 'duvida',
  String assunto = 'Assunto de exemplo',
  String? responsavel,
  String? usuario,
  bool retencao = false,
  String? responsavelNome,
}) =>
    Chamado(
      id: 'ch-1',
      protocolo: 'SAC-EXEMPLO-000031',
      assunto: assunto,
      solicitante: 'Paulo (exemplo)',
      status: status,
      categoria: categoria,
      canal: 'telefone',
      abertoEm: DateTime(2026, 11, 1),
      responderAte: DateTime(2026, 11, 8),
      responsavelId: responsavel,
      responsavelNome: responsavelNome,
      contestacaoRetencao: retencao,
      usuarioId: usuario,
      contato: '31 0000-0000',
    );

Future<ApiFake> abrir(WidgetTester tester,
    {ApiFake? api, String papel = 'atendente_n1', double largura = 1400, double altura = 1000}) async {
  final fake = api ?? ApiFake();
  await abrirPainel(tester, papel: papel, api: fake, secao: 'atendimento', largura: largura, altura: altura);
  return fake;
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await rolarListaAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Finder noModal(String texto) => find.descendant(of: find.byType(Dialog), matching: find.text(texto));
Finder campoNoModal(String rotulo) =>
    find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextField, rotulo));

void main() {
  testWidgets('fila com selo atrasado, nota interna marcada e filtros enviados ao servidor', (tester) async {
    final api = await abrir(tester);
    expect(find.text('Atrasado'), findsWidgets);
    await rolarListaAte(tester, find.textContaining('nota interna (o usuário não vê)'));
    await tester.tap(find.text('Só atrasados'));
    await tester.pumpAndSettle();
    expect(api.ultimoFiltroChamados!.atrasados, isTrue);
    await tester.enterText(find.widgetWithText(TextField, 'Protocolo'), 'SAC-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.ultimoFiltroChamados!.protocolo, 'SAC-1');
  });

  testWidgets('resposta ao usuário pede confirmação; nota interna não envia ao usuário', (tester) async {
    final api = await abrir(tester);
    await rolarListaAte(tester, find.widgetWithText(TextField, 'Mensagem ao usuário'));
    await tester.enterText(find.widgetWithText(TextField, 'Mensagem ao usuário'), 'Olá, segue a resposta');
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Aguardar resposta do usuário'));
    await tocar(tester, find.text('Responder'));
    expect(api.chamadasSac, isEmpty);
    await tester.tap(noModal('Enviar resposta'));
    await tester.pumpAndSettle();
    expect(api.chamadasSac.single.$2, {'texto': 'Olá, segue a resposta', 'interna': false, 'aguardar': true});

    await tocar(tester, find.text('Nota interna'));
    await rolarListaAte(tester, find.widgetWithText(TextField, 'Nota interna (só a equipe vê)'));
    await tester.enterText(find.widgetWithText(TextField, 'Nota interna (só a equipe vê)'), 'Anotação');
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Salvar nota'));
    expect(api.chamadasSac.last.$2, {'texto': 'Anotação', 'interna': true, 'aguardar': false});
  });

  testWidgets('falha mantém o texto e mostra o erro do servidor', (tester) async {
    final api = ApiFake()..falhaChamado = const ErroApi('Este chamado está encerrado.', status: 409);
    await abrir(tester, api: api);
    await tocar(tester, find.text('Nota interna'));
    await rolarListaAte(tester, find.widgetWithText(TextField, 'Nota interna (só a equipe vê)'));
    await tester.enterText(find.widgetWithText(TextField, 'Nota interna (só a equipe vê)'), 'Texto que fica');
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Salvar nota'));
    expect(find.textContaining('Este chamado está encerrado.', findRichText: true), findsWidgets);
    expect(find.text('Texto que fica'), findsOneWidget);
  });

  testWidgets('assumir no lugar de outra pessoa envia substituir', (tester) async {
    final api = ApiFake()..chamados = [exemplo(responsavel: 'outra-pessoa')];
    await abrir(tester, api: api);
    await tocar(tester, find.text('Assumir'));
    await tester.tap(noModal('Assumir no lugar'));
    await tester.pumpAndSettle();
    expect(api.chamadasSac.single.$1, 'assumir');
    expect(api.chamadasSac.single.$2, {'substituir': true});
  });

  testWidgets('encerrar exige resposta final e envia uma vez com duplo clique', (tester) async {
    final api = ApiFake(atraso: const Duration(milliseconds: 200))..chamados = [exemplo()];
    await abrir(tester, api: api);
    await tocar(tester, find.text('Encerrar'));
    await tester.enterText(campoNoModal('Resposta final ao usuário'), 'Resolvido conforme combinado');
    await tester.pump();
    await tester.tap(noModal('Encerrar chamado'));
    await tester.tap(noModal('Encerrar chamado'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2)); // esgota o atraso simulado
    await tester.pumpAndSettle();
    expect(api.chamadasSac.length, 1);
    expect(api.chamadasSac.single.$2, {'mensagem': 'Resolvido conforme combinado'});
  });

  testWidgets('estender prazo pede data e motivo', (tester) async {
    final api = ApiFake()..chamados = [exemplo()];
    await abrir(tester, api: api);
    await tocar(tester, find.text('Estender prazo'));
    expect(find.textContaining('lê o motivo'), findsOneWidget);
    await tester.enterText(campoNoModal('Motivo (o usuário lê)'), 'Aguardando retorno do parceiro');
    await tester.pump();
    await tester.tap(noModal('Informar novo prazo'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.chamadasSac, isEmpty); // falta a data
    await tester.tap(noModal('Novo prazo (até o fim do dia)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(noModal('Informar novo prazo'));
    await tester.pumpAndSettle();
    final ate = api.chamadasSac.single.$2['ate'] as DateTime;
    expect((ate.hour, ate.minute), (23, 59));
  });

  testWidgets('contestação de retenção não encerra e leva a Cliente ausente', (tester) async {
    final api = ApiFake()
      ..chamados = [exemplo(categoria: 'contestacao', retencao: true)];
    await abrir(tester, api: api, papel: 'lider_suporte');
    expect(find.text('Encerrar'), findsNothing);
    await tocar(tester, find.text('Abrir Cliente ausente'));
    expect(find.text('Casos em aberto, pelo prazo mais próximo'), findsOneWidget);
  });

  testWidgets('no celular o atalho fecha o detalhe e troca de seção', (tester) async {
    final api = ApiFake()
      ..chamados = [exemplo(categoria: 'contestacao', retencao: true)];
    await abrirPainel(tester, papel: 'lider_suporte', api: api, largura: 360, altura: 740);
    await tester.tap(find.byKey(const ValueKey('menu-mais')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atendimento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('SAC-EXEMPLO-000031').first);
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Abrir Cliente ausente'));
    expect(find.text('Casos em aberto, pelo prazo mais próximo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registrar contato exige contato ou conta e mostra o protocolo', (tester) async {
    final api = ApiFake()..chamados = [exemplo()];
    await abrir(tester, api: api);
    await tester.tap(find.text('Registrar contato'));
    await tester.pumpAndSettle();
    Future<void> campo(String rotulo, String v) async {
      await tester.ensureVisible(campoNoModal(rotulo));
      await tester.enterText(campoNoModal(rotulo), v);
      await tester.pump();
    }

    await campo('Assunto', 'Cobrança em dobro');
    await campo('O que a pessoa disse', 'Disse que foi cobrada duas vezes');
    final enviar = noModal('Registrar e gerar protocolo');
    await tester.ensureVisible(enviar);
    await tester.tap(enviar, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.chamadasSac, isEmpty);
    await campo('Telefone ou e-mail', '31 0000-0000');
    await tester.ensureVisible(enviar);
    await tester.tap(enviar);
    await tester.pumpAndSettle();
    expect(api.chamadasSac.single.$2['canal'], 'telefone');
    expect(noModal('Contato registrado'), findsOneWidget);
    expect(find.text('SAC-EXEMPLO-000031'), findsWidgets);
  });

  testWidgets('mostra o nome do responsável e usa a marca do servidor, não o assunto', (tester) async {
    final api = ApiFake()
      ..chamados = [
        exemplo(
            categoria: 'contestacao',
            assunto: 'Contestação da retenção por cliente ausente',
            responsavel: 'outra',
            responsavelNome: 'Carla (exemplo)')
      ];
    await abrir(tester, api: api);
    expect(find.text('Carla (exemplo)'), findsOneWidget);
    await rolarListaAte(tester, find.text('Encerrar'));
    expect(find.text('Abrir Cliente ausente'), findsNothing);
  });

  testWidgets('estado vazio', (tester) async {
    await abrir(tester, api: ApiFake()..chamados = []);
    expect(find.text('Nenhum chamado com esse filtro.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrir(tester, api: ApiFake(erro: true));
    expect(find.text('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('quem não tem suporte_ver não vê a seção', (tester) async {
    await abrirPainel(tester, papel: 'mediador');
    expect(find.byKey(const ValueKey('menu-atendimento')), findsNothing);
  });

  testWidgets('segurança vê "Ver conversa" no alerta com pedido', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'seguranca', api: api, secao: 'risco');
    await tester.tap(find.textContaining('PED-10498').first);
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Ver conversa'));
    expect(api.chamadasConversa, isEmpty);
    await tester.enterText(campoNoModal('Motivo'), 'Apurando o alerta de risco');
    await tester.pump();
    await tester.tap(noModal('Ler mensagens'));
    await tester.pumpAndSettle();
    expect(api.chamadasConversa.single.$1, 'ped-exemplo-10498');
    expect(api.chamadasConversa.single.$3, 'incidente');
  });

  test('API: paginação, filtros e corpos das ações', () async {
    final pedidos = <http.Request>[];
    const chamado = {
      'id': 'c1',
      'protocolo': 'P-1',
      'assunto': 'a',
      'solicitante': 's',
      'status': 'aberto',
      'aberto_em': '2026-11-25T10:00:00Z',
      'categoria': 'duvida',
      'canal': 'app',
      'responder_ate': '2026-12-01T10:00:00Z',
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"atendente_n1"}', 200);
        pedidos.add(r);
        final lista = r.method == 'GET' && r.url.path == '/v1/admin/chamados';
        return http.Response(
            jsonEncode(lista ? {'itens': [chamado], 'total': 7, 'limite': 50, 'deslocamento': 0} : chamado), 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    final pagina = await api.listarChamados(const FiltroChamados(status: 'aberto', atrasados: true), deslocamento: 50);
    expect(pagina.total, 7);
    expect(pedidos.last.url.queryParameters,
        {'status': 'aberto', 'atrasados': 'true', 'limite': '50', 'deslocamento': '50'});
    Future<void> confere(Future<Object?> chamada, String caminho, Map<String, Object?> corpo) async {
      await chamada;
      expect(pedidos.last.url.path, '/v1/admin/chamados$caminho');
      expect(jsonDecode(pedidos.last.body), corpo);
    }

    await confere(api.assumirChamado('c1', substituir: true), '/c1/assumir', {'substituir': true});
    await confere(api.responderChamado('c1', texto: 'x', interna: true), '/c1/mensagens',
        {'texto': 'x', 'interna': true, 'aguardar_usuario': false});
    await confere(api.encerrarChamado('c1', mensagem: 'resposta final'), '/c1/encerrar', {'mensagem': 'resposta final'});
    await confere(api.estenderPrazoChamado('c1', ate: DateTime.utc(2026, 12, 10, 23, 59), motivo: 'motivo longo'),
        '/c1/prazo', {'novo_prazo_ate': '2026-12-10T23:59:00.000Z', 'motivo': 'motivo longo'});
  });
}
