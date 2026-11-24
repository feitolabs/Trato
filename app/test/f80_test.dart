import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/cliente/chips_categorias.dart';
import 'package:trato/telas/cliente/inicio_tela.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/busca/servico_fake.dart';

const _muitas =
    'Limpeza de estofados e caixa d\'água, Instalação de eletrodomésticos, Pisos e revestimentos, '
    'Mudança e frete, Montagem de móveis, Ar-condicionado, Pintura de interiores';

Future<void> _abrir(WidgetTester tester, Widget tela, {Size tamanho = const Size(390, 1800), double fonte = 1}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  group('C01: categorias em chips (até 3 + "+N")', () {
    test('descrição para leitor de tela: 3 nomes e "e mais N categorias"', () {
      expect(descricaoDeCategorias('Elétrica, Hidráulica'), 'Elétrica, Hidráulica');
      expect(descricaoDeCategorias('A, B, C, D'), 'A, B, C e mais 1 categoria');
      expect(descricaoDeCategorias(_muitas), endsWith('e mais 4 categorias'));
      expect(nomesDeCategorias(' A ,, B '), ['A', 'B']);
    });

    testWidgets('mostra só 3 chips e um "+4" com o resto', (tester) async {
      await _abrir(tester, const Scaffold(body: ChipsCategorias(categorias: _muitas)));
      expect(find.text('Limpeza de estofados e caixa d\'água'), findsOneWidget);
      expect(find.text('Instalação de eletrodomésticos'), findsOneWidget);
      expect(find.text('Pisos e revestimentos'), findsOneWidget);
      expect(find.text('Mudança e frete'), findsNothing);
      expect(find.text('+4'), findsOneWidget);
    });

    testWidgets('até 3 categorias: sem "+N"', (tester) async {
      await _abrir(tester, const Scaffold(body: ChipsCategorias(categorias: 'Elétrica, Hidráulica')));
      expect(find.text('Elétrica'), findsOneWidget);
      expect(find.byKey(const ValueKey('mais-categorias')), findsNothing);
    });

    testWidgets('na busca: cartão com chips, sem estourar, e nota com vírgula para o leitor de tela',
        (tester) async {
      final semantica = tester.ensureSemantics();
      await _abrir(
        tester,
        const BuscaProfissionaisTela(servico: _ServicoUm(), termoInicial: 'tester'),
        fonte: 1.3,
        tamanho: const Size(360, 1800),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('+4'), findsOneWidget);
      expect(find.text('Mudança e frete'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'Tester P\., .*e mais 4 categorias, nota 4,8')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'nota 4\.8')), findsNothing);
      semantica.dispose();
    });
  });

  group('C02: títulos das categorias do Início em fonte 1,3x', () {
    final categorias = [
      const CategoriaServico('Ar-condicionado', Icons.ac_unit),
      const CategoriaServico('Câmeras e segurança', Icons.videocam),
      const CategoriaServico('Chaveiro', Icons.key),
      const CategoriaServico('Cortinas e persianas', Icons.blinds),
      const CategoriaServico('Elétrica', Icons.bolt),
      const CategoriaServico('Hidráulica', Icons.water),
      const CategoriaServico('Instalação de eletrodomésticos', Icons.kitchen),
    ];

    Future<void> abrirInicio(WidgetTester tester, double fonte) => _abrir(
          tester,
          InicioTela(
            aoBuscar: () {},
            dados: DadosInicio(nome: 'Tester', categorias: categorias),
          ),
          fonte: fonte,
          tamanho: const Size(390, 2400),
        );

    testWidgets('com a fonte ampliada são 3 por linha e os títulos usam até 2 linhas',
        (tester) async {
      await abrirInicio(tester, 1.3);
      expect(tester.takeException(), isNull);
      final ar = find.text('Ar-condicionado');
      expect(ar, findsOneWidget);
      final texto = tester.widget<Text>(ar);
      expect(texto.maxLines, 2);
      expect(texto.overflow, TextOverflow.ellipsis);
      // 3 por linha: Ar-condicionado, Câmeras e Chaveiro na mesma linha.
      final y1 = tester.getTopLeft(find.text('Ar-condicionado')).dy;
      final y2 = tester.getTopLeft(find.text('Câmeras e segurança')).dy;
      final y3 = tester.getTopLeft(find.text('Chaveiro')).dy;
      final y4 = tester.getTopLeft(find.text('Cortinas e persianas')).dy;
      expect((y1 - y2).abs(), lessThan(30));
      expect((y1 - y3).abs(), lessThan(30));
      expect(y4, greaterThan(y1 + 30)); // a quarta já está na linha de baixo
      // O título inteiro cabe em até 2 linhas sem reticências (largura do cartão basta).
      final largura = tester.getSize(find.text('Ar-condicionado')).width;
      final cartao = tester.getSize(find.ancestor(of: ar, matching: find.byType(InkWell)).first).width;
      expect(largura, lessThanOrEqualTo(cartao));
    });

    testWidgets('fonte normal continua com 4 por linha', (tester) async {
      await abrirInicio(tester, 1.0);
      final y1 = tester.getTopLeft(find.text('Ar-condicionado')).dy;
      final y4 = tester.getTopLeft(find.text('Cortinas e persianas')).dy;
      expect((y1 - y4).abs(), lessThan(30)); // a quarta na mesma linha
    });
  });
}

class _ServicoUm extends ServicoBuscaFake {
  const _ServicoUm();

  @override
  Future<List<Profissional>> buscar(String termo, {bool disponivelAgora = false}) async => const [
        Profissional(
          nome: 'Tester P.',
          iniciais: 'TP',
          verificacao: 'Verificado',
          especialidade: _muitas,
          servicosConcluidos: 3,
          nota: 4.8,
          distanciaKm: 2,
        ),
      ];
}
