import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/telas/incidentes_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 9.5: sinais antifraude são para análise, não prova.
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Incidente _inc(List<String> sinais) => Incidente(
      id: 'inc-9',
      protocolo: 'INC-EXEMPLO-9',
      canal: 'app',
      tipo: 'pessoa_diferente',
      descricao: 'Exemplo',
      status: 'aberto',
      pedidoId: 'ped-1',
      abertoEm: DateTime(2026, 11, 20),
      cautelaAte: DateTime(2099),
      sinaisAntifraude: sinais,
    );

Future<void> _abrir(WidgetTester tester, List<String> sinais) => abrirPainel(tester,
    papel: 'seguranca', api: ApiFake()..incidentes = [_inc(sinais)], secao: 'incidentes', largura: 1400);

void main() {
  test('texto por código, com genérico para o desconhecido', () {
    expect(textoDoSinalAntifraude('relato_repetido_do_cliente:3'), contains('em 3 pedidos'));
    expect(textoDoSinalAntifraude('relato_durante_espera_de_ausencia'), contains('tempo de espera'));
    for (final c in ['codigo_novo', 'relato_repetido_do_cliente:x']) {
      expect(textoDoSinalAntifraude(c), contains('outro ponto para conferir'));
    }
  });

  testWidgets('lista e detalhe mostram o alerta sem afirmar fraude', (tester) async {
    await _abrir(tester, ['relato_repetido_do_cliente:2', 'codigo_novo']);
    // Um no cartão da lista e o título do aviso no detalhe.
    expect(find.text('Sinal para análise'), findsOneWidget);
    expect(_contem('Sinal para análise.'), findsOneWidget);
    expect(_contem('em 2 pedidos'), findsOneWidget);
    expect(_contem('outro ponto para conferir'), findsOneWidget);
    expect(_contem(kSinalNaoEProva), findsOneWidget);
    expect(_contem('codigo_novo'), findsNothing);
  });

  testWidgets('sem sinais nada aparece', (tester) async {
    await _abrir(tester, const []);
    expect(_contem('Sinal para análise'), findsNothing);
    expect(_contem(kSinalNaoEProva), findsNothing);
  });

  test('API: lê a lista; ausente = vazia', () async {
    Object? sinais = ['relato_durante_espera_de_ausencia'];
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
              'tipo': 'pessoa_diferente',
              'status': 'aberto',
              'aberto_em': '2026-11-20T10:00:00Z',
              'cautela_ate': '2026-11-21T10:00:00Z',
              'sinais_antifraude': ?sinais,
            })),
            200);
      }),
    );
    await api.entrar('a@teste.local', 'senha-de-teste');
    expect((await api.obterIncidente('i1')).sinaisAntifraude, ['relato_durante_espera_de_ausencia']);
    sinais = null;
    expect((await api.obterIncidente('i1')).sinaisAntifraude, isEmpty);
  });
}
