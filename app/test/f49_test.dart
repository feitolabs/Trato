import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/auth/servico_auth.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/ajuda/servico_ajuda_local.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/telas/onboarding/tour_perfil_tela.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServicoAuthPadrao.atual = ServicoAuthFake();
  });

  group('F49 · tour rápido por perfil', () {
    testWidgets('cliente vê as 4 páginas com textos exatos, indicador 1 DE 4, Avançar e Pular',
        (tester) async {
      var concluiu = false;
      await _abrir(
        tester,
        TourPerfilTela(perfil: PerfilUso.cliente, aoConcluir: () => concluiu = true),
      );

      final esperados = [
        ('1 DE 4', 'Conte o que você precisa', 'Descreva o serviço. É grátis e sem taxa.'),
        (
          '2 DE 4',
          'Compare e escolha',
          'Profissionais verificados mandam orçamentos. Veja o que inclui e escolha.',
        ),
        (
          '3 DE 4',
          'Pague com segurança',
          'O dinheiro fica guardado no app. Só vai para o profissional quando você confirma o serviço.',
        ),
        (
          '4 DE 4',
          'Avalie e ganhe Tratinhos',
          'Avalie o serviço e ganhe Tratinhos de desconto. Deu problema? Abra uma disputa.',
        ),
      ];

      for (var i = 0; i < esperados.length; i++) {
        final (ind, titulo, texto) = esperados[i];
        final botao = i == esperados.length - 1 ? 'Começar' : 'Avançar';
        expect(find.text(ind), findsOneWidget);
        expect(find.text(titulo), findsOneWidget);
        expect(find.text(texto), findsOneWidget);
        expect(find.text('Pular'), findsOneWidget);
        expect(find.text(botao), findsOneWidget);
        await tester.tap(find.text(botao));
        await tester.pumpAndSettle();
      }

      expect(concluiu, isTrue);
      expect(await PreferenciaTourPerfil.visto(PerfilUso.cliente), isTrue);
      expect(await PreferenciaTourPerfil.visto(PerfilUso.profissional), isFalse);
    });

    testWidgets('profissional vê as 4 páginas com textos exatos e Pular em todas', (tester) async {
      var concluiu = false;
      await _abrir(
        tester,
        TourPerfilTela(perfil: PerfilUso.profissional, aoConcluir: () => concluiu = true),
      );

      final esperados = [
        (
          '1 DE 4',
          'Complete seu perfil',
          'Foto, categorias, regiões e conta para receber. Depois da verificação, os clientes veem você.',
        ),
        (
          '2 DE 4',
          'Receba pedidos',
          'Veja os pedidos perto de você e mande o orçamento pela calculadora.',
        ),
        (
          '3 DE 4',
          'Receba sem taxa',
          'O valor líquido cai na sua carteira depois que o cliente confirma. Sem taxa.',
        ),
        (
          '4 DE 4',
          'Ganhe Tratinhos',
          'Avalie seus clientes e ganhe Tratinhos.',
        ),
      ];

      for (var i = 0; i < esperados.length; i++) {
        final (ind, titulo, texto) = esperados[i];
        final botao = i == esperados.length - 1 ? 'Começar' : 'Avançar';
        expect(find.text(ind), findsOneWidget);
        expect(find.text(titulo), findsOneWidget);
        expect(find.text(texto), findsOneWidget);
        expect(find.text('Pular'), findsOneWidget);
        expect(find.text(botao), findsOneWidget);
        await tester.tap(find.text(botao));
        await tester.pumpAndSettle();
      }

      expect(concluiu, isTrue);
      expect(await PreferenciaTourPerfil.visto(PerfilUso.profissional), isTrue);
      expect(await PreferenciaTourPerfil.visto(PerfilUso.cliente), isFalse);
    });

    testWidgets('Pular marca como visto e não reaparece para aquele perfil', (tester) async {
      await _abrir(tester, const EscolhaPerfilTela());

      await tester.tap(find.text('Criar conta de cliente'));
      await tester.pumpAndSettle();
      expect(find.byType(TourPerfilTela), findsOneWidget);

      await tester.tap(find.text('Pular'));
      await tester.pumpAndSettle();
      expect(find.byType(CriarContaTela), findsOneWidget);
      expect(await PreferenciaTourPerfil.visto(PerfilUso.cliente), isTrue);

      // Reabrindo a escolha de perfil: cliente vai direto ao cadastro (não vê o tour).
      await tester.pumpWidget(const SizedBox.shrink());
      await _abrir(tester, const EscolhaPerfilTela());
      await tester.tap(find.text('Criar conta de cliente'));
      await tester.pumpAndSettle();
      expect(find.byType(TourPerfilTela), findsNothing);
      expect(find.byType(CriarContaTela), findsOneWidget);
    });

    testWidgets('quem já tem login guardado não vê o tour', (tester) async {
      final auth = ServicoAuthFake();
      ServicoAuthPadrao.atual = auth;
      await auth.entrarComEmail(email: 'a@b.com', senha: 'x');

      await _abrir(tester, const EscolhaPerfilTela());
      await tester.tap(find.text('Criar conta de cliente'));
      await tester.pumpAndSettle();

      expect(find.byType(TourPerfilTela), findsNothing);
      expect(find.byType(CriarContaTela), findsOneWidget);
    });

    testWidgets('Ajuda tem "Ver tour de novo" e abre o tour sem marcar preferência',
        (tester) async {
      await _abrir(
        tester,
        Builder(
          builder: (context) => AjudaTela(
            servico: const ServicoAjudaLocal(),
            aoVerTour: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (tourCtx) => TourPerfilTela(
                  perfil: PerfilUso.profissional,
                  registrarVisto: false,
                  aoConcluir: () => Navigator.of(tourCtx).pop(),
                ),
              ),
            ),
          ),
        ),
      );

      final botao = find.text('Ver tour de novo');
      await tester.scrollUntilVisible(botao, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(botao);
      await tester.pumpAndSettle();
      expect(botao, findsOneWidget);

      await tester.tap(botao);
      await tester.pumpAndSettle();
      expect(find.byType(TourPerfilTela), findsOneWidget);
      expect(find.text('Complete seu perfil'), findsOneWidget);

      await tester.tap(find.text('Pular'));
      await tester.pumpAndSettle();
      expect(find.byType(AjudaTela), findsOneWidget);
      // Não gravou nenhuma preferência no aparelho.
      expect(await PreferenciaTourPerfil.visto(PerfilUso.profissional), isFalse);
      expect(await PreferenciaTourPerfil.visto(PerfilUso.cliente), isFalse);
    });
  });
}
