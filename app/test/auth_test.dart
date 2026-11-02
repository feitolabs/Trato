import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/auth/servico_auth_fake.dart';
import 'package:trato/telas/auth/confirmar_celular_tela.dart';
import 'package:trato/telas/auth/confirmar_email_tela.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/auth/recuperar_senha_tela.dart';
import 'package:trato/telas/auth/validacao.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/ajuda/ajuda_tela.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/tema/tema.dart';

const _celularDigitado = '(31) 98765-4417';
const _senha = 'segredo123';

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
    test('cpf confere os dígitos verificadores; celular e código exigem números', () {
      expect(ValidacaoAuth.cpf('123.456.789-09'), isNull);
      expect(ValidacaoAuth.cpf('123.456.789-01'), isNotNull);
      expect(ValidacaoAuth.cpf('111.111.111-11'), isNotNull);
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

      expect(
        find.text('Campo não preenchido. Digite seu e-mail, CPF ou celular para continuar.'),
        findsOneWidget,
      );
      expect(find.text('Senha não informada. Digite sua senha para entrar.'), findsOneWidget);
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

    testWidgets('não oferece biometria (fora do MVP)', (tester) async {
      await _abrir(tester, const LoginTela());
      expect(find.text('Entrar com biometria'), findsNothing);
    });

    testWidgets('senha errada mostra o erro em português e não sai da tela', (tester) async {
      final servico = ServicoAuthFake(
        contas: {'mariana@email.com': 'segredo123'},
        aceitaQualquerLogin: false,
      );
      await _abrir(tester, LoginTela(servico: servico));
      await _digitar(tester, 'E-mail, CPF ou telefone', 'mariana@email.com');
      await _digitar(tester, 'Senha', 'errada999');

      await _tocar(tester, 'Entrar');

      expect(find.text('E-mail, CPF, celular ou senha incorretos.'), findsOneWidget);
      expect(find.byType(CascaClienteTela), findsNothing);
      expect(servico.sessaoAtual, isNull);
    });

    testWidgets('senha certa entra com a conta cadastrada', (tester) async {
      final servico = ServicoAuthFake(
        contas: {'mariana@email.com': 'segredo123'},
        aceitaQualquerLogin: false,
      );
      await _abrir(tester, LoginTela(servico: servico));
      await _digitar(tester, 'E-mail, CPF ou telefone', 'Mariana@Email.com');
      await _digitar(tester, 'Senha', 'segredo123');

      await _tocar(tester, 'Entrar');

      expect(find.byType(CascaClienteTela), findsOneWidget);
      expect(servico.sessaoAtual?.email, 'mariana@email.com');
    });

    testWidgets('sem internet mostra o erro', (tester) async {
      final servico = ServicoAuthFake()..falharNaProxima = const ErroAuth(TipoErroAuth.semInternet);
      await _abrir(tester, LoginTela(servico: servico));
      await _digitar(tester, 'E-mail, CPF ou telefone', 'mariana@email.com');
      await _digitar(tester, 'Senha', 'segredo123');

      await _tocar(tester, 'Entrar');

      expect(find.text('Sem internet. Confira sua conexão e tente de novo.'), findsOneWidget);
      expect(find.byType(CascaClienteTela), findsNothing);
    });

    testWidgets('aceita entrar com CPF ou telefone e barra identificador curto', (tester) async {
      await _abrir(tester, const LoginTela());
      await _digitar(tester, 'E-mail, CPF ou telefone', '12345');
      await _digitar(tester, 'Senha', 'segredo123');

      await _tocar(tester, 'Entrar');

      expect(
        find.text(
          'Identificador incompleto. Digite um e-mail válido, CPF (11 números) ou telefone com DDD.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CascaClienteTela), findsNothing);

      await _digitar(tester, 'E-mail, CPF ou telefone', '12345678909');
      await _tocar(tester, 'Entrar');
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('Google habilitado entra', (tester) async {
      final servico = ServicoAuthFake();
      await _abrir(tester, LoginTela(servico: servico));
      await _tocar(tester, 'Entrar com Google');
      expect(find.byType(CascaClienteTela), findsOneWidget);
      expect(servico.sessaoAtual?.id, 'fake-google');
    });

    testWidgets('Google desabilitado não aparece', (tester) async {
      await _abrir(tester, LoginTela(servico: ServicoAuthFake(provedores: {})));
      expect(find.text('Entrar com Google'), findsNothing);
      expect(find.text('Entrar com Apple'), findsNothing);
    });

    testWidgets('Google cancelado some em silêncio; outro erro aparece', (tester) async {
      final servico = ServicoAuthFake()..falharNaProxima = const ErroAuth(TipoErroAuth.cancelado);
      await _abrir(tester, LoginTela(servico: servico));
      await _tocar(tester, 'Entrar com Google');
      expect(find.byType(CascaClienteTela), findsNothing);
      expect(find.text('Entrada cancelada.'), findsNothing);

      servico.falharNaProxima = const ErroAuth(TipoErroAuth.desconhecido);
      await _tocar(tester, 'Entrar com Google');
      expect(find.text('Algo deu errado. Tente de novo.'), findsOneWidget);
    });

    testWidgets('Apple só aparece no iOS', (tester) async {
      await _abrir(tester, LoginTela(servico: ServicoAuthFake()));
      expect(find.text('Entrar com Apple'), findsNothing);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _abrir(tester, LoginTela(servico: ServicoAuthFake(), key: UniqueKey()));
        await tester.pumpAndSettle();
        await _tocar(tester, 'Entrar com Apple');
        expect(find.byType(CascaClienteTela), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('no iOS, Apple desabilitada no serviço não aparece', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _abrir(
            tester, LoginTela(servico: ServicoAuthFake(provedores: {ProvedorAuth.google})));
        expect(find.text('Entrar com Apple'), findsNothing);
        expect(find.text('Entrar com Google'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('e-mail não confirmado avisa e oferece reenviar', (tester) async {
      final servico = ServicoAuthFake()
        ..falharNaProxima = const ErroAuth(TipoErroAuth.emailNaoConfirmado);
      await _abrir(tester, LoginTela(servico: servico));
      await tester.enterText(find.byType(TextField).at(0), 'mariana@email.com');
      await tester.enterText(find.byType(TextField).at(1), 'segredo123');
      await tester.tap(find.text('Entrar').last);
      await tester.pumpAndSettle();

      expect(find.text('Confirme seu e-mail para entrar.'), findsOneWidget);
      await _tocar(tester, 'Reenviar e-mail de confirmação');
      expect(servico.emailsReenviados, 1);
      expect(find.textContaining('Enviamos um e-mail novo'), findsOneWidget);
    });

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
      await _digitar(tester, 'CPF', '12345678909');
      await _digitar(tester, 'Nascimento', '15031990');
      await _digitar(tester, 'Celular', '31987654417');
      await _digitar(tester, 'E-mail', 'mariana@email.com');
      await _digitar(tester, 'Senha', 'segredo123');
    }

    testWidgets('mostra "Passo 1 de 2" e valida tudo ao tentar criar', (tester) async {
      await _abrir(tester, const CriarContaTela());
      expect(find.text('Passo 1 de 2'), findsOneWidget);

      await _tocar(tester, 'Criar conta');

      expect(
        find.text('Nome muito curto. Digite seu nome completo (mínimo de 3 letras).'),
        findsOneWidget,
      );
      expect(
        find.text('CPF incompleto. Digite os 11 números do seu documento.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Termos não aceitos. Marque a caixa para concordar com os Termos de uso e continuar.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ConfirmarCelularTela), findsNothing);
    });

    testWidgets('sem aceitar os termos não avança', (tester) async {
      await _abrir(tester, const CriarContaTela());
      await preencher(tester);

      await _tocar(tester, 'Criar conta');

      expect(
        find.text(
          'Termos não aceitos. Marque a caixa para concordar com os Termos de uso e continuar.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ConfirmarCelularTela), findsNothing);
    });

    testWidgets('formulário certo leva a "Confirme seu e-mail" (passo 2)', (tester) async {
      await _abrir(
        tester,
        CriarContaTela(servico: ServicoAuthFake(exigeConfirmacaoEmail: true)),
      );
      await preencher(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      await _tocar(tester, 'Criar conta');

      expect(find.byType(ConfirmarEmailTela), findsOneWidget);
      expect(find.byType(ConfirmarCelularTela), findsNothing);
      expect(find.text('Passo 2 de 2'), findsOneWidget);
      expect(find.textContaining('mariana@email.com', findRichText: true), findsOneWidget);
    });

    testWidgets('sem confirmação de e-mail entra direto na casca, sem tela de SMS', (tester) async {
      await _abrir(tester, const CriarContaTela());
      await preencher(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      await _tocar(tester, 'Criar conta');

      expect(find.byType(CascaClienteTela), findsOneWidget);
      expect(find.byType(ConfirmarCelularTela), findsNothing);
    });

    Future<void> aceitarETocar(WidgetTester tester) async {
      await preencher(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await _tocar(tester, 'Criar conta');
    }

    testWidgets('e-mail já usado mostra o erro e fica no passo 1', (tester) async {
      final servico = ServicoAuthFake(contas: {'mariana@email.com': 'outra12345'});
      await _abrir(tester, CriarContaTela(servico: servico));

      await aceitarETocar(tester);

      expect(find.text('Este e-mail já tem uma conta. Tente entrar.'), findsOneWidget);
      expect(find.byType(ConfirmarCelularTela), findsNothing);
    });

    testWidgets('CPF já usado mostra o erro e fica no passo 1', (tester) async {
      final servico = ServicoAuthFake();
      await servico.criarConta(const DadosCadastro(
        nome: 'Outra Pessoa',
        email: 'outra@email.com',
        senha: _senha,
        celular: '(11) 91234-5678',
        cpf: '123.456.789-09',
      ));
      await servico.sair();
      await _abrir(tester, CriarContaTela(servico: servico));

      await aceitarETocar(tester);

      expect(find.text('Este CPF já está cadastrado em outra conta.'), findsOneWidget);
      expect(find.byType(CascaClienteTela), findsNothing);
    });

    testWidgets('sem internet mostra o erro e fica no passo 1', (tester) async {
      final servico = ServicoAuthFake()..falharNaProxima = const ErroAuth(TipoErroAuth.semInternet);
      await _abrir(tester, CriarContaTela(servico: servico));

      await aceitarETocar(tester);

      expect(find.text('Sem internet. Confira sua conexão e tente de novo.'), findsOneWidget);
      expect(find.byType(ConfirmarCelularTela), findsNothing);
    });

    testWidgets('conta criada fica na sessão do serviço', (tester) async {
      final servico = ServicoAuthFake();
      await _abrir(tester, CriarContaTela(servico: servico));

      await aceitarETocar(tester);

      expect(servico.sessaoAtual?.email, 'mariana@email.com');
      expect(servico.sessaoAtual?.nome, 'Mariana Alves');
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });
  });

  group('confirmar e-mail', () {
    Future<ServicoAuthFake> cadastrar(WidgetTester tester) async {
      final servico = ServicoAuthFake(exigeConfirmacaoEmail: true);
      await _abrir(tester, CriarContaTela(servico: servico));
      await _digitar(tester, 'Nome completo', 'Mariana Alves');
      await _digitar(tester, 'CPF', '12345678909');
      await _digitar(tester, 'Nascimento', '15031990');
      await _digitar(tester, 'Celular', '31987654417');
      await _digitar(tester, 'E-mail', 'mariana@email.com');
      await _digitar(tester, 'Senha', 'segredo123');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await _tocar(tester, 'Criar conta');
      return servico;
    }

    testWidgets('cadastro → Confirme seu e-mail → Já confirmei → casca', (tester) async {
      final servico = await cadastrar(tester);
      expect(find.text('Confirme seu e-mail'), findsOneWidget);

      // Antes de abrir o link: fica na tela, com aviso.
      await _tocar(tester, 'Já confirmei');
      expect(find.byType(ConfirmarEmailTela), findsOneWidget);
      expect(find.textContaining('Ainda não confirmamos'), findsOneWidget);

      servico.confirmarEmail('mariana@email.com');
      await _tocar(tester, 'Já confirmei');

      expect(find.byType(CascaClienteTela), findsOneWidget);
      expect(servico.sessaoAtual?.email, 'mariana@email.com');
    });

    testWidgets('reenviar só libera depois de 60 s e a espera recomeça', (tester) async {
      final servico = await cadastrar(tester);
      expect(find.text('Reenviar e-mail'), findsNothing);
      expect(find.text('Reenviar e-mail em 1:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 60));
      await _tocar(tester, 'Reenviar e-mail');

      expect(servico.emailsReenviados, 1);
      expect(find.text('Enviamos um e-mail novo.'), findsOneWidget);
      expect(find.text('Reenviar e-mail em 1:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('Trocar e-mail volta ao formulário', (tester) async {
      await cadastrar(tester);
      await _tocar(tester, 'Trocar e-mail');
      expect(find.byType(CriarContaTela), findsOneWidget);
    });
  });

  group('confirmar celular', () {
    testWidgets('código incompleto mostra erro; completo leva ao app', (tester) async {
      await _abrir(tester, const ConfirmarCelularTela(celular: _celularDigitado));

      await _tocar(tester, 'Confirmar código');
      expect(
        find.text('Código incompleto. Digite os 6 números recebidos por SMS.'),
        findsOneWidget,
      );

      await _digitar(tester, 'Código', '123456');
      await _tocar(tester, 'Confirmar código');
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('código errado mostra o erro; o certo (do teste) entra', (tester) async {
      final servico = ServicoAuthFake(codigoCelular: '654321');
      await _abrir(tester, ConfirmarCelularTela(celular: _celularDigitado, servico: servico));

      await _digitar(tester, 'Código', '123456');
      await _tocar(tester, 'Confirmar código');
      expect(find.text('Código incorreto. Confira e tente de novo.'), findsOneWidget);
      expect(find.byType(CascaClienteTela), findsNothing);

      await _digitar(tester, 'Código', '654321');
      await _tocar(tester, 'Confirmar código');
      expect(find.byType(CascaClienteTela), findsOneWidget);
    });

    testWidgets('depois de 5 erros pede um código novo', (tester) async {
      final servico = ServicoAuthFake();
      await _abrir(tester, ConfirmarCelularTela(celular: _celularDigitado, servico: servico));

      for (var i = 0; i < LimitesCodigoCelular.maxTentativas; i++) {
        await _digitar(tester, 'Código', '000000');
        await _tocar(tester, 'Confirmar código');
      }
      expect(find.text('Muitas tentativas. Peça um código novo.'), findsOneWidget);

      // Mesmo o código certo não vale mais.
      await _digitar(tester, 'Código', '123456');
      await _tocar(tester, 'Confirmar código');
      expect(find.byType(CascaClienteTela), findsNothing);
    });

    testWidgets('sem internet ao confirmar mostra o erro', (tester) async {
      final servico = ServicoAuthFake()..falharNaProxima = const ErroAuth(TipoErroAuth.semInternet);
      await _abrir(tester, ConfirmarCelularTela(celular: _celularDigitado, servico: servico));
      await _digitar(tester, 'Código', '123456');

      await _tocar(tester, 'Confirmar código');

      expect(find.text('Sem internet. Confira sua conexão e tente de novo.'), findsOneWidget);
    });

    testWidgets('reenvio só libera depois de 60 s e para depois de 3 reenvios', (tester) async {
      var agora = DateTime(2026, 10, 29, 12);
      final servico = ServicoAuthFake(agora: () => agora);
      await _abrir(tester, ConfirmarCelularTela(celular: _celularDigitado, servico: servico));
      expect(find.text('Reenviar em 1:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Reenviar em 0:59'), findsOneWidget);
      expect(find.text('Reenviar código'), findsNothing);

      await tester.pump(const Duration(seconds: 59));
      for (var i = 1; i <= LimitesCodigoCelular.maxReenvios; i++) {
        agora = agora.add(const Duration(seconds: 60));
        expect(find.text('Reenviar código'), findsOneWidget);
        await _tocar(tester, 'Reenviar código');
        expect(find.text('Enviamos um código novo.'), findsOneWidget);
        expect(find.text('Reenviar em 1:00'), findsOneWidget);
        expect(servico.codigosEnviados, i + 1);
        await tester.pump(const Duration(seconds: 60));
      }

      agora = agora.add(const Duration(seconds: 60));
      await _tocar(tester, 'Reenviar código');
      expect(find.text('Você já pediu códigos demais. Tente mais tarde.'), findsOneWidget);
      expect(servico.codigosEnviados, 1 + LimitesCodigoCelular.maxReenvios);
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
    testWidgets('e-mail inválido mostra erro; válido confirma o envio', (tester) async {
      await _abrir(tester, const RecuperarSenhaTela());

      await _digitar(tester, 'E-mail', 'mariana');
      await _tocar(tester, 'Enviar código');
      expect(
        find.text('E-mail incompleto ou sem arroba. Digite no formato nome@exemplo.com.'),
        findsOneWidget,
      );

      await _digitar(tester, 'E-mail', 'mariana@email.com');
      await _tocar(tester, 'Enviar código');
      expect(find.textContaining('você vai receber as instruções'), findsOneWidget);
      expect(
        find.text('E-mail incompleto ou sem arroba. Digite no formato nome@exemplo.com.'),
        findsNothing,
      );
    });

    testWidgets('sem internet ao recuperar mostra o erro', (tester) async {
      final servico = ServicoAuthFake()..falharNaProxima = const ErroAuth(TipoErroAuth.semInternet);
      await _abrir(tester, RecuperarSenhaTela(servico: servico));
      await _digitar(tester, 'E-mail', 'mariana@email.com');

      await _tocar(tester, 'Enviar código');

      expect(find.text('Sem internet. Confira sua conexão e tente de novo.'), findsOneWidget);
      expect(find.textContaining('você vai receber as instruções'), findsNothing);
    });

    testWidgets('Fale com o suporte abre a central de ajuda', (tester) async {
      await _abrir(tester, const RecuperarSenhaTela());
      await _tocar(tester, 'Fale com o suporte');
      expect(find.byType(AjudaTela), findsOneWidget);
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
