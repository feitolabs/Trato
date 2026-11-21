import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

const _dados = DadosAvaliacao(
  nomeProfissional: 'Gabriel L.',
  valorLiberadoCentavos: 10000,
  criterios: ['Qualidade'],
  gorjetasCentavos: [],
  gorjetaDisponivel: false,
);

Finder _chip(String e) => find.byKey(ValueKey('etiqueta-$e'));

bool _marcado(WidgetTester tester, String e) => tester.widget<FilterChip>(_chip(e)).selected;

Future<void> _tocar(WidgetTester tester, String e) async {
  await tester.ensureVisible(_chip(e));
  await tester.tap(_chip(e));
  await tester.pumpAndSettle();
}

Profissional _pro({List<EtiquetaTop> top = const [], List<String> etiquetasAv = const []}) =>
    Profissional(
      nome: 'Ana Lima',
      iniciais: 'AL',
      verificacao: 'Verificado',
      especialidade: 'Eletricista',
      servicosConcluidos: 8,
      nota: 4.8,
      distanciaKm: 2,
      detalhe: DetalhePerfil(
        noTratoDesde: 2026,
        totalAvaliacoes: 1,
        taxaConclusao: 96,
        respondeEm: '—',
        verificacoes: const [],
        etiquetasTop: top,
        avaliacoes: [
          Avaliacao(
            cliente: 'Maria',
            servico: 'Tomada',
            nota: 5,
            comentario: 'Ótimo!',
            detalhes: '',
            etiquetas: etiquetasAv,
          ),
        ],
      ),
    );

class _PerfilPublicoFake implements ServicoPerfilPublico {
  _PerfilPublicoFake(this.top);

  final List<EtiquetaTop> top;

  @override
  Future<PerfilPublico> carregarPerfil() async => PerfilPublico(
        nome: 'Ana Lima',
        iniciais: 'AL',
        categoria: 'Eletricista',
        verificacao: null,
        noTratoDesde: 2026,
        nota: 4.8,
        totalAvaliacoes: 1,
        servicosConcluidos: 8,
        sobre: 'Eletricista',
        cidade: 'BH',
        fotosPortfolio: 0,
        etiquetasTop: top,
        ultimasAvaliacoes: const [
          Avaliacao(
            cliente: 'Maria',
            servico: 'Tomada',
            nota: 5,
            comentario: 'Ótimo!',
            detalhes: '',
            etiquetas: ['Limpo', 'Educado'],
          ),
        ],
      );

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => const [];

  @override
  Future<bool> temPerfilProfissional() async => true;
}

