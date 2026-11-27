import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/campos_trava.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// `trava_fraude_vigente` e o prazo máximo informado pelo backend. Null = não informado.
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);
Finder _noDialogo(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

class _Api extends ApiFake {
  _Api({this.trava, this.falhaDetalhe = false});
  final bool? trava;
  final bool falhaDetalhe;

  @override
  Future<List<AlertaRisco>> listarAlertasRisco() async => [
        AlertaRisco(
          id: 'r-t',
          usuarioId: 'u-103',
          usuarioNome: 'Carla M.',
          usuarioTipo: 'profissional',
          usuarioStatus: 'restrito',
          tipo: 'troca_de_chave_pix',
          severidade: 'media',
          detalhes: 'Exemplo.',
          criadoEm: '2026-11-03T10:00:00Z',
          travaFraudeVigente: trava,
        ),
      ];

  // A lista diz "não informado"; o detalhe, lido antes de mudar o status, traz o valor.
  @override
  Future<UsuarioBusca> detalheUsuario(String usuarioId) async {
    if (falhaDetalhe) throw const ErroApi('Falhou (exemplo)');
    final u = await super.detalheUsuario(usuarioId);
    return UsuarioBusca(id: u.id, nome: u.nome, tipo: u.tipo, status: u.status, travaFraudeVigente: trava);
  }
}

Future<void> _abrirStatus(WidgetTester tester, ApiFake api) async {
  await abrirPainel(tester, papel: 'administrador', api: api, secao: 'busca');
  await tester.tap(find.text('Paulo Lima').first);
  await tester.pumpAndSettle();
  await rolarListaAte(tester, find.text('Alterar status'));
  await _clicar(tester, find.text('Alterar status').first);
  await _clicar(tester, _noDialogo(_contem('Restrito (atividades')).first);
  await tester.tap(_contem('Ativo (acesso normal)').last);
  await tester.pumpAndSettle();
}

Future<void> _abrirTrava(WidgetTester tester, ApiFake api) async {
  await abrirPainel(tester, papel: 'seguranca', api: api, secao: 'risco');
  await tester.tap(find.textContaining(RegExp(r'^Todos \d+$')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Troca de chave PIX').first);
  await tester.pumpAndSettle();
  await rolarListaAte(tester, find.text('Registrar trava'));
  await _clicar(tester, find.text('Registrar trava'));
  await _clicar(tester, _noDialogo(find.text('Por fraude')));
}

Future<void> _dias(WidgetTester tester, String rotulo, String valor) async {
  final campo = _noDialogo(find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, valor);
  await tester.pump();
}

void main() {
  for (final (nome, trava, trecho) in <(String, bool?, String)>[
    ('com trava', true, 'Há trava por fraude em vigor.'),
    ('sem trava', false, 'Não há trava por fraude em vigor.'),
    ('não informado', null, 'não foi informado se há uma'),
  ]) {
    testWidgets('risco, $nome: aviso e texto do destravar', (tester) async {
      await abrirPainel(tester, papel: 'administrador', api: _Api(trava: trava), secao: 'risco');
      await tester.tap(find.text('Troca de chave PIX').first);
      await tester.pumpAndSettle();
      expect(_contem(trecho), findsWidgets);
      await rolarListaAte(tester, find.text('Remover trava'));
      await _clicar(tester, find.text('Remover trava'));
      expect(_noDialogo(_contem(avisoAoDestravar(trava))), findsOneWidget);
    });
  }

  testWidgets('busca: com trava vigente, o aviso afirma antes de reativar', (tester) async {
    await _abrirStatus(tester, _Api(trava: true));
    expect(_contem(avisoAoAtivar(true)!), findsOneWidget);
  });

  testWidgets('busca: sem trava vigente, não avisa', (tester) async {
    await _abrirStatus(tester, _Api(trava: false));
    expect(_contem(kFimDaTravaAoAtivar), findsNothing);
  });

  testWidgets('busca: leitura falhou = não informado, aviso condicional', (tester) async {
    await _abrirStatus(tester, _Api(trava: false, falhaDetalhe: true));
    expect(_contem(kFimDaTravaAoAtivar), findsOneWidget);
    expect(_contem('Há trava por fraude em vigor.'), findsNothing);
  });

  testWidgets('risco: o prazo do servidor limita os dias da trava por fraude', (tester) async {
    final api = ApiFake()..prazoMaximoTrava = 15;
    await _abrirTrava(tester, api);
    expect(api.leiturasDoPrazo, 1);
    await _dias(tester, 'Duração da trava em dias', '16');
    expect(find.text('Use de 1 a 15 dias'), findsOneWidget);
    await _dias(tester, 'Duração da trava em dias', '15');
    expect(find.text('Use de 1 a 15 dias'), findsNothing);
  });

  testWidgets('risco: se a leitura do prazo falhar, continua 1 a 90', (tester) async {
    await _abrirTrava(tester, ApiFake()..prazoMaximoTrava = null);
    await _dias(tester, 'Duração da trava em dias', '90');
    expect(_contem('Use de 1 a'), findsNothing);
    await _dias(tester, 'Duração da trava em dias', '91');
    expect(find.text('Use de 1 a 90 dias'), findsOneWidget);
  });

  for (final (nome, prazo, valor, erro) in <(String, int?, String, String?)>[
    ('usa o prazo do servidor', 15, '16', 'Use de 1 a 15 dias'),
    ('falha mantém 1 a 3650', null, '400', null),
  ]) {
    testWidgets('medidas: $nome', (tester) async {
      await abrirPainel(tester, papel: 'mediador', api: ApiFake()..prazoMaximoTrava = prazo, secao: 'medidas');
      await tester.tap(find.text('Aplicar medida'));
      await tester.pumpAndSettle();
      await _clicar(tester, find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.text('Trava de saques').last);
      await tester.pumpAndSettle();
      await _clicar(tester, _noDialogo(find.text('Por fraude')));
      await _dias(tester, 'Duração em dias', valor);
      expect(_contem('Use de 1 a'), erro == null ? findsNothing : findsOneWidget);
      if (erro != null) expect(find.text(erro), findsOneWidget);
    });
  }

  test('API: null ou ausente = não informado; lê o prazo máximo', () async {
    Object? valor;
    var enviarCampo = true;
    final caminhos = <String>[];
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        caminhos.add(r.url.path);
        final usuario = {'id': 'u1', if (enviarCampo) 'trava_fraude_vigente': valor};
        final Object corpo = switch (r.url.path) {
          '/v1/admin/medidas/trava-fraude' => {'prazo_maximo_dias': 21},
          '/v1/admin/risco/alertas' => [
              {'id': 'a1', 'tipo': 't', 'severidade': 'alta', 'detalhes': 'd', ...usuario, 'id_extra': 1}
            ],
          _ => usuario,
        };
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    for (final v in [true, false, null]) {
      valor = v;
      expect((await api.detalheUsuario('u1')).travaFraudeVigente, v);
      expect((await api.listarAlertasRisco()).single.travaFraudeVigente, v);
    }
    enviarCampo = false;
    expect((await api.detalheUsuario('u1')).travaFraudeVigente, isNull);
    expect(await api.prazoMaximoTravaFraude(), 21);
    expect(caminhos.last, '/v1/admin/medidas/trava-fraude');
  });
}
