import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/auth/confirmar_celular_tela.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/auth/recuperar_senha_tela.dart';
import 'package:trato/telas/auth/validacao.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/em_breve_tela.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/tema/tema.dart';

const _celularDigitado = '(31) 98765-4417';

Future<void> _abrir(WidgetTester tester, Widget tela,
    {Size tamanho = const Size(390, 1600)}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: tela,
    ),
  );
}

/// Digita no campo cujo rótulo é [rotulo] (o rótulo e o TextField ficam na mesma CampoTrato).
Future<void> _digitar(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.descendant(
    of: find.ancestor(of: find.text(rotulo), matching: find.byType(Column)).first,
    matching: find.byType(TextField),
  );
  await tester.enterText(campo.first, texto);
}

Future<void> _tocar(WidgetTester tester, String texto) async {
  // `.last`: em "Criar conta" o título vem antes do botão.
  final alvo = find.text(texto).last;
  await tester.ensureVisible(alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  group('validação', () {
    test('cpf, celular e código exigem a quantidade de números', () {
      expect(ValidacaoAuth.cpf('123.456.789-01'), isNull);
      expect(ValidacaoAuth.cpf('123.456.789'), isNotNull);
      expect(ValidacaoAuth.celular(_celularDigitado), isNull);
      expect(ValidacaoAuth.celular('(31) 9876'), isNotNull);
      expect(ValidacaoAuth.codigoSms('123456'), isNull);
      expect(ValidacaoAuth.codigoSms('12345'), isNotNull);
    });

    test('e-mail', () {
      expect(ValidacaoAuth.email('mariana@email.com'), isNull);
      expect(ValidacaoAuth.email('mariana@email'), isNotNull);
      expect(ValidacaoAuth.email(''), isNotNull);
    });

    test('senha nova: 8+ caracteres com letra e número', () {
      expect(ValidacaoAuth.senhaNova('abc12345'), isNull);
      expect(ValidacaoAuth.senhaNova('abc1234'), isNotNull);
      expect(ValidacaoAuth.senhaNova('abcdefgh'), isNotNull);
      expect(ValidacaoAuth.senhaNova('12345678'), isNotNull);
    });

    test('nascimento: formato, data real e maioridade', () {
      final hoje = DateTime(2026, 10, 28);
      expect(ValidacaoAuth.nascimento('28/10/2008', hoje: hoje), isNull);
      expect(ValidacaoAuth.nascimento('29/10/2008', hoje: hoje), isNotNull);
      expect(ValidacaoAuth.nascimento('31/02/1990', hoje: hoje), isNotNull);
      expect(ValidacaoAuth.nascimento('1/1/90', hoje: hoje), isNotNull);
    });

    test('celular mascarado', () {
      expect(ValidacaoAuth.celularMascarado(_celularDigitado), '(31) 9••••-4417');
    });

    test('máscaras formatam enquanto digita', () {
      String f(MascaraNumerica m, String t) =>
          m.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: t)).text;
      expect(f(MascaraNumerica.cpf, '12345678901'), '123.456.789-01');
      expect(f(MascaraNumerica.data, '28102008'), '28/10/2008');
      expect(f(MascaraNumerica.celular, '31987654417'), _celularDigitado);
    });
  });

  group('login', () {
    testWidgets('campos vazios mostram erro e não saem da tela', (tester) async {
      await _abrir(tester, const LoginTela());

      await _tocar(tester, 'Entrar');

      expect(find.text('Informe e-mail, CPF ou telefone.'), findsOneWidget);
      expect(find.text('Informe sua senha.'), findsOneWidget);
      expect(find.byType(EmBreveTela), findsNothing);
    });

    testWidgets('Mostrar alterna a visibilidade da senha', (tester) async {
      await _abrir(tester, const LoginTela());

      bool oculta() => tester.widgetList<TextField>(find.byType(TextField)).last.obscureText;
      expect(oculta(), isTrue);
      await tester.tap(find.text('Mostrar'));
      await tester.pump();
      expect(oculta(), isFalse);
      expect(find.text('Ocultar'), findsOneWidget);
    });

    testWidgets('com dados preenchidos, Entrar leva à casca do cliente', (tester) async {
      await _abrir(tester, const LoginTela());
      await _digitar(tester, 'E-mail, CPF ou telefone', 'mariana@email.com');
      await _digitar(tester, 'Senha', 'segredo123');

      await _tocar(tester, 'Entrar');

      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    for (final texto in ['Entrar com Google', 'Entrar com Apple', 'Entrar com biometria']) {
      testWidgets('$texto abre "em breve"', (tester) async {
        await _abrir(tester, const LoginTela());
        await _tocar(tester, texto);
        expect(find.byType(EmBreveTela), findsOneWidget);
      });
    }

    testWidgets('Esqueci minha senha e Criar conta levam às telas certas', (tester) async {
      await _abrir(tester, const LoginTela());
      await _tocar(tester, 'Esqueci minha senha');
      expect(find.byType(RecuperarSenhaTela), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tocar(tester, 'Criar conta');
      expect(find.byType(EscolhaPerfilTela), findsOneWidget);
    });
  });

  group('criar conta', () {
    Future<void> preencher(WidgetTester tester) async {
      await _digitar(tester, 'Nome completo', 'Mariana Alves');
      await _digitar(tester, 'CPF', '12345678901');
      await _digitar(tester, 'Nascimento', '15031990');
      await _digitar(tester, 'Celular', '31987654417');
      await _digitar(tester, 'E-mail', 'mariana@email.com');
      await _digitar(tester, 'Senha', 'segredo123');
    }

    testWidgets('mostra "Passo 1 de 2" e valida tudo ao tentar criar', (tester) async {
      await _abrir(tester, const CriarContaTela());
      expect(find.text('Passo 1 de 2'), findsOneWidget);

      await _tocar(tester, 'Criar conta');

      expect(find.text('Informe seu nome completo.'), findsOneWidget);
      expect(find.text('O CPF tem 11 números.'), findsOneWidget);
      expect(find.text('Aceite os termos para continuar.'), findsOneWidget);
      expect(find.byType(ConfirmarCelularTela), findsNothing);
    });

    testWidgets('sem aceitar os termos não avança', (tester) async {
      await _abrir(tester, const CriarContaTela());
      await preencher(tester);

      await _tocar(tester, 'Criar conta');

      expect(find.text('Aceite os termos para continuar.'), findsOneWidget);
      expect(find.byType(ConfirmarCelularTela), findsNothing);
    });

    testWidgets('formulário certo leva ao passo 2 com o celular mascarado', (tester) async {
      await _abrir(tester, const CriarContaTela());
      await preencher(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      await _tocar(tester, 'Criar conta');

      expect(find.byType(ConfirmarCelularTela), findsOneWidget);
      expect(find.text('Passo 2 de 2'), findsOneWidget);
      expect(find.textContaining('(31) 9••••-4417', findRichText: true), findsOneWidget);
    });
  });

  group('confirmar celular', () {
    testWidgets('código incompleto mostra erro; completo leva ao app', (tester) async {
      await _abrir(tester, const ConfirmarCelularTela(celular: _celularDigitado));

      await _tocar(tester, 'Confirmar código');
      expect(find.text('O código tem 6 números.'), findsOneWidget);

      await _digitar(tester, 'Código', '123456');
      await _tocar(tester, 'Confirmar código');
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('contagem de reenvio chega a zero e vira link', (tester) async {
      await _abrir(tester, const ConfirmarCelularTela(celular: _celularDigitado));
      expect(find.text('Reenviar em 0:45'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Reenviar em 0:44'), findsOneWidget);

      await tester.pump(const Duration(seconds: 44));
      expect(find.text('Reenviar código'), findsOneWidget);
    });

    testWidgets('Mudar número volta ao passo 1', (tester) async {
      await _abrir(tester, const CriarContaTela());
      Navigator.of(tester.element(find.byType(CriarContaTela))).push(
        MaterialPageRoute<void>(
          builder: (_) => const ConfirmarCelularTela(celular: _celularDigitado),
        ),
      );
      await tester.pumpAndSettle();

      await _tocar(tester, 'Mudar número');

      expect(find.byType(CriarContaTela), findsOneWidget);
    });
  });

  group('recuperar senha', () {
    testWidgets('e-mail inválido mostra erro; válido abre "em breve"', (tester) async {
      await _abrir(tester, const RecuperarSenhaTela());

      await _digitar(tester, 'E-mail', 'mariana');
      await _tocar(tester, 'Enviar código');
      expect(find.text('E-mail inválido.'), findsOneWidget);

      await _digitar(tester, 'E-mail', 'mariana@email.com');
      await _tocar(tester, 'Enviar código');
      expect(find.byType(EmBreveTela), findsOneWidget);
    });

    testWidgets('Fale com o suporte abre "em breve"', (tester) async {
      await _abrir(tester, const RecuperarSenhaTela());
      await _tocar(tester, 'Fale com o suporte');
      expect(find.byType(EmBreveTela), findsOneWidget);
    });
  });

  // Qualquer estouro de layout faz o teste falhar.
  const telas = <String, Widget>{
    'login': LoginTela(),
    'criar conta': CriarContaTela(),
    'confirmar celular': ConfirmarCelularTela(celular: _celularDigitado),
    'recuperar senha': RecuperarSenhaTela(),
  };
  const tamanhos = [Size(320, 568), Size(390, 844), Size(768, 1024)];
  for (final MapEntry(key: nome, value: tela) in telas.entries) {
    for (final tamanho in tamanhos) {
      for (final escala in [1.0, Responsivo.escalaFonteMaxima]) {
        testWidgets('sem estouro — $nome ${tamanho.width.toInt()} fonte x$escala', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await _abrir(tester, tela, tamanho: tamanho);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
