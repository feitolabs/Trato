// Termos 15.4: o aviso de marketing abre a Central de Privacidade, onde se revoga.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/lgpd/central_privacidade_tela.dart';
import 'package:trato/telas/lgpd/modelos.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';

import 'apoio/exemplos/demo.dart';

const _dados = <String, dynamic>{
  'campanha_id': 'camp-1',
  'tela': 'privacidade',
  'link': 'trato://privacidade',
};
const _esperado = ResultadoLink.valido(DestinoApp.privacidade, null);

void main() {
  test('push de marketing: destino privacidade, sem trocar de modo e sem usar o link', () {
    expect(resultadoDoPush(_dados), _esperado);
    expect(resultadoDoPush({..._dados, 'link': 'https://outro.site'}), _esperado);
    expect(resultadoDoPush({'link': 'trato://privacidade'}), ResultadoLink.ignorado);
  });

  for (final profissional in [false, true]) {
    test('caixa: mesmo destino (profissional: $profissional)', () {
      final aviso = Notificacao(
        id: 'n1',
        tipo: tipoDaNotificacao('aviso_campanha'),
        tipoApi: 'aviso_campanha',
        tela: 'privacidade',
        titulo: 'Novidade',
        texto: 'x',
        quando: 'agora',
      );
      expect(RotasTrato.destinoDaCaixa(aviso, modoAtualProfissional: profissional), _esperado);
    });

    testWidgets('abre a Central com a chave (profissional: $profissional)', (t) async {
      t.view.physicalSize = const Size(320, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final antes = RotasTrato.repos;
      addTearDown(() => RotasTrato.repos = antes);
      RotasTrato.repos = repositoriosDemo();
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));
      RotasTrato.abrirLink(ctx, _esperado, profissional: profissional);
      await t.pumpAndSettle();
      expect(find.byType(CentralPrivacidadeTela), findsOneWidget);
      expect(find.text('Avisos e novidades', skipOffstage: false), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  test('a chave não promete canal que não existe', () {
    final chave = consentimentosPadrao.singleWhere((c) => c.id == 'avisos');
    expect(chave.descricao, isNot(contains('WhatsApp')));
  });
}
