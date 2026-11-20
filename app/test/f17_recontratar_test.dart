import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/comuns/botao_de_confianca.dart';
import 'package:trato/telas/comuns/convite.dart';
import 'package:trato/telas/comuns/sucesso_acao_tela.dart';
import 'package:trato/telas/conta/favoritos_contatos_telas.dart';
import 'package:trato/telas/conta/modelos.dart';
import 'package:trato/telas/conta/servico_fake.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  group('1. Chamar de novo (Favoritos)', () {
    final servico = ServicoContaFake(
      favoritos: const [
        FavoritoConta(profissionalId: 'p1', nome: 'Carlos Pintor', nota: 4.8, servicos: 12),
      ],
    );

    testWidgets('o botão entrega o favorito (com o id) a quem abre o novo pedido', (tester) async {
      FavoritoConta? escolhido;
      await _abrir(
        tester,
        FavoritosTela(servico: servico, aoChamarDeNovo: (f) => escolhido = f),
      );
      await tester.tap(find.text('Chamar de novo'));
      expect(escolhido?.profissionalId, 'p1');
    });

    testWidgets('sem a ação, o botão não aparece', (tester) async {
      await _abrir(tester, FavoritosTela(servico: servico));
      expect(find.text('Chamar de novo'), findsNothing);
    });
  });

  group('2. Salvar como profissional de confiança', () {
    testWidgets('salva uma vez e passa a mostrar "Profissional de confiança"', (tester) async {
      var salvou = 0;
      await _abrir(
        tester,
        Scaffold(
          body: BotaoDeConfianca(
            jaEFavorito: () async => false,
            favoritar: () async => salvou++,
          ),
        ),
      );
      await tester.tap(find.text('Salvar como profissional de confiança'));
      await tester.pumpAndSettle();
      expect(salvou, 1);
      expect(find.text('Profissional de confiança'), findsOneWidget);
      expect(find.text('Salvar como profissional de confiança'), findsNothing); // não duplica
    });

    testWidgets('já favorito: mostra "Profissional de confiança" e não chama o PUT', (tester) async {
      var salvou = 0;
      await _abrir(
        tester,
        Scaffold(
          body: BotaoDeConfianca(
            jaEFavorito: () async => true,
            favoritar: () async => salvou++,
          ),
        ),
      );
      expect(find.text('Profissional de confiança'), findsOneWidget);
      expect(salvou, 0);
    });

    testWidgets('erro de rede (na consulta e ao salvar) não trava o fluxo', (tester) async {
      await _abrir(
        tester,
        Scaffold(
          body: BotaoDeConfianca(
            jaEFavorito: () async => throw Exception('rede'),
            favoritar: () async => throw Exception('rede'),
          ),
        ),
      );
      await tester.tap(find.text('Salvar como profissional de confiança'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Não deu para salvar agora'), findsOneWidget);
      expect(find.text('Salvar como profissional de confiança'), findsOneWidget); // pode tentar de novo
    });
  });

  group('3. Convite', () {
    testWidgets('compartilha a mensagem pronta, sem Tratinhos', (tester) async {
      String? enviado;
      await _abrir(
        tester,
        SucessoAcaoTela(
          titulo: 'Feito',
          subtitulo: 'ok',
          aoVoltarInicio: () {},
          compartilhar: (t) async => enviado = t,
        ),
      );
      await tester.tap(find.text('Indicar o Trato'));
      await tester.pumpAndSettle();
      expect(enviado, textoConvite);
      expect(textoConvite, startsWith('Contrato profissionais verificados pelo Trato'));
      expect(textoConvite.toLowerCase(), isNot(contains('tratinho')));
      expect(find.text('Convite copiado!'), findsNothing);
    });

    testWidgets('sem compartilhamento (erro/plugin): copia e avisa "Convite copiado!"',
        (tester) async {
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _abrir(
        tester,
        SucessoAcaoTela(
          titulo: 'Feito',
          subtitulo: 'ok',
          aoVoltarInicio: () {},
          compartilhar: (_) async => throw StateError('sem plugin'),
        ),
      );
      await tester.tap(find.text('Indicar o Trato'));
      await tester.pumpAndSettle();
      expect(find.text('Convite copiado!'), findsOneWidget);
      expect(copiado, textoConvite);
    });
  });
}
