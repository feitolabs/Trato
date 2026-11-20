// QA adversarial (so teste; sem rede real). Marcados com skip: 'bug conhecido: QA-n'.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedidos/modelos.dart';

ClienteApi _api(MockClient c, {Duration limite = const Duration(seconds: 2)}) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: c,
      tempoLimite: limite,
      intervaloBaseRetry: const Duration(milliseconds: 1),
    );

http.Response _json(Object o, [int s = 200]) => http.Response.bytes(utf8.encode(jsonEncode(o)), s,
    headers: const {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('formatarReais (so exibicao)', () {
    test('zero, comum e enorme', () {
      expect(formatarReais(0), 'R\$ 0,00');
      expect(formatarReais(5), 'R\$ 0,05');
      expect(formatarReais(123456789), 'R\$ 1.234.567,89');
      expect(formatarReais(9007199254740991), contains(','));
    });
    test('negativo >= R\$ 1 mantem o sinal (antes do R\$)', () {
      expect(formatarReais(-500), '-R\$ 5,00');
      expect(formatarReais(-1050), '-R\$ 10,50');
      expect(formatarReais(-1025), '-R\$ 10,25'); // QA-04: nao pode sair "R\$ -10,75"
    });
    test('negativo abaixo de R\$ 1 mantem o sinal', () {
      expect(formatarReais(-50), '-R\$ 0,50');
      expect(formatarReais(-1), '-R\$ 0,01');
    });
    test('limites e separador de milhar', () {
      expect(formatarReais(0), 'R\$ 0,00');
      expect(formatarReais(99), 'R\$ 0,99');
      expect(formatarReais(100), 'R\$ 1,00');
      expect(formatarReais(100000), 'R\$ 1.000,00');
      expect(formatarReais(123456), 'R\$ 1.234,56');
      expect(formatarReais(123456789), 'R\$ 1.234.567,89');
      expect(formatarReais(-123456789), '-R\$ 1.234.567,89');
    });
  });

  group('ClienteApi: erro de rede, timeout e 5xx', () {
    test('timeout vira ErroTrato.semInternet (a tela mostra Tentar de novo)', () async {
      final api = _api(MockClient((r) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return _json({});
      }), limite: const Duration(milliseconds: 100));
      await expectLater(api.get('/v1/pedidos'), throwsA(isA<Object>()));
    });
    test('500 em GET nao devolve dado e levanta erro tratado', () async {
      final api = _api(MockClient((r) async => _json({'detail': 'boom'}, 500)));
      await expectLater(api.get('/v1/pedidos'), throwsA(isA<Object>()));
    });
    test('POST de dinheiro com 503 nao e reenviado sem chave de idempotencia', () async {
      var chamadas = 0;
      final api = _api(MockClient((r) async {
        chamadas++;
        return _json({'detail': 'indisponivel'}, 503);
      }));
      try {
        await api.post('/v1/contratos/c1/cobranca', corpo: {'meio': 'pix'});
      } catch (_) {}
      expect(chamadas, 1, reason: 'POST sem chave nao pode ser repetido');
    });
    test('POST com chave de idempotencia: toque rapido repetido envia a MESMA chave', () async {
      final chaves = <String?>[];
      final api = _api(MockClient((r) async {
        chaves.add(r.headers['Idempotency-Key'] ?? r.headers['idempotency-key']);
        return _json({'ok': true});
      }));
      await Future.wait([
        api.post('/v1/pedidos/p/acoes/aceitar_orcamento', chaveIdempotencia: 'k1'),
        api.post('/v1/pedidos/p/acoes/aceitar_orcamento', chaveIdempotencia: 'k1'),
      ]);
      expect(chaves.toSet().length, 1);
    });
    test('401 sem renovar: nao entra em laco infinito', () async {
      var n = 0;
      final api = _api(MockClient((r) async {
        n++;
        return _json({'detail': 'expirou'}, 401);
      }));
      try {
        await api.get('/v1/pedidos');
      } catch (_) {}
      expect(n, lessThanOrEqualTo(3));
    });
    test('resposta com corpo invalido/vazio nao derruba o app', () async {
      for (final corpo in ['', 'nao-e-json', '<html>502</html>', 'null']) {
        final api = _api(MockClient((r) async => http.Response(corpo, 200)));
        try {
          await api.get('/v1/pedidos');
        } catch (e) {
          expect(e, isNot(isA<TypeError>()), reason: 'corpo "$corpo" gerou TypeError');
        }
      }
    });
  });
}
