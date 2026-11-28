// FL-REATIVAR-4.9: 403 conta_inativa separado de conta_bloqueada e reativação gratuita.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/conta_inativa/conta_inativa_tela.dart';

import 'apoio/fontes.dart';

http.Response _json(Object corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(carregarFontesTrato);

  group('ClienteApi e RepositorioPerfilApi — conta_inativa (4.9)', () {
    test('403 conta_inativa dispara aoInativar sem disparar aoBloquear nem logout', () async {
      String? msgInativa;
      String? msgBloqueada;
      var expirou = false;
      final sessao = SessaoTrato()
        ..entrar('token-teste')
        ..aoInativar = (m) {
          msgInativa = m;
        }
        ..aoBloquear = (m) {
          msgBloqueada = m;
        }
        ..aoExpirar = () {
          expirou = true;
        };

      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient(
          (_) async => _json(
            {
              'detail': 'Sua conta está inativa por falta de uso.',
              'codigo': 'conta_inativa',
            },
            403,
          ),
        ),
      );

      await expectLater(
        () => api.get('/v1/me'),
        throwsA(
          isA<ErroTrato>()
              .having((e) => e.codigoHttp, 'codigoHttp', 403)
              .having((e) => e.codigo, 'codigo', 'conta_inativa'),
        ),
      );
      expect(msgInativa, 'Sua conta está inativa por falta de uso.');
      expect(msgBloqueada, isNull);
      expect(expirou, isFalse);
      expect(sessao.logada, isTrue);
    });

    test('403 conta_bloqueada continua disparando só aoBloquear', () async {
      String? msgInativa;
      String? msgBloqueada;
      final sessao = SessaoTrato()
        ..entrar('token-teste')
        ..aoInativar = (m) {
          msgInativa = m;
        }
        ..aoBloquear = (m) {
          msgBloqueada = m;
        };

      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient(
          (_) async => _json(
            {'detail': 'Conta bloqueada.', 'codigo': 'conta_bloqueada'},
            403,
          ),
        ),
      );

      await expectLater(
        () => api.get('/v1/me'),
        throwsA(isA<ErroTrato>().having((e) => e.codigo, 'codigo', 'conta_bloqueada')),
      );
      expect(msgBloqueada, 'Conta bloqueada.');
      expect(msgInativa, isNull);
    });

    test('RepositorioPerfilApi.reativarConta chama POST /v1/me/reativar', () async {
      http.Request? reqFeita;
      final sessao = SessaoTrato()..entrar('token-teste');
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((req) async {
          reqFeita = req;
          return _json({'usuario_id': 'u-1', 'status': 'ativo', 'reativada': true});
        }),
      );

      final ok = await RepositorioPerfilApi(api).reativarConta();
      expect(ok, isTrue);
      expect(reqFeita?.method, 'POST');
      expect(reqFeita?.url.path, '/v1/me/reativar');
    });
  });

  group('ContaInativaTela (4.9)', () {
    testWidgets('exibe mensagem, reativa gratuitamente, abre suporte e trata erro', (t) async {
      var tentativas = 0;
      var reativada = false;
      var abriuSuporte = false;
      var falhar = true;

      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: ContaInativaTela(
            mensagem: 'Sua conta está inativa por falta de uso.',
            aoReativar: () async {
              tentativas++;
              if (falhar) throw const ErroTrato(TipoErro.servidor, 'Sem conexão agora.');
            },
            aoReativada: () => reativada = true,
            aoFalar: () => abriuSuporte = true,
            aoSair: () async {},
          ),
        ),
      );

      expect(find.text('Conta inativa'), findsOneWidget);
      expect(find.text('Sua conta está inativa por falta de uso.'), findsOneWidget);
      expect(find.text('Reativar conta gratuitamente'), findsOneWidget);

      // Falha na primeira tentativa mostra erro junto do botão sem sair da tela.
      await t.tap(find.byKey(const Key('botao-reativar-conta')));
      await t.pumpAndSettle();
      expect(tentativas, 1);
      expect(reativada, isFalse);
      expect(find.byKey(const Key('erro-reativar-conta')), findsOneWidget);
      expect(find.text('Sem conexão agora.'), findsOneWidget);

      // Acesso ao suporte funciona.
      await t.tap(find.byKey(const Key('botao-suporte-inativa')));
      expect(abriuSuporte, isTrue);

      // Segunda tentativa bem-sucedida chama aoReativada.
      falhar = false;
      await t.tap(find.byKey(const Key('botao-reativar-conta')));
      await t.pumpAndSettle();
      expect(tentativas, 2);
      expect(reativada, isTrue);
    });
  });
}
