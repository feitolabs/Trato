import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/configuracoes/configuracoes_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';

// As opções de conta (dados pessoais, privacidade e exclusão, ajuda, termos, sair) ficam na tela
// Configurações, atrás da engrenagem do Perfil, para cliente e profissional. A exclusão da conta
// continua à mão (exigência das lojas e da LGPD).

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('perfil do profissional não mistura mais a conta: só "Usar como cliente"',
      (tester) async {
    await _abrir(
      tester,
      PerfilPublicoTela(
        servico: ServicoPerfilPublicoFake(),
        aoUsarComoCliente: () {},
        aoAbrirConfiguracoes: () {},
      ),
    );

    expect(find.text('Usar como cliente'), findsOneWidget);
    for (final titulo in ['Dados pessoais', 'Notificações', 'Central de ajuda', 'Sair']) {
      expect(find.text(titulo), findsNothing, reason: titulo);
    }
    expect(find.byTooltip('Configurações'), findsOneWidget);
  });

  testWidgets('a engrenagem do perfil do profissional abre as configurações', (tester) async {
    var abriu = false;
    await _abrir(
      tester,
      PerfilPublicoTela(
        servico: ServicoPerfilPublicoFake(),
        aoAbrirConfiguracoes: () => abriu = true,
      ),
    );

    await tester.tap(find.byTooltip('Configurações'));

    expect(abriu, isTrue);
  });

  testWidgets('sem destino, a engrenagem não aparece', (tester) async {
    await _abrir(tester, PerfilPublicoTela(servico: ServicoPerfilPublicoFake()));
    expect(find.byTooltip('Configurações'), findsNothing);
  });

  testWidgets('configurações lista os grupos, avisa os toques e tem Sair no fim', (tester) async {
    final tocados = <String>[];
    var saiu = false;
    ItemContaPerfil item(IconData icone, String titulo) =>
        ItemContaPerfil(icone: icone, titulo: titulo, aoTocar: () => tocados.add(titulo));

    await _abrir(
      tester,
      ConfiguracoesTela(
        grupos: [
          GrupoConfiguracao(titulo: 'CONTA', itens: [
            item(Icons.person_outline, 'Dados pessoais'),
            item(Icons.notifications_none, 'Notificações'),
          ]),
          GrupoConfiguracao(titulo: 'PRIVACIDADE E AJUDA', itens: [
            item(Icons.lock_outline, 'Meus dados e excluir conta'),
            item(Icons.help_outline, 'Central de ajuda'),
            item(Icons.description_outlined, 'Termos e políticas'),
          ]),
        ],
        aoSair: () => saiu = true,
      ),
    );

    expect(find.text('Configurações'), findsOneWidget);
    for (final titulo in [
      'CONTA',
      'PRIVACIDADE E AJUDA',
      'Dados pessoais',
      'Notificações',
      'Meus dados e excluir conta',
      'Central de ajuda',
      'Termos e políticas',
      'Sair',
    ]) {
      expect(find.text(titulo), findsOneWidget, reason: titulo);
    }

    await tester.tap(find.text('Meus dados e excluir conta'));
    await tester.tap(find.text('Sair'));
    expect(tocados, ['Meus dados e excluir conta']);
    expect(saiu, isTrue);
  });

  testWidgets('sem aoSair, a linha Sair não aparece', (tester) async {
    await _abrir(tester, const ConfiguracoesTela(grupos: []));
    expect(find.text('Sair'), findsNothing);
  });
}
