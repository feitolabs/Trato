import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

/// Termos 6.9: compensação criada pelo estorno de material contestado (sem disputa).
const _rotulo = 'Estorno de material contestado';

/// A API de verdade lê a resposta; a linha vem com `disputa_id` nulo, como no banco.
Future<PaginaRemota<Compensacao>> _lerDoServidor() async {
  final api = ApiAdminHttp(
    urlApi: 'http://api.teste',
    urlSupabase: 'http://supa.teste',
    chaveAnonSupabase: 'anon',
    cliente: MockClient((r) async {
      if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
      if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"administrador"}', 200);
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'itens': [
              {
                'id': 'c1',
                'pedido_id': 'ped-1',
                'disputa_id': null,
                'origem': 'nota_material_contestacao',
                'valor_centavos': 10000,
                'compensado_centavos': 2500,
                'restante_centavos': 7500,
                'motivo': 'Motivo de exemplo',
                'status': 'aberta',
                'criada_em': '2026-11-28T10:00:00Z',
                'avisado_em': '2026-11-28T11:00:00Z',
              }
            ],
            'total': 1,
          })),
          200);
    }),
  );
  await api.entrar('a@teste.local', 'senha-de-teste');
  return api.listarCompensacoes();
}

class _Api extends ApiFake {
  _Api(this.pagina);
  final PaginaRemota<Compensacao> pagina;

  @override
  Future<PaginaRemota<Compensacao>> listarCompensacoes(
          {String? profissionalId,
          String? pedidoId,
          String? status,
          bool revisaoPendente = false,
          int deslocamento = 0,
          int limite = 50}) async =>
      pagina;
}

void main() {
  test('API lê compensação de material com disputa_id nulo', () async {
    final c = (await _lerDoServidor()).itens.single;
    expect(c.origem, 'nota_material_contestacao');
    expect(c.valorCentavos, 10000);
    expect(c.restanteCentavos, 7500);
  });

  for (final largura in [360.0, 1100.0]) {
    testWidgets('detalhe mostra a origem com rótulo claro em ${largura.toInt()} px', (tester) async {
      final pagina = (await tester.runAsync(_lerDoServidor))!;
      await abrirPainel(tester, api: _Api(pagina), largura: largura);
      if (largura < 600) {
        await tester.tap(find.byKey(const ValueKey('menu-mais')));
        await tester.pumpAndSettle();
        await tocarNoMais(tester, 'compensacoes');
      } else {
        await irPara(tester, 'compensacoes');
      }
      await tester.tap(find.textContaining('Pedido ped-1').first);
      await tester.pumpAndSettle();
      final rotulo = find.textContaining(_rotulo, findRichText: true);
      await rolarListaAte(tester, rotulo);
      expect(rotulo, findsOneWidget);
      expect(find.textContaining('nota_material_contestacao', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
