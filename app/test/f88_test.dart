import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/conta/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/telas/onboarding/onboarding_tela.dart';
import 'package:trato/telas/profissional/detalhe_orcamento_enviado_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_catalogo_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

Future<void> _janela(WidgetTester t, {double fonte = 1}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

/// Catálogo de teste: cada profissional atua só nas categorias listadas.
class _CatalogoDele extends RepositorioCatalogoFake {
  _CatalogoDele(this.ids);
  final Map<String, List<String>> ids;

  @override
  Future<Profissional> perfil(String profissionalId) async => Profissional(
        id: profissionalId,
        nome: 'Carlos',
        iniciais: 'C',
        verificacao: '',
        especialidade: '',
        servicosConcluidos: 0,
        nota: 0,
        distanciaKm: 0,
        categoriasIds: ids[profissionalId] ?? const [],
      );
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('5. E-mail só em Dados pessoais', () {
    for (final fonte in [1.0, 1.3]) {
      testWidgets(
          'Configurações do cliente não repete "E-mail e senha" (x$fonte)',
          (t) async {
        await _janela(t, fonte: fonte);
        late BuildContext ctx;
        await t.pumpWidget(_app(Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })));
        RotasTrato.abrirConfiguracoes(ctx, profissional: false);
        await t.pumpAndSettle();
        expect(find.text('Dados pessoais'), findsOneWidget);
        expect(find.text('E-mail e senha'), findsNothing);

        await t.tap(find.text('Dados pessoais'));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
            find.byKey(const Key('botao-alterar-credenciais')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Alterar e-mail ou senha'), findsOneWidget);
      });
    }
  });

  group('6. Martelo na escolha de perfil', () {
    testWidgets('"Quero trabalhar" usa o martelo, não a caneta', (t) async {
      await _janela(t);
      await t.pumpWidget(_app(const EscolhaPerfilTela()));
      expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('7. Onboarding com o Tratinho', () {
    for (final fonte in [1.0, 1.3]) {
      testWidgets('o 3º slide mostra o mascote (x$fonte)', (t) async {
        await _janela(t, fonte: fonte);
        await t.pumpWidget(_app(const OnboardingTela()));
        for (var i = 0; i < 2; i++) {
          await t.tap(find.text('Próximo'));
          await t.pumpAndSettle();
        }
        expect(find.text('3 DE 3'), findsOneWidget);
        expect(find.bySemanticsLabel('Tratinho, o mascote do Trato, acenando'),
            findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('8. Chamar de novo só com as categorias do profissional', () {
    Future<void> chamar(WidgetTester t, Map<String, List<String>> ids) async {
      RotasTrato.repos = repositoriosDemo(catalogo: _CatalogoDele(ids));
      await t.pumpWidget(_app(Builder(
        builder: (c) => TextButton(
          onPressed: () => RotasTrato.chamarDeNovo(c,
              const FavoritoConta(profissionalId: 'p1', nome: 'Carlos Pintor')),
          child: const Text('chamar'),
        ),
      )));
      await t.tap(find.text('chamar'));
      await t.pumpAndSettle();
    }

    testWidgets('duas categorias: a escolha mostra só as dele', (t) async {
      await _janela(t);
      await chamar(t, {
        'p1': ['eletrica', 'pintura']
      });
      expect(find.text('Que serviço você precisa?'), findsOneWidget);
      expect(find.text('Elétrica'), findsOneWidget);
      expect(find.text('Pintura'), findsOneWidget);
      expect(find.text('Hidráulica'), findsNothing);
    });

    testWidgets('uma categoria: vai direto ao pedido', (t) async {
      await _janela(t);
      await chamar(t, {
        'p1': ['pintura']
      });
      expect(find.text('Que serviço você precisa?'), findsNothing);
      expect(find.textContaining('Pedido direto para Carlos Pintor'),
          findsOneWidget);
    });

    testWidgets('servidor antigo (sem categorias): mostra todas', (t) async {
      await _janela(t);
      await chamar(t, {});
      expect(find.text('Que serviço você precisa?'), findsOneWidget);
      expect(find.text('Hidráulica'), findsOneWidget);
    });
  });

  group('10. Garantia mínima do CDC', () {
    Future<void> abrir(WidgetTester t,
        {int minima = 30, int inicial = 90, double fonte = 1}) async {
      await _janela(t, fonte: fonte);
      await t.pumpWidget(_app(CalculadoraOrcamentoTela(
        servico: ServicoOrcamentoFake(),
        tituloPedido: 'Trocar tomada',
        garantiaInicialDias: inicial,
        garantiaMinimaDias: minima,
      )));
      await t.pumpAndSettle();
    }

    Future<List<String>> opcoes(WidgetTester t) async {
      final campo = find.text('Garantia');
      await t.ensureVisible(campo.first);
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<int>).first);
      await t.pumpAndSettle();
      return [
        for (final w in t.widgetList<Text>(find.textContaining(' dias')))
          if (RegExp(r'^\d+ dias$').hasMatch(w.data ?? '')) w.data!,
      ];
    }

    for (final fonte in [1.0, 1.3]) {
      testWidgets('padrão 30: não oferece menos que 30 (x$fonte)', (t) async {
        await abrir(t, fonte: fonte);
        final lista = await opcoes(t);
        expect(lista.toSet(), containsAll(['30 dias', '60 dias', '90 dias']));
        expect(lista.any((s) => s == '7 dias'), isFalse);
      });
    }

    testWidgets('durável: o mínimo é 90 e nada abaixo é oferecido', (t) async {
      await abrir(t, minima: 90, inicial: 30);
      final lista = await opcoes(t);
      expect(lista.toSet(), {'90 dias'});
    });

    testWidgets('garantia antiga abaixo do mínimo fica sem escolha', (t) async {
      await abrir(t, inicial: 7);
      expect(find.text('Escolha'), findsOneWidget);
      expect(find.text('7 dias'), findsNothing);
    });
  });

  group('9. Caixas vazias e desalinhadas', () {
    testWidgets(
        'onboarding: o ícone vai num selo compacto, não numa caixa de 260 px',
        (t) async {
      await _janela(t);
      await t.pumpWidget(_app(const OnboardingTela()));
      final caixa = t.getSize(find.byIcon(Icons.format_list_bulleted));
      final selo = t.getSize(find
          .ancestor(
              of: find.byIcon(Icons.format_list_bulleted),
              matching: find.byType(Container))
          .first);
      expect(caixa.width, lessThanOrEqualTo(112));
      expect(selo.height, lessThan(130));
    });

    for (final fonte in [1.0, 1.3]) {
      testWidgets(
          'orçamento enviado: todos os cartões ocupam a largura toda (x$fonte)',
          (t) async {
        await _janela(t, fonte: fonte);
        await t.pumpWidget(_app(const DetalheOrcamentoEnviadoTela(
          detalhe: DetalheOrcamentoEnviado(
            orcamentoId: 'o1',
            pedidoId: 'p1',
            tituloPedido: 'Trocar tomada',
            versao: 1,
            situacao: 'enviado',
            valorCentavos: 35000,
            foraDoEscopo: 'Fornecimento de disjuntor geral',
            observacoes: 'Levar escada',
          ),
        )));
        await t.pumpAndSettle();
        final largura = t.getSize(find.byType(Scaffold).first).width;
        for (final titulo in [
          'Valor proposto ao cliente',
          'Fora do escopo',
          'Observações'
        ]) {
          final cartao = find.ancestor(
              of: find.text(titulo), matching: find.byType(CartaoTrato));
          expect(t.getSize(cartao.first).width, greaterThan(largura - 80),
              reason: titulo);
        }
      });
    }
  });
}
