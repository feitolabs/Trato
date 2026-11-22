import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/servico_push.dart';
import 'package:trato/dispositivo/servico_push_firebase.dart';
import 'package:trato/telas/fluxo/rotas.dart';

class _AuthSessaoTeste implements ServicoAuth {
  _AuthSessaoTeste(this._sessao);

  SessaoAuth? _sessao;

  @override
  SessaoAuth? get sessaoAtual => _sessao;

  @override
  Future<void> sair() async {
    _sessao = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('F54 — Push Firebase FCM', () {
    test('inicializarFirebaseComSeguranca retorna false sem lançar quando Firebase falha',
        () async {
      final ok = await inicializarFirebaseComSeguranca(
        jaInicializado: () => false,
        inicializar: () async => throw StateError('sem google-services'),
      );
      expect(ok, isFalse);
    });

    test('inicializarFirebaseComSeguranca retorna true quando inicializa ou já está pronto',
        () async {
      var chamou = 0;
      final ok1 = await inicializarFirebaseComSeguranca(
        jaInicializado: () => false,
        inicializar: () async => chamou++,
      );
      final ok2 = await inicializarFirebaseComSeguranca(
        jaInicializado: () => true,
        inicializar: () async => chamou++,
      );
      expect(ok1, isTrue);
      expect(ok2, isTrue);
      expect(chamou, 1);
    });

    test('ServicoPushFirebase pede permissão, obtém token e repassa onTokenRefresh', () async {
      final refresh = StreamController<String>.broadcast();
      var pediuPermissao = false;
      final servico = ServicoPushFirebase(
        garantirFirebase: () async => true,
        pedirPermissao: () async {
          pediuPermissao = true;
          return true;
        },
        obterTokenFcm: () async => 'token-fcm-inicial-12345',
        streamTokenRefresh: () => refresh.stream,
        plataformaAtual: () => 'android',
      );

      final recebidos = <TokenPushDispositivo>[];
      final sub = servico.aoAtualizarToken.listen(recebidos.add);

      final token = await servico.obterToken();
      expect(pediuPermissao, isTrue);
      expect(token, isNotNull);
      expect(token!.token, 'token-fcm-inicial-12345');
      expect(token.plataforma, 'android');

      refresh.add('token-fcm-renovado-67890');
      await Future<void>.delayed(Duration.zero);
      expect(recebidos, hasLength(1));
      expect(recebidos.first.token, 'token-fcm-renovado-67890');
      expect(recebidos.first.plataforma, 'android');

      await sub.cancel();
      await servico.encerrar();
      await refresh.close();
    });

    test('ServicoPushFirebase retorna null quando permissão é negada ou ocorre falha', () async {
      var chamouToken = false;
      final negado = ServicoPushFirebase(
        garantirFirebase: () async => true,
        pedirPermissao: () async => false,
        obterTokenFcm: () async {
          chamouToken = true;
          return 'token-nao-deve-ser-lido';
        },
        streamTokenRefresh: () => const Stream<String>.empty(),
        plataformaAtual: () => 'android',
      );
      expect(await negado.obterToken(), isNull);
      expect(chamouToken, isFalse);
      await negado.encerrar();

      final erro = ServicoPushFirebase(
        garantirFirebase: () async => true,
        pedirPermissao: () async => true,
        obterTokenFcm: () async => throw Exception('rede fora'),
        streamTokenRefresh: () => const Stream<String>.empty(),
        plataformaAtual: () => 'android',
      );
      expect(await erro.obterToken(), isNull);
      await erro.encerrar();
    });

    test(
        'RotasTrato.sincronizarPush registra token inicial e refresh em POST /v1/dispositivos e respeita sessão',
        () async {
      final chamadas = <({String metodo, String caminho, Map<String, dynamic> corpo})>[];
      final httpMock = MockClient((req) async {
        if (req.url.path == '/v1/dispositivos') {
          final corpo =
              req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
          chamadas.add((metodo: req.method, caminho: req.url.path, corpo: corpo));
          return http.Response('', 204);
        }
        return http.Response('{}', 200);
      });

      final sessao = SessaoTrato()..entrar('jwt-teste');
      final refresh = StreamController<String>.broadcast();
      final push = ServicoPushFirebase(
        garantirFirebase: () async => true,
        pedirPermissao: () async => true,
        obterTokenFcm: () async => 'fcm-token-android-001',
        streamTokenRefresh: () => refresh.stream,
        plataformaAtual: () => 'android',
      );

      final reposAnterior = RotasTrato.repos;
      final sessaoAnterior = RotasTrato.sessao;
      final pushAnterior = RotasTrato.push;
      final authAnterior = ServicoAuthPadrao.atual;
      final authTeste = _AuthSessaoTeste(
        const SessaoAuth(id: 'u1', email: 'teste@trato.app', perfil: 'cliente'),
      );
      try {
        ServicoAuthPadrao.atual = authTeste;
        RotasTrato.sessao = sessao;
        RotasTrato.push = push;
        RotasTrato.repos = RepositoriosTrato.api(
          ClienteApi(urlBase: 'https://api.teste', sessao: sessao, cliente: httpMock),
        );
        await RotasTrato.resetarPushParaTeste();

        await RotasTrato.sincronizarPush();
        expect(chamadas, hasLength(1));
        expect(chamadas.first.metodo, 'POST');
        expect(chamadas.first.caminho, '/v1/dispositivos');
        expect(chamadas.first.corpo, {
          'token': 'fcm-token-android-001',
          'plataforma': 'android',
        });
        expect(push.ultimoTokenRegistrado, 'fcm-token-android-001');

        refresh.add('fcm-token-android-002');
        await Future<void>.delayed(Duration.zero);
        expect(chamadas, hasLength(2));
        expect(chamadas[1].metodo, 'POST');
        expect(chamadas[1].corpo['token'], 'fcm-token-android-002');

        // Desregistro explícito usa DELETE /v1/dispositivos.
        await RotasTrato.repos.notificacoes.removerDispositivo('fcm-token-android-002');
        expect(chamadas, hasLength(3));
        expect(chamadas[2].metodo, 'DELETE');
        expect(chamadas[2].caminho, '/v1/dispositivos');
        expect(chamadas[2].corpo, {'token': 'fcm-token-android-002'});

        // Sem sessão, novo refresh não chama o backend.
        await authTeste.sair();
        sessao.sair();
        refresh.add('fcm-token-android-003');
        await Future<void>.delayed(Duration.zero);
        expect(chamadas, hasLength(3));
      } finally {
        await RotasTrato.resetarPushParaTeste();
        ServicoAuthPadrao.atual = authAnterior;
        RotasTrato.repos = reposAnterior;
        RotasTrato.sessao = sessaoAnterior;
        RotasTrato.push = pushAnterior;
        await push.encerrar();
        await refresh.close();
      }
    });
  });
}
