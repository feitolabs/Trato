// Termos 10.3: avisos do selo e orçamento recusado com o selo retirado.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/profissional/selo_tela.dart';

import 'apoio/exemplos/demo.dart';

const _eventos = ['conta.selo_retirado', 'conta.selo_reconferencia', 'conta.selo_regularizado'];
const _mensagem = 'O seu selo de verificação foi retirado (Termos 10.3).';
const _corpo = 'Selo retirado. Motivo: documento vencido. Para contestar, fale com o atendimento.';

Future<BuildContext> _app(WidgetTester t) async {
  t.view.physicalSize = const Size(320, 640);
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
  return ctx;
}

void main() {
  for (final evento in _eventos) {
    test('$evento: push com tela perfil abre o selo, como profissional', () {
      expect(
        resultadoDoPush({'evento': evento, 'tela': 'perfil'}),
        const ResultadoLink.valido(DestinoApp.selo, null, papel: 'profissional'),
      );
    });
  }

  test('tela perfil de outro evento continua ignorada', () {
    expect(resultadoDoPush({'evento': 'conta.outro', 'tela': 'perfil'}), ResultadoLink.ignorado);
  });

  testWidgets('abrir o destino mostra o motivo e como contestar', (t) async {
    final ctx = await _app(t);
    RotasTrato.abrirDestino(ctx, DestinoApp.selo, null, profissional: true);
    await t.pumpAndSettle();
    expect(find.byType(SeloTela), findsOneWidget);
    expect(find.byKey(const ValueKey('selo-falar')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('tela do selo: usa o aviso mais novo do selo; sem aviso, orienta', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Future<void> abrir(List<Notificacao> avisos) async {
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: SeloTela(key: UniqueKey(), carregar: () async => avisos, aoFalar: (_) {}),
      ));
      await t.pumpAndSettle();
    }

    await abrir(const [
      Notificacao(id: '1', titulo: 'Outro', texto: 'nada', quando: 'agora', tipo: 'pedido.novo'),
      Notificacao(
          id: '2',
          titulo: 'Selo retirado',
          texto: _corpo,
          quando: 'há 1 h',
          tipo: 'conta.selo_retirado'),
    ]);
    expect(find.text(_corpo), findsOneWidget);
    await abrir(const []);
    expect(find.textContaining('fale com o Trato'), findsOneWidget);
  });

  testWidgets('orçar com selo retirado: mensagem do servidor e orientação', (t) async {
    final ctx = await _app(t);
    final resultado = RotasTrato.tentarOrcamento(
      ctx,
      () async => throw const ErroTrato(TipoErro.recusado, _mensagem,
          codigoHttp: 409, codigo: 'selo_retirado'),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('dialogo-selo-retirado')), findsOneWidget);
    expect(find.textContaining(_mensagem), findsOneWidget);
    expect(find.byKey(const Key('selo-contestar')), findsOneWidget);
    await t.tap(find.byKey(const Key('selo-ver-aviso')));
    await t.pumpAndSettle();
    expect(await resultado, isFalse);
    expect(find.byType(SeloTela), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
