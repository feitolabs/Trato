import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/perfil_publico/perfil_publico_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';

// O perfil do profissional tem as mesmas opções de conta do perfil do cliente, inclusive
// excluir a conta (exigência das lojas e da LGPD).

void main() {
  testWidgets('perfil do profissional lista dados pessoais, privacidade/exclusão, ajuda e termos',
      (tester) async {
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tocados = <String>[];
    ItemContaPerfil item(IconData icone, String titulo) =>
        ItemContaPerfil(icone: icone, titulo: titulo, aoTocar: () => tocados.add(titulo));

    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: PerfilPublicoTela(
          servico: ServicoPerfilPublicoFake(),
          aoSair: () {},
          aoUsarComoCliente: () {},
          itensConta: [
            item(Icons.person_outline, 'Dados pessoais'),
            item(Icons.notifications_none, 'Notificações'),
            item(Icons.lock_outline, 'Meus dados e excluir conta'),
            item(Icons.help_outline, 'Central de ajuda'),
            item(Icons.description_outlined, 'Termos e políticas'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final titulo in [
      'Dados pessoais',
      'Notificações',
      'Meus dados e excluir conta',
      'Central de ajuda',
      'Termos e políticas',
      'Usar como cliente',
      'Sair',
    ]) {
      expect(find.text(titulo), findsOneWidget, reason: titulo);
    }

    await tester.ensureVisible(find.text('Meus dados e excluir conta'));
    await tester.tap(find.text('Meus dados e excluir conta'));
    expect(tocados, ['Meus dados e excluir conta']);
  });

  testWidgets('sem itens de conta, só aparecem Usar como cliente e Sair (como antes)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: PerfilPublicoTela(
          servico: ServicoPerfilPublicoFake(),
          aoSair: () {},
          aoUsarComoCliente: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dados pessoais'), findsNothing);
    expect(find.text('Sair'), findsOneWidget);
  });
}
