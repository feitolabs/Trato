// FL-RESPOSTA-12.7: cliente vê avaliações recebidas (GET /v1/me/avaliacoes/recebidas) e responde.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_publico/avaliacoes_recebidas_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';

import 'apoio/fontes.dart';

ClienteApi _apiSimulado(Future<http.Response> Function(http.Request) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient(responder),
    );

http.Response _json(Object corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _ServicoClienteFake implements ServicoPerfilPublico, RespostaAvaliacao {
  _ServicoClienteFake(this.lista);

  List<Avaliacao> lista;
  final List<(String, String)> enviadas = [];

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => lista;

  @override
  Future<String?> responderAvaliacao(String avaliacaoId, String resposta) async {
    enviadas.add((avaliacaoId, resposta));
    lista = [
      for (final a in lista)
        if (a.id == avaliacaoId)
          Avaliacao(
            id: a.id,
            cliente: a.cliente,
            servico: a.servico,
            nota: a.nota,
            comentario: a.comentario,
            detalhes: a.detalhes,
            resposta: resposta,
          )
        else
          a,
    ];
    return resposta;
  }

  @override
  Future<PerfilPublico> carregarPerfil() => throw UnimplementedError();

  @override
  Future<bool> temPerfilProfissional() async => false;
}

void main() {
  setUpAll(carregarFontesTrato);

  group('RepositorioPerfilApi — avaliações recebidas e resposta (12.7)', () {
    test('lê GET /v1/me/avaliacoes/recebidas e envia POST /v1/avaliacoes/{id}/responder', () async {
      final requisicoes = <http.Request>[];
      final api = _apiSimulado((req) async {
        requisicoes.add(req);
        if (req.method == 'GET' && req.url.path == '/v1/me/avaliacoes/recebidas') {
          return _json([
            {
              'id': 'av-1',
              'nota_geral': 5,
              'nota_decimal': 5.0,
              'criterios': null,
              'comentario': 'Cliente pontual e organizado.',
              'resposta': null,
              'etiquetas': [],
              'criada_em': '2026-11-27T18:00:00Z',
              'cliente_nome': 'Carlos S.',
              'categoria': 'Elétrica',
            },
            {
              'id': 'av-2',
              'nota_geral': 4,
              'comentario': 'Tudo certo.',
              'resposta': 'Obrigado pelo atendimento!',
              'etiquetas': [],
              'criada_em': '2026-11-20T12:00:00Z',
              'cliente_nome': null,
              'categoria': null,
            },
          ]);
        }
        if (req.method == 'POST' && req.url.path == '/v1/avaliacoes/av-1/responder') {
          final corpo = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'id': 'av-1', 'resposta': corpo['resposta']});
        }
        return _json({}, 404);
      });

      final repo = RepositorioPerfilApi(api);
      final lista = await repo.avaliacoesRecebidas();
      expect(lista, hasLength(2));
      expect(lista[0].id, 'av-1');
      expect(lista[0].cliente, 'Carlos S.');
      expect(lista[0].servico, contains('Elétrica'));
      expect(lista[0].comentario, 'Cliente pontual e organizado.');
      expect(lista[0].resposta, isNull);
      expect(lista[1].cliente, 'Profissional');
      expect(lista[1].resposta, 'Obrigado pelo atendimento!');

      final resp = await repo.responderAvaliacao('av-1', '  Valeu, Carlos!  ');
      expect(resp, 'Valeu, Carlos!');
      final post = requisicoes.last;
      expect(post.method, 'POST');
      expect(post.url.path, '/v1/avaliacoes/av-1/responder');
      expect(jsonDecode(post.body), {'resposta': 'Valeu, Carlos!'});
    });

    test('soNoPerfilParaTeste mantém Avaliações recebidas no perfil do cliente', () {
      const perfil = PerfilCliente(
        nome: 'Ana',
        iniciais: 'AN',
        resumo: 'Nota 4,9 como cliente · 3 serviços',
        grupos: [
          GrupoPerfil(
            titulo: 'CONTA',
            itens: [
              ItemPerfil(acao: AcaoPerfil.dadosPessoais, titulo: 'Dados pessoais'),
              ItemPerfil(acao: AcaoPerfil.avaliacoesRecebidas, titulo: 'Avaliações recebidas'),
            ],
          ),
        ],
      );
      final filtrado = RotasTrato.soNoPerfilParaTeste(perfil);
      expect(
        filtrado.grupos.single.itens.map((i) => i.acao),
        [AcaoPerfil.avaliacoesRecebidas],
      );
    });
  });

  group('AvaliacoesRecebidasTela — fluxo do cliente (12.7)', () {
    testWidgets('exibe resposta existente, permite responder sem resposta e recarrega', (t) async {
      final servico = _ServicoClienteFake([
        const Avaliacao(
          id: 'av-1',
          cliente: 'Carlos S.',
          servico: 'Elétrica',
          nota: 5,
          comentario: 'Ótimo cliente.',
          detalhes: '',
        ),
        const Avaliacao(
          id: 'av-2',
          cliente: 'Maria R.',
          servico: 'Hidráulica',
          nota: 4,
          comentario: 'Local organizado.',
          detalhes: '',
          resposta: 'Muito obrigado!',
        ),
      ]);

      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: AvaliacoesRecebidasTela(
            servico: servico,
            textoVazio:
                'Depois do primeiro serviço concluído, as avaliações recebidas aparecem aqui.',
            dicaResposta: 'Escreva sua resposta',
          ),
        ),
      );
      await t.pumpAndSettle();

      // Já respondida mostra a resposta e não tem botão Responder; sem resposta tem 1 botão.
      expect(find.textContaining('Muito obrigado!'), findsOneWidget);
      expect(find.text('Responder'), findsOneWidget);

      await t.tap(find.text('Responder'));
      await t.pumpAndSettle();

      expect(find.text('Escreva sua resposta'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('campo-resposta-avaliacao')),
        'Obrigado, Carlos!',
      );
      await t.tap(find.byKey(const ValueKey('botao-enviar-resposta')));
      await t.pumpAndSettle();

      expect(servico.enviadas, [('av-1', 'Obrigado, Carlos!')]);
      expect(find.textContaining('Obrigado, Carlos!'), findsOneWidget);
      expect(find.text('Responder'), findsNothing);
    });
  });
}
