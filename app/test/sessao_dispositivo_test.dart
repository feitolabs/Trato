import 'package:flutter_test/flutter_test.dart';
import 'package:trato/auth/ligacao_sessao.dart';
import 'package:trato/auth/servico_auth_fake.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/check_in_dispositivo.dart';
import 'package:trato/dispositivo/dispositivo.dart';
import 'package:trato/telas/profissional/servico_check_in_fake.dart';

const _credencialDeTeste = 'abc12345';

void main() {
  group('LigacaoSessao', () {
    test('o token do login chega à sessão e sai ao sair', () async {
      final auth = ServicoAuthFake();
      final sessao = SessaoTrato();
      final ligacao = LigacaoSessao(auth, sessao);
      addTearDown(ligacao.encerrar);
      expect(sessao.logada, isFalse);

      await auth.entrarComEmail(email: 'mariana@email.com', senha: _credencialDeTeste);
      await Future<void>.delayed(Duration.zero);
      expect(sessao.logada, isTrue);
      expect(sessao.token, auth.tokenAtual);

      await auth.sair();
      await Future<void>.delayed(Duration.zero);
      expect(sessao.logada, isFalse);
      expect(sessao.token, isNull);
    });

    test('já logado ao ligar: pega o token na hora', () async {
      final auth = ServicoAuthFake();
      await auth.entrarComEmail(email: 'mariana@email.com', senha: _credencialDeTeste);
      final sessao = SessaoTrato();
      final ligacao = LigacaoSessao(auth, sessao);
      addTearDown(ligacao.encerrar);
      expect(sessao.token, auth.tokenAtual);
    });
  });

  group('Dispositivo', () {
    test('foto devolve só a referência; cancelar devolve null', () async {
      final ok = DispositivoTrato(camera: CapturaFotoFake(), localizador: LocalizadorFake());
      expect(await ok.fotografarEEnviar(), 'fake://foto/1');
      final cancelado = DispositivoTrato(
        camera: CapturaFotoFake(cancelar: true),
        localizador: LocalizadorFake(),
      );
      expect(await cancelado.fotografarEEnviar(), isNull);
    });

    test('check-in usa câmera e GPS; sem posição não libera o passo', () async {
      final disp = DispositivoTrato.fake();
      final servico = ServicoCheckInDispositivo(base: ServicoCheckInFake(), dispositivo: disp);
      expect(await servico.tirarFoto(), isNotNull);
      expect(servico.ultimaFoto, startsWith('fake://'));
      expect(await servico.localizar(), isNotNull);
      expect(servico.ultimaPosicao, isNotNull);

      final semGps = ServicoCheckInDispositivo(
        base: ServicoCheckInFake(),
        dispositivo: DispositivoTrato(
          camera: CapturaFotoFake(),
          localizador: LocalizadorFake(posicao: null),
        ),
      );
      expect(await semGps.localizar(), isNull);
    });
  });
}
