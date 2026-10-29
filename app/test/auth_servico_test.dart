import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/config_auth.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/auth/servico_auth_fake.dart';

const _credencial = 'segredo123';
const _outraCredencial = 'errada';

const _dados = DadosCadastro(
  nome: 'Mariana Alves',
  email: 'Mariana@Email.com',
  senha: _credencial,
  celular: '(31) 98765-4417',
);

Matcher _erro(TipoErroAuth tipo) => isA<ErroAuth>().having((e) => e.tipo, 'tipo', tipo);

void main() {
  group('ServicoAuthFake', () {
    test('criar conta abre a sessão; sair fecha', () async {
      final s = ServicoAuthFake();
      final sessao = await s.criarConta(_dados);
      expect(sessao.email, 'mariana@email.com');
      expect(sessao.celularConfirmado, isFalse);
      expect(s.sessaoAtual, isNotNull);

      await s.sair();
      expect(s.sessaoAtual, isNull);
    });

    test('e-mail repetido (sem diferenciar maiúsculas) dá emailJaUsado', () async {
      final s = ServicoAuthFake();
      await s.criarConta(_dados);
      await expectLater(s.criarConta(_dados), throwsA(_erro(TipoErroAuth.emailJaUsado)));
    });

    test('login: conta criada entra; senha errada não', () async {
      final s = ServicoAuthFake(aceitaQualquerLogin: false);
      await expectLater(
        s.entrarComEmail(email: 'mariana@email.com', senha: _credencial),
        throwsA(_erro(TipoErroAuth.credenciaisInvalidas)),
      );
      await s.criarConta(_dados);
      await s.sair();
      await expectLater(
        s.entrarComEmail(email: 'mariana@email.com', senha: _outraCredencial),
        throwsA(_erro(TipoErroAuth.credenciaisInvalidas)),
      );
      final sessao = await s.entrarComEmail(email: ' MARIANA@email.com ', senha: _credencial);
      expect(sessao.id, s.sessaoAtual?.id);
    });

    test('sessaoMudou avisa entrada e saída', () async {
      final s = ServicoAuthFake();
      final eventos = <String?>[];
      final sub = s.sessaoMudou.listen((e) => eventos.add(e?.email));
      await s.entrarComEmail(email: 'a@b.com', senha: 'x');
      await s.sair();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(eventos, ['a@b.com', null]);
    });

    test('provedores só entram se habilitados', () async {
      final s = ServicoAuthFake(provedores: {ProvedorAuth.google});
      expect(s.provedorHabilitado(ProvedorAuth.google), isTrue);
      expect(s.provedorHabilitado(ProvedorAuth.apple), isFalse);
      await s.entrarComProvedor(ProvedorAuth.google);
      await expectLater(
        s.entrarComProvedor(ProvedorAuth.apple),
        throwsA(_erro(TipoErroAuth.provedorIndisponivel)),
      );
    });

    test('falharNaProxima vale uma vez só', () async {
      final s = ServicoAuthFake()..falharNaProxima = const ErroAuth(TipoErroAuth.semInternet);
      await expectLater(s.recuperarSenha('a@b.com'), throwsA(_erro(TipoErroAuth.semInternet)));
      await s.recuperarSenha('a@b.com');
    });

    test('código certo confirma o celular da conta', () async {
      final s = ServicoAuthFake(codigoCelular: '246810');
      await s.criarConta(_dados);
      final sessao = await s.confirmarCelular(celular: _dados.celular, codigo: '246810');
      expect(sessao.celularConfirmado, isTrue);
      expect(s.sessaoAtual?.celularConfirmado, isTrue);
    });

    test('5 códigos errados bloqueiam, até o certo; reenvio libera de novo', () async {
      var agora = DateTime(2026, 10, 29, 12);
      final s = ServicoAuthFake(agora: () => agora);
      await s.criarConta(_dados);
      for (var i = 1; i < LimitesCodigoCelular.maxTentativas; i++) {
        await expectLater(
          s.confirmarCelular(celular: _dados.celular, codigo: '000000'),
          throwsA(_erro(TipoErroAuth.codigoInvalido)),
        );
      }
      await expectLater(
        s.confirmarCelular(celular: _dados.celular, codigo: '000000'),
        throwsA(_erro(TipoErroAuth.tentativasEsgotadas)),
      );
      await expectLater(
        s.confirmarCelular(celular: _dados.celular, codigo: '123456'),
        throwsA(_erro(TipoErroAuth.tentativasEsgotadas)),
      );

      agora = agora.add(const Duration(seconds: 60));
      await s.reenviarCodigoCelular(_dados.celular);
      final sessao = await s.confirmarCelular(celular: _dados.celular, codigo: '123456');
      expect(sessao.celularConfirmado, isTrue);
    });

    test('reenvio: nada antes de 60 s e no máximo 3 vezes', () async {
      var agora = DateTime(2026, 10, 29, 12);
      final s = ServicoAuthFake(agora: () => agora);
      await s.criarConta(_dados);

      agora = agora.add(const Duration(seconds: 59));
      await expectLater(
        s.reenviarCodigoCelular(_dados.celular),
        throwsA(_erro(TipoErroAuth.reenvioMuitoCedo)),
      );

      for (var i = 0; i < LimitesCodigoCelular.maxReenvios; i++) {
        agora = agora.add(const Duration(seconds: 60));
        await s.reenviarCodigoCelular(_dados.celular);
        await expectLater(
          s.reenviarCodigoCelular(_dados.celular),
          throwsA(_erro(TipoErroAuth.reenvioMuitoCedo)),
        );
      }
      agora = agora.add(const Duration(seconds: 60));
      await expectLater(
        s.reenviarCodigoCelular(_dados.celular),
        throwsA(_erro(TipoErroAuth.reenviosEsgotados)),
      );
    });
  });

  group('ErroAuth e ConfigAuth', () {
    test('todo tipo de erro tem mensagem em português', () {
      for (final tipo in TipoErroAuth.values) {
        expect(ErroAuth(tipo).mensagem, isNotEmpty);
      }
    });

    test('sem chaves, o Supabase não está configurado', () {
      final c = ConfigAuth.doAmbiente();
      expect(c.supabaseConfigurado, isFalse);
      expect(c.googleConfigurado, isFalse);
      expect(const ConfigAuth(supabaseUrl: 'u', supabaseAnonKey: 'k').supabaseConfigurado, isTrue);
    });
  });
}
