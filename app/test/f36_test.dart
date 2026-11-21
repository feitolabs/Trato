import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

Profissional _pro({
  required int servicos,
  required int avaliacoes,
  String verificacao = 'Verificado',
  bool historico = true,
}) =>
    Profissional(
      nome: 'Ana Lima',
      iniciais: 'AL',
      verificacao: verificacao,
      especialidade: 'Eletricista',
      servicosConcluidos: servicos,
      nota: avaliacoes == 0 ? 0 : 4.8,
      distanciaKm: 2,
      detalhe: DetalhePerfil(
        noTratoDesde: 2026,
        totalAvaliacoes: avaliacoes,
        taxaConclusao: 96,
        respondeEm: '—',
        verificacoes: const [],
        avaliacoes: const [],
        temHistorico: historico,
      ),
    );

void main() {
  group('F36 · Perfil do profissional', () {
    testWidgets('sem avaliações e sem serviços: "Novo no Trato · Identidade verificada"',
        (tester) async {
      await _abrir(
        tester,
        PerfilProfissionalTela(profissional: _pro(servicos: 0, avaliacoes: 0)),
      );
      expect(find.text('Novo no Trato · Identidade verificada'), findsOneWidget);
      expect(find.textContaining('0,0'), findsNothing);
      expect(find.text('Serviços concluídos'), findsNothing);
      expect(find.text('Taxa de conclusão'), findsNothing);
      expect(find.textContaining('Responde em'), findsNothing);
    });

    testWidgets('novo e não verificado: só "Novo no Trato"', (tester) async {
      await _abrir(
        tester,
        PerfilProfissionalTela(profissional: _pro(servicos: 0, avaliacoes: 0, verificacao: '')),
      );
      expect(find.text('Novo no Trato'), findsOneWidget);
    });

    testWidgets('com 4 serviços: nota e serviços, mas sem Taxa de conclusão', (tester) async {
      await _abrir(
        tester,
        PerfilProfissionalTela(profissional: _pro(servicos: 4, avaliacoes: 3)),
      );
      expect(find.text('Serviços concluídos'), findsOneWidget);
      expect(find.text('Taxa de conclusão'), findsNothing);
      expect(find.text('96%'), findsNothing);
      expect(find.textContaining('Responde em'), findsNothing);
    });

    testWidgets('com 5 serviços e taxa informada: mostra a Taxa de conclusão', (tester) async {
      await _abrir(
        tester,
        PerfilProfissionalTela(profissional: _pro(servicos: 5, avaliacoes: 5)),
      );
      expect(find.text('Taxa de conclusão'), findsOneWidget);
      expect(find.text('96%'), findsOneWidget);
      expect(find.textContaining('Responde em'), findsNothing);
    });

    testWidgets('com 5 serviços mas sem a taxa (dado nulo): não mostra', (tester) async {
      await _abrir(
        tester,
        PerfilProfissionalTela(profissional: _pro(servicos: 8, avaliacoes: 5, historico: false)),
      );
      expect(find.text('Taxa de conclusão'), findsNothing);
    });
  });

  test('F36 · Comparar orçamentos: sem nota aparece "Novo no Trato"', () {
    expect(semAvaliacoes, 'Novo no Trato');
  });
}
