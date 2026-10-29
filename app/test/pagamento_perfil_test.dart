import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/tema/tema.dart';

const _telas = {
  'pequeno 320x568': Size(320, 568),
  'protótipo 390x844': Size(390, 844),
  'tablet 768x1024': Size(768, 1024),
};

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 1200),
  double fonte = 1,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = fonte;
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

const _adiantamento = DadosPagamento(
  subtitulo: 'Carlos Mendes · Troca de tomadas e chuveiro',
  valorAgoraCentavos: 11400,
  rotuloValor: 'Adiantamento de 30%',
  opcoes: [
    OpcaoPagamento(metodo: MetodoPagamento.pix, titulo: 'Pix', descricao: 'Na hora'),
    OpcaoPagamento(metodo: MetodoPagamento.cartao, titulo: 'Cartão', descricao: 'Visa final 4417'),
  ],
);

void main() {
  group('Pagamento', () {
    testWidgets('mostra valor, passos de proteção e aviso de CPF', (tester) async {
      await _abrir(tester, const PagamentoTela());
      expect(find.text('R\$ 380,00'), findsOneWidget);
      expect(find.text('Como funciona o pagamento', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('só no nome do seu CPF', skipOffstage: false), findsOneWidget);
      expect(find.text('Pagar R\$ 380,00 com Pix'), findsOneWidget);
    });

    testWidgets('trocar para cartão muda o botão e o método enviado', (tester) async {
      MetodoPagamento? pago;
      await _abrir(tester, PagamentoTela(aoPagar: (m) => pago = m));
      await tester.tap(find.text('Cartão de crédito à vista'));
      await tester.pumpAndSettle();
      expect(find.text('Pagar R\$ 380,00 com cartão'), findsOneWidget);

      await tester.tap(find.text('Pagar R\$ 380,00 com cartão'));
      expect(pago, MetodoPagamento.cartao);
    });

    testWidgets('Pix é o padrão e o botão chama o callback', (tester) async {
      MetodoPagamento? pago;
      await _abrir(tester, PagamentoTela(aoPagar: (m) => pago = m));
      await tester.tap(find.textContaining('Pagar R\$'));
      expect(pago, MetodoPagamento.pix);
    });

    testWidgets('exibe o valor e o rótulo que vierem dos dados', (tester) async {
      await _abrir(tester, const PagamentoTela(dados: _adiantamento));
      expect(find.text('R\$ 114,00'), findsOneWidget);
      expect(find.text('Adiantamento de 30%'), findsOneWidget);
      expect(find.text('Pagar R\$ 114,00 com Pix'), findsOneWidget);
    });

    testWidgets('sem rótulo, nada extra aparece', (tester) async {
      await _abrir(tester, const PagamentoTela());
      expect(find.textContaining('Adiantamento'), findsNothing);
    });
  });

  group('Perfil do cliente', () {
    testWidgets('mostra nome, nota e os três grupos', (tester) async {
      await _abrir(tester, const PerfilClienteTela());
      expect(find.text('Mariana Alves'), findsOneWidget);
      expect(find.text('Nota 4,8 como cliente · 6 serviços'), findsOneWidget);
      expect(find.text('CONTA'), findsOneWidget);
      expect(find.text('SEGURANÇA E AVISOS'), findsOneWidget);
      expect(find.text('PRIVACIDADE E AJUDA'), findsOneWidget);
      expect(find.text('Pix, Visa'), findsOneWidget);
    });

    testWidgets('itens e Sair chamam os callbacks', (tester) async {
      final toques = <AcaoPerfil>[];
      var saiu = false;
      await _abrir(
        tester,
        PerfilClienteTela(aoTocarItem: toques.add, aoSair: () => saiu = true),
      );
      await tester.tap(find.text('Usar como profissional'));
      await tester.tap(find.text('Meus dados (LGPD)'));
      await tester.tap(find.text('Sair'));
      expect(toques, [AcaoPerfil.usarComoProfissional, AcaoPerfil.meusDados]);
      expect(saiu, isTrue);
    });
  });

  group('sem estouro de layout', () {
    final telas = <String, Widget>{
      'pagamento': const PagamentoTela(dados: _adiantamento),
      'perfil': const PerfilClienteTela(),
    };
    for (final MapEntry(key: nome, value: tela) in telas.entries) {
      for (final MapEntry(key: nomeTela, value: tamanho) in _telas.entries) {
        for (final fonte in [1.0, 1.3]) {
          testWidgets('$nome — $nomeTela, fonte x$fonte', (tester) async {
            await _abrir(tester, tela, tamanho: tamanho, fonte: fonte);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
