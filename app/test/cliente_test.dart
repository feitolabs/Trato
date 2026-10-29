import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/cliente/buscar_tela.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/cliente/dados_exemplo.dart';
import 'package:trato/telas/cliente/inicio_tela.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/em_breve_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 1600),
  double escala = 1.0,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: tela,
    ),
  );
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  group('casca', () {
    testWidgets('começa no Início e as abas trocam de tela', (tester) async {
      await _abrir(tester, const CascaClienteTela());

      expect(find.byType(InicioTela), findsOneWidget);
      expect(find.text('O que você precisa hoje?'), findsOneWidget);

      await tester.tap(find.text('Buscar').last);
      await tester.pumpAndSettle();
      expect(find.text('3 profissionais perto de Savassi'), findsOneWidget);

      await tester.tap(find.text('Pedidos'));
      await tester.pumpAndSettle();
      expect(find.text('Seus pedidos'), findsOneWidget);

      await tester.tap(find.text('Mensagens'));
      await tester.pumpAndSettle();
      expect(find.byType(MensagensTela), findsOneWidget);
    });

    testWidgets('campo Buscar do Início leva à aba Buscar', (tester) async {
      await _abrir(tester, const CascaClienteTela());

      await tester.tap(find.text('Serviço ou profissional'));
      await tester.pumpAndSettle();

      expect(find.text('3 profissionais perto de Savassi'), findsOneWidget);
    });
  });

  group('início', () {
    testWidgets('mostra os textos do protótipo', (tester) async {
      await _abrir(tester, const CascaClienteTela());

      expect(find.text('Olá, Mariana'), findsOneWidget);
      expect(find.text('Descreva o problema'), findsOneWidget);
      expect(find.text('Pedir orçamento'), findsOneWidget);
      expect(find.text('Troca de tomadas e chuveiro'), findsOneWidget);
      expect(find.text('3 orçamentos novos'), findsOneWidget);
      for (final c in categorias) {
        expect(find.text(c.nome), findsOneWidget);
      }
      expect(find.text('Pintura da sala'), findsOneWidget);
      expect(find.text('Garantia ativa até 31/12/2026'), findsOneWidget);
    });

    testWidgets('Pedir orçamento abre "em breve"', (tester) async {
      await _abrir(tester, const CascaClienteTela());

      await _tocar(tester, find.text('Pedir orçamento'));

      expect(find.byType(EmBreveTela), findsOneWidget);
    });
  });

  group('buscar', () {
    testWidgets('lista os 3 profissionais do protótipo', (tester) async {
      await _abrir(tester, const BuscarTela());

      expect(find.text('Carlos Mendes'), findsOneWidget);
      expect(find.text('André Lopes'), findsOneWidget);
      expect(find.text('Joana Ribeiro'), findsOneWidget);
      expect(find.text('4,9'), findsOneWidget);
      expect(find.text('2,1 km'), findsOneWidget);
      expect(find.text('Elétrica · 71 serviços · resp. em 1 h'), findsOneWidget);
    });

    testWidgets('filtros reduzem a lista e atualizam a contagem', (tester) async {
      await _abrir(tester, const BuscarTela());

      await tester.tap(find.text('Atende hoje'));
      await tester.pump();

      expect(find.text('1 profissional perto de Savassi'), findsOneWidget);
      expect(find.text('André Lopes'), findsNothing);

      await tester.tap(find.text('Atende hoje'));
      await tester.pump();
      expect(find.text('3 profissionais perto de Savassi'), findsOneWidget);
    });

    testWidgets('Mapa troca a lista por um espaço reservado', (tester) async {
      await _abrir(tester, const BuscarTela());

      await tester.tap(find.text('Mapa'));
      await tester.pump();

      expect(find.text('Mapa em breve'), findsOneWidget);
      expect(find.text('Carlos Mendes'), findsNothing);

      await tester.tap(find.text('Lista'));
      await tester.pump();
      expect(find.text('Carlos Mendes'), findsOneWidget);
    });

    testWidgets('Carlos abre o perfil', (tester) async {
      await _abrir(tester, const BuscarTela());

      await _tocar(tester, find.text('Carlos Mendes'));

      expect(find.byType(PerfilProfissionalTela), findsOneWidget);
    });

    testWidgets('quem ainda não tem perfil no protótipo abre "em breve"', (tester) async {
      await _abrir(tester, const BuscarTela());

      await _tocar(tester, find.text('André Lopes'));

      expect(find.byType(EmBreveTela), findsOneWidget);
    });
  });

  group('perfil do profissional', () {
    testWidgets('mostra nota, serviços, verificações, trabalhos e avaliações', (tester) async {
      await _abrir(tester, PerfilProfissionalTela(profissional: profissionais.first));

      expect(find.text('Carlos Mendes'), findsOneWidget);
      expect(find.text('Verificado Plus'), findsOneWidget);
      expect(find.textContaining('4,9', findRichText: true), findsOneWidget);
      expect(find.text('Serviços concluídos'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
      expect(find.text('Documento e selfie com prova de vida'), findsOneWidget);
      expect(find.text('[Foto]'), findsNWidgets(3));
      expect(find.text('Ver as 64'), findsOneWidget);
    });

    testWidgets('botão traz o primeiro nome e abre "em breve"', (tester) async {
      await _abrir(tester, PerfilProfissionalTela(profissional: profissionais.first));

      await _tocar(tester, find.text('Pedir orçamento ao Carlos'));

      expect(find.byType(EmBreveTela), findsOneWidget);
    });
  });

  // Qualquer estouro de layout faz o teste falhar.
  final telas = <String, Widget Function()>{
    'casca/início': () => const CascaClienteTela(),
    'casca/buscar': () => const CascaClienteTela(abaInicial: 1),
    'perfil': () => PerfilProfissionalTela(profissional: profissionais.first),
  };
  const tamanhos = [Size(320, 568), Size(390, 844), Size(768, 1024)];
  for (final MapEntry(key: nome, value: criar) in telas.entries) {
    for (final tamanho in tamanhos) {
      for (final escala in [1.0, Responsivo.escalaFonteMaxima]) {
        testWidgets('sem estouro — $nome ${tamanho.width.toInt()} fonte x$escala', (tester) async {
          await _abrir(tester, criar(), tamanho: tamanho, escala: escala);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Rola até o fim: o que aparece depois da primeira tela também não pode estourar.
          final rolagem = find.byType(SingleChildScrollView);
          if (rolagem.evaluate().isNotEmpty) {
            await tester.drag(rolagem.first, const Offset(0, -3000));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
}
