import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/tema/tema.dart';

const _texto = 'Costuma responder no mesmo dia';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

Profissional _pro(String? faixa) => Profissional(
      nome: 'Ana Lima',
      iniciais: 'AL',
      verificacao: 'Verificado',
      especialidade: 'Eletricista',
      servicosConcluidos: 8,
      nota: 4.8,
      distanciaKm: 2,
      detalhe: DetalhePerfil(
        noTratoDesde: 2026,
        totalAvaliacoes: 3,
        taxaConclusao: 96,
        verificacoes: const [],
        avaliacoes: const [],
        respondeEmFaixa: faixa,
      ),
    );

class _PerfilPublicoFake implements ServicoPerfilPublico {
  _PerfilPublicoFake(this.faixa);

  final String? faixa;

  @override
  Future<PerfilPublico> carregarPerfil() async => PerfilPublico(
        nome: 'Ana Lima',
        iniciais: 'AL',
        categoria: 'Eletricista',
        verificacao: null,
        noTratoDesde: 2026,
        nota: 4.8,
        totalAvaliacoes: 0,
        servicosConcluidos: 8,
        sobre: 'Eletricista',
        cidade: 'BH',
        fotosPortfolio: 0,
        ultimasAvaliacoes: const [],
        respondeEmFaixa: faixa,
      );

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => const [];

  @override
  Future<bool> temPerfilProfissional() async => true;
}

ClienteApi _api(Map<String, Object?> perfil) => ClienteApi(
      urlBase: 'https://api.teste/',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient((r) async {
        Object corpo = <Object>[];
        if (r.url.path == '/v1/profissionais/pro1') corpo = perfil;
        if (r.url.path == '/v1/me') corpo = {'id': 'pro1', 'nome': 'Ana Lima'};
        if (r.url.path == '/v1/profissional/perfil') corpo = <String, Object?>{};
        if (r.url.path.endsWith('/foto')) corpo = <String, Object?>{};
        return http.Response(
          jsonEncode(corpo),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

void main() {
  group('F41 · leitura de responde_em_faixa', () {
    test('só texto não vazio vale; o resto vira nulo sem quebrar', () {
      expect(DetalhePerfil.lerFaixaResposta('no mesmo dia'), 'no mesmo dia');
      expect(DetalhePerfil.lerFaixaResposta('  no mesmo dia '), 'no mesmo dia');
      expect(DetalhePerfil.lerFaixaResposta(null), isNull);
      expect(DetalhePerfil.lerFaixaResposta(''), isNull);
      expect(DetalhePerfil.lerFaixaResposta('   '), isNull);
      expect(DetalhePerfil.lerFaixaResposta(5), isNull);
      expect(DetalhePerfil.lerFaixaResposta(['x']), isNull);
    });

    Map<String, Object?> perfilApi(Map<String, Object?> extra) => {
          'id': 'pro1',
          'nome': 'Ana Lima',
          'nivel_verificacao': 'verificado',
          'avaliacoes': <Object>[],
          'categorias': <Object>[],
          ...extra,
        };

    test('perfil do cliente: lê o campo da API (presente, nulo, ausente, tipo errado)', () async {
      Future<String?> ler(Map<String, Object?> extra) async {
        final p = await RepositorioCatalogoApi(_api(perfilApi(extra))).perfil('pro1');
        return p.detalhe!.respondeEmFaixa;
      }

      expect(await ler({'responde_em_faixa': 'no mesmo dia'}), 'no mesmo dia');
      expect(await ler({'responde_em_faixa': null}), isNull);
      expect(await ler({}), isNull); // backend antigo
      expect(await ler({'responde_em_faixa': 42}), isNull);
    });

    test('perfil público do próprio profissional: lê o campo da API', () async {
      Future<String?> ler(Map<String, Object?> extra) async {
        final p = await ServicoPerfilPublicoApi(_api(perfilApi(extra))).carregarPerfil();
        return p.respondeEmFaixa;
      }

      expect(await ler({'responde_em_faixa': 'no mesmo dia'}), 'no mesmo dia');
      expect(await ler({'responde_em_faixa': null}), isNull);
      expect(await ler({}), isNull);
    });
  });

  group('F41 · selo "Costuma responder no mesmo dia"', () {
    testWidgets('perfil visto pelo cliente: com valor mostra o texto fixo', (tester) async {
      await _abrir(tester, PerfilProfissionalTela(profissional: _pro('no mesmo dia')));
      expect(find.text(_texto), findsOneWidget);
      expect(find.textContaining('Responde em'), findsNothing);
    });

    for (final faixa in <String?>[null, '', '   ']) {
      testWidgets('perfil visto pelo cliente: "${faixa ?? 'nulo'}" não mostra nada',
          (tester) async {
        await _abrir(tester, PerfilProfissionalTela(profissional: _pro(faixa)));
        expect(find.text(_texto), findsNothing);
        expect(find.byKey(const Key('selo-resposta-real')), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('perfil público do próprio profissional: com valor mostra', (tester) async {
      await _abrir(tester, PerfilPublicoTela(servico: _PerfilPublicoFake('no mesmo dia')));
      expect(find.text(_texto), findsOneWidget);
    });

    testWidgets('perfil público do próprio profissional: sem valor não mostra nada',
        (tester) async {
      await _abrir(tester, PerfilPublicoTela(servico: _PerfilPublicoFake(null)));
      expect(find.text(_texto), findsNothing);
      expect(find.byKey(const Key('selo-resposta-real')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
