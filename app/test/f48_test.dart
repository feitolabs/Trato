import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';

ClienteApi _apiComAvaliacoes(List<Map<String, Object?>> avaliacoes) => ClienteApi(
      urlBase: 'https://api.teste/',
      sessao: SessaoTrato()..entrar('token'),
      cliente: MockClient((r) async {
        Object corpo = <Object>[];
        if (r.url.path == '/v1/profissionais/pro1') {
          corpo = {
            'id': 'pro1',
            'nome': 'Ana Lima',
            'nota_publica': 4.8,
            'servicos_concluidos': 5,
            'avaliacoes': avaliacoes,
            'portfolio': <Object>[],
            'regioes': <Object>[],
          };
        } else if (r.url.path == '/v1/me') {
          corpo = {'id': 'pro1', 'nome': 'Ana Lima', 'nota_publica': 4.8, 'servicos_concluidos': 5};
        } else if (r.url.path == '/v1/profissional/perfil') {
          corpo = <String, Object?>{'categorias': <Object>[], 'regioes': <Object>[]};
        } else if (r.url.path.endsWith('/foto')) {
          corpo = <String, Object?>{};
        }
        return http.Response(
          jsonEncode(corpo),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

void main() {
  final avaliacoesJson = <Map<String, Object?>>[
    {
      'id': 'a1',
      'cliente_nome': 'João',
      'nota_geral': 5,
      'nota_decimal': 4.8,
      'comentario': 'Ótimo'
    },
    {'id': 'a2', 'cliente_nome': 'Maria', 'nota_geral': 5, 'comentario': 'Sem decimal'},
    {
      'id': 'a3',
      'cliente_nome': 'Lucas',
      'nota_geral': 4,
      'nota_decimal': null,
      'comentario': 'Nulo'
    },
    {
      'id': 'a4',
      'cliente_nome': 'Eva',
      'nota_geral': 5,
      'nota_decimal': 'invalido',
      'comentario': 'Tipo'
    },
  ];

  group('F48 · leitura de nota_decimal nas avaliações recebidas', () {
    test(
        'RepositorioCatalogoApi.detalhe usa nota_decimal quando numérica e faz fallback para nota_geral',
        () async {
      final api = _apiComAvaliacoes(avaliacoesJson);
      final pro = await RepositorioCatalogoApi(api).perfil('pro1');
      expect(pro.detalhe!.avaliacoes.map((a) => a.nota).toList(), [4.8, 5.0, 4.0, 5.0]);
    });

    test('ServicoPerfilPublicoApi usa nota_decimal quando numérica e faz fallback para nota_geral',
        () async {
      final api = _apiComAvaliacoes(avaliacoesJson);
      final perfil = await ServicoPerfilPublicoApi(api).carregarPerfil();
      expect(perfil.ultimasAvaliacoes.map((a) => a.nota).toList(), [4.8, 5.0, 4.0, 5.0]);

      final todas = await ServicoPerfilPublicoApi(api).carregarAvaliacoes();
      expect(todas.map((a) => a.nota).toList(), [4.8, 5.0, 4.0, 5.0]);
    });
  });
}