void main() {
  group('F39 · avaliar com elogios ("O que foi bom?")', () {
    testWidgets('mostra os 6 chips da lista do backend, nenhum marcado', (tester) async {
      await _abrir(tester, const AvaliacaoTela(dados: _dados));
      expect(find.text('O que foi bom?'), findsOneWidget);
      for (final e in [
        'Pontual',
        'Limpo',
        'Explicou bem',
        'Preço justo',
        'Educado',
        'Caprichoso'
      ]) {
        expect(_chip(e), findsOneWidget);
        expect(_marcado(tester, e), isFalse);
      }
    });

    testWidgets('seleciona até 3; o 4º não seleciona e mostra aviso; desmarcar libera',
        (tester) async {
      await _abrir(tester, const AvaliacaoTela(dados: _dados));
      await _tocar(tester, 'Pontual');
      await _tocar(tester, 'Limpo');
      await _tocar(tester, 'Educado');
      expect(find.byKey(const Key('aviso-etiquetas')), findsNothing);

      await _tocar(tester, 'Caprichoso');
      expect(_marcado(tester, 'Caprichoso'), isFalse);
      expect(find.byKey(const Key('aviso-etiquetas')), findsOneWidget);
      expect(_marcado(tester, 'Pontual'), isTrue);

      await _tocar(tester, 'Limpo'); // desmarca
      expect(find.byKey(const Key('aviso-etiquetas')), findsNothing);
      await _tocar(tester, 'Caprichoso');
      expect(_marcado(tester, 'Caprichoso'), isTrue);
    });

    testWidgets('enviar leva as etiquetas escolhidas; sem nenhuma, vai vazio', (tester) async {
      final envios = <EnvioAvaliacao>[];
      await _abrir(
        tester,
        AvaliacaoTela(
          dados: _dados,
          notasIniciais: const [5],
          aoEnviar: (e) {
            envios.add(e);
            return false;
          },
        ),
      );
      await tester.tap(find.text('Enviar avaliação'));
      await tester.pumpAndSettle();
      expect(envios.single.etiquetas, isEmpty);

      await _tocar(tester, 'Explicou bem');
      await _tocar(tester, 'Preço justo');
      await tester.tap(find.text('Enviar avaliação'));
      await tester.pumpAndSettle();
      expect(envios.last.etiquetas, ['Explicou bem', 'Preço justo']);
    });

    Future<Map<String, dynamic>> post(List<String> etiquetas) async {
      Map<String, dynamic>? corpo;
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: SessaoTrato()..entrar('valor-de-teste'),
        cliente: MockClient((r) async {
          corpo = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'moedas_ganhas': 50}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await RepositorioPedidosApi(api).avaliar(
        'p1',
        EnvioAvaliacao(
          notas: const [5],
          comentario: 'ok',
          gorjetaCentavos: 0,
          etiquetas: etiquetas,
        ),
      );
      return corpo!;
    }

    test('o POST da avaliação leva etiquetas (lista de textos)', () async {
      final corpo = await post(['Pontual', 'Limpo']);
      expect(corpo['etiquetas'], ['Pontual', 'Limpo']);
      expect(corpo['nota_geral'], 5);
    });

    test('sem etiquetas o POST segue igual, sem o campo', () async {
      final corpo = await post(const []);
      expect(corpo.containsKey('etiquetas'), isFalse);
      expect(corpo['nota_geral'], 5);
    });
  });

  group('F39 · perfil com elogios', () {
    test('etiquetas_top: lê o formato da API e ignora lixo sem quebrar', () {
      expect(EtiquetaTop.listaDeJson(null), isEmpty);
      expect(EtiquetaTop.listaDeJson('x'), isEmpty);
      expect(EtiquetaTop.listaDeJson(<Object>[]), isEmpty);
      final lista = EtiquetaTop.listaDeJson([
        {'etiqueta': 'Pontual', 'total': 12},
        {'etiqueta': 'Limpo'},
        'lixo',
        {'etiqueta': '', 'total': 3},
      ]);
      expect(lista, hasLength(1));
      expect(lista.single.etiqueta, 'Pontual');
      expect(lista.single.total, 12);
    });

    testWidgets('perfil do profissional (visão cliente): top em chips e etiquetas do cartão',
        (tester) async {
      await _abrir(
        tester,
        PerfilProfissionalTela(
          profissional: _pro(
            top: const [EtiquetaTop('Pontual', 12), EtiquetaTop('Limpo', 7)],
            etiquetasAv: const ['Pontual', 'Explicou bem'],
          ),
        ),
      );
      expect(find.text('Mais elogiado por'), findsOneWidget);
      expect(find.text('Pontual · 12'), findsOneWidget);
      expect(find.text('Limpo · 7'), findsOneWidget);
      // Cartão da avaliação mostra as etiquetas daquela avaliação.
      expect(find.text('Explicou bem'), findsOneWidget);
    });

    testWidgets('perfil sem etiquetas_top (backend antigo) não mostra nada e não quebra',
        (tester) async {
      await _abrir(tester, PerfilProfissionalTela(profissional: _pro()));
      expect(find.text('Mais elogiado por'), findsNothing);
      expect(find.byKey(const Key('etiquetas-top')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('perfil público do próprio profissional mostra o top e as etiquetas do cartão',
        (tester) async {
      await _abrir(
        tester,
        PerfilPublicoTela(
          servico: _PerfilPublicoFake(const [EtiquetaTop('Educado', 5)]),
        ),
      );
      expect(find.text('Educado · 5'), findsOneWidget);
      expect(find.text('Limpo'), findsOneWidget);
    });

    testWidgets('perfil público sem etiquetas_top: sem a seção', (tester) async {
      await _abrir(tester, PerfilPublicoTela(servico: _PerfilPublicoFake(const [])));
      expect(find.text('Mais elogiado por'), findsNothing);
    });
  });
}
