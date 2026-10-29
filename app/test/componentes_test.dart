import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/tema/tema.dart';

Widget _emTela(Widget filho) => MaterialApp(
      theme: TemaTrato.claro,
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: filho)),
    );

void main() {
  group('BotaoPrimario', () {
    testWidgets('chama aoTocar', (tester) async {
      var tocou = 0;
      await tester.pumpWidget(_emTela(BotaoPrimario(texto: 'Próximo', aoTocar: () => tocou++)));

      await tester.tap(find.text('Próximo'));

      expect(tocou, 1);
    });

    testWidgets('carregando: mostra progresso e não aceita toque', (tester) async {
      var tocou = 0;
      await tester.pumpWidget(
        _emTela(BotaoPrimario(texto: 'Pagar', aoTocar: () => tocou++, carregando: true)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(tocou, 0);
    });

    testWidgets('tem a altura do protótipo (52)', (tester) async {
      await tester.pumpWidget(_emTela(BotaoPrimario(texto: 'Próximo', aoTocar: () {})));

      expect(tester.getSize(find.byType(FilledButton)).height, EspacosTrato.alturaBotao);
    });
  });

  testWidgets('BotaoSecundario selecionado usa fundo azul suave', (tester) async {
    await tester.pumpWidget(
      _emTela(BotaoSecundario(texto: 'Eu forneço', selecionado: true, aoTocar: () {})),
    );

    final botao = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(botao.style!.backgroundColor!.resolve({}), CoresTrato.azulSuave);
  });

  group('CampoTrato', () {
    testWidgets('mostra rótulo, dica e ajuda', (tester) async {
      await tester.pumpWidget(
        _emTela(const CampoTrato(rotulo: 'Senha', dica: '••••', ajuda: 'Pelo menos 8 caracteres')),
      );

      expect(find.text('Senha'), findsOneWidget);
      expect(find.text('••••'), findsOneWidget);
      expect(find.text('Pelo menos 8 caracteres'), findsOneWidget);
    });

    testWidgets('erro substitui a ajuda', (tester) async {
      await tester.pumpWidget(
        _emTela(const CampoTrato(rotulo: 'CPF', ajuda: 'Só números', erro: 'CPF inválido')),
      );

      expect(find.text('CPF inválido'), findsOneWidget);
      expect(find.text('Só números'), findsNothing);
    });

    testWidgets('senha fica oculta', (tester) async {
      await tester.pumpWidget(_emTela(const CampoTrato(rotulo: 'Senha', senha: true)));

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    });
  });

  testWidgets('CartaoTrato tocável mostra seta e responde', (tester) async {
    var tocou = false;
    await tester.pumpWidget(
      _emTela(CartaoTrato(aoTocar: () => tocou = true, child: const Text('Vazamento na pia'))),
    );

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.text('Vazamento na pia'));
    expect(tocou, isTrue);
  });

  testWidgets('ChipStatus usa as cores da família', (tester) async {
    await tester.pumpWidget(
      _emTela(const ChipStatus(texto: 'Disputa aberta', tipo: TipoStatus.alerta)),
    );

    final caixa = tester.widget<Container>(find.byType(Container).first);
    expect((caixa.decoration! as BoxDecoration).color, CoresTrato.ambarSuave);
    expect(tester.widget<Text>(find.text('Disputa aberta')).style!.color, CoresTrato.ambarTexto);
  });

  testWidgets('LinhaDoTempo marca só as etapas feitas com ✓', (tester) async {
    await tester.pumpWidget(
      _emTela(
        const LinhaDoTempo(
          etapas: [
            EtapaLinhaDoTempo(titulo: 'Contratado', detalhe: 'a', estado: EstadoEtapa.feita),
            EtapaLinhaDoTempo(titulo: 'Em execução', detalhe: 'b', estado: EstadoEtapa.atual),
            EtapaLinhaDoTempo(titulo: 'Finalizado', detalhe: 'c', estado: EstadoEtapa.futura),
          ],
        ),
      ),
    );

    expect(find.text('Em execução'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('BarraAbasTrato mostra as 5 abas do cliente e troca de aba', (tester) async {
    var escolhida = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: Scaffold(
          bottomNavigationBar: BarraAbasTrato(
            abas: abasCliente,
            indiceAtual: 0,
            aoSelecionar: (i) => escolhida = i,
          ),
        ),
      ),
    );

    for (final rotulo in ['Início', 'Buscar', 'Pedidos', 'Mensagens', 'Perfil']) {
      expect(find.text(rotulo), findsOneWidget);
    }
    await tester.tap(find.text('Pedidos'));
    expect(escolhida, 2);
  });
}
