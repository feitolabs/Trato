import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:trato_admin/dados/modelos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

class _ApiComDenuncias extends ApiFake {
  @override
  Future<List<AlertaRisco>> listarAlertasRisco() async => [
        ...await super.listarAlertasRisco(),
        const AlertaRisco(
          id: 'd-1',
          usuarioId: 'u-201',
          usuarioNome: 'Ana P.',
          usuarioTipo: 'cliente',
          usuarioStatus: 'ativo',
          tipo: 'denuncia_perfil',
          severidade: 'media',
          detalhes: 'Foto de perfil imprópria.',
          criadoEm: '2026-11-03T10:00:00Z',
        ),
        const AlertaRisco(
          id: 'd-2',
          usuarioId: 'u-202',
          usuarioNome: 'Beto S.',
          usuarioTipo: 'profissional',
          usuarioStatus: 'ativo',
          tipo: 'denuncia_chat',
          severidade: 'alta',
          detalhes: 'Pediu pagamento por fora.',
          criadoEm: '2026-11-03T11:00:00Z',
        ),
      ];
}

void main() {
  testWidgets('denúncias aparecem com rótulo legível e o filtro "Só denúncias" mostra só elas', (tester) async {
    await abrirPainel(tester, papel: 'administrador', api: _ApiComDenuncias(), secao: 'risco');
    expect(find.text('Denúncia de perfil'), findsOneWidget);
    expect(find.text('Denúncia no chat'), findsOneWidget);
    expect(find.textContaining('denuncia_'), findsNothing);
    expect(find.text('Valor atípico'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('risco-so-denuncias')));
    await tester.pumpAndSettle();
    expect(find.text('Denúncia de perfil'), findsWidgets);
    expect(find.text('Denúncia no chat'), findsWidgets);
    expect(find.text('Valor atípico'), findsNothing);
    expect(find.text('Troca de chave PIX'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('risco-so-denuncias')));
    await tester.pumpAndSettle();
    expect(find.text('Valor atípico'), findsWidgets);
  });
}
