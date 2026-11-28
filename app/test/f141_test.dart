// APP-ACESSOS: Termos 14.3/16.1, dados do aparelho e aviso de login, renovação e saída.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/auth/ligacao_sessao.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/aparelho_do_acesso.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/dispositivo/relato_bug.dart' show versaoDoApp;

/// Token de mentira, só com o `sub` que o app lê.
String _token(String usuario, int n) =>
    'x.${base64Url.encode(utf8.encode(jsonEncode({'sub': usuario, 'n': n})))}.y';

class _Auth implements ServicoAuth {
  SessaoAuth? quem;
  String? atual;
  String? proximo;
  final mudancas = StreamController<SessaoAuth?>.broadcast(sync: true);

  @override
  SessaoAuth? get sessaoAtual => quem;

  @override
  Stream<SessaoAuth?> get sessaoMudou => mudancas.stream;

  @override
  String? get tokenAtual => atual;

  @override
  Future<String?> renovarToken() async => proximo;

  void emitir(String? token, {SessaoAuth? sessao}) {
    atual = token;
    quem = token == null ? null : sessao;
    mudancas.add(quem);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pessoa = SessaoAuth(id: 'u1', nome: 'Exemplo', email: 'a@exemplo.test');

Future<void> _assentar() => Future<void>.delayed(const Duration(milliseconds: 5));

(SessaoTrato, List<(String, String)>) _sessaoQueAnota() {
  final avisos = <(String, String)>[];
  final sessao = SessaoTrato()
    ..enviarAcesso = (evento, token) async => avisos.add((evento, token));
  return (sessao, avisos);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('id sorteado pelo app: 32 hex, o mesmo depois, outro numa instalação nova', () async {
    SharedPreferences.setMockInitialValues({});
    final primeiro = await idDeAcessoDoApp();
    expect(primeiro, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await idDeAcessoDoApp(), primeiro);
    final cabecalhos = await carregarCabecalhosDoAparelho();
    expect(cabecalhos, {
      'X-Dispositivo-Id': primeiro,
      'X-Aparelho-Tipo': 'android',
      'X-Sistema-Operacional': 'Android',
      'X-App-Versao': versaoDoApp,
    });
    SharedPreferences.setMockInitialValues({});
    expect(await idDeAcessoDoApp(), isNot(primeiro));
    SharedPreferences.setMockInitialValues({chaveDoIdDeAcesso: 'valor estranho'});
    expect(await idDeAcessoDoApp(), matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('cabeçalhos só nas chamadas com sessão', () async {
    final vistos = <Map<String, String>>[];
    final sessao = SessaoTrato()..cabecalhosDoAparelho = {'X-Dispositivo-Id': 'abc'};
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: sessao,
      cliente: MockClient((r) async {
        vistos.add(r.headers);
        return http.Response('{}', 200);
      }),
    );
    await api.get('/v1/a');
    await api.post('/v1/b', token: _token('u1', 1));
    sessao.entrar(_token('u1', 1));
    await api.get('/v1/c');
    await api.getBytes('/v1/d');
    expect([for (final h in vistos) h['X-Dispositivo-Id']], [null, 'abc', 'abc', 'abc']);
  });

  for (final status in [200, 401, 404, 500]) {
    test('aviso com resposta $status: uma chamada, sem renovar nem sair', () async {
      final chamadas = <http.Request>[];
      var renovacoes = 0;
      final sessao = SessaoTrato()
        ..entrar('t1')
        ..cabecalhosDoAparelho = {'X-Aparelho-Tipo': 'android'}
        ..renovar = () async {
          renovacoes++;
          return 't2';
        };
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: sessao,
        cliente: MockClient((r) async {
          chamadas.add(r);
          return http.Response('{"registrado": false}', status);
        }),
      );
      sessao.enviarAcesso = api.enviarAcesso;
      await sessao.avisarAcesso('logout');
      expect(chamadas, hasLength(1));
      expect(chamadas.single.url.path, '/v1/me/acessos');
      expect(jsonDecode(chamadas.single.body), {'evento': 'logout'});
      expect(chamadas.single.headers['Authorization'], 'Bearer t1');
      expect(chamadas.single.headers['X-Aparelho-Tipo'], 'android');
      expect(renovacoes, 0);
      expect(sessao.token, 't1');
    });
  }

  test('servidor lento ou sem rede não segura a saída', () async {
    final sessao = SessaoTrato()
      ..entrar('t1')
      ..limiteDoAcesso = const Duration(milliseconds: 50)
      ..enviarAcesso = (_, __) => Completer<void>().future;
    final relogio = Stopwatch()..start();
    await sessao.avisarAcesso('logout');
    expect(relogio.elapsed, lessThan(const Duration(seconds: 2)));
    sessao.enviarAcesso = (_, __) async => throw StateError('sem rede');
    await sessao.avisarAcesso('logout');
    await sessao.sair();
    expect(sessao.logada, isFalse);
  });

  test('o limite padrão é curto; sem sessão nada é enviado', () async {
    final (sessao, avisos) = _sessaoQueAnota();
    expect(sessao.limiteDoAcesso, const Duration(seconds: 3));
    await sessao.avisarAcesso('logout');
    expect(avisos, isEmpty);
  });

  test('login avisa uma vez, depois do GET /v1/me, mesmo se ele falhar', () async {
    for (final falha in [false, true]) {
      final (sessao, avisos) = _sessaoQueAnota();
      final auth = _Auth();
      final me = Completer<void>();
      LigacaoSessao(auth, sessao, aoEntrar: () => me.future);
      final t1 = _token('u1', 1);
      auth.emitir(t1, sessao: _pessoa);
      auth.emitir(t1, sessao: _pessoa);
      await _assentar();
      expect(avisos, isEmpty);
      falha ? me.completeError(StateError('fora')) : me.complete();
      await _assentar();
      expect(avisos, [('login', t1)]);
    }
  });

  test('reabrir o app não é login; renovação avisa uma vez, em qualquer ordem', () async {
    final t1 = _token('u1', 1), t2 = _token('u1', 2), t3 = _token('u1', 3);
    final (sessao, avisos) = _sessaoQueAnota();
    final auth = _Auth()
      ..quem = _pessoa
      ..atual = t1;
    LigacaoSessao(auth, sessao);
    await _assentar();
    expect(avisos, isEmpty);

    // Pelo 401: primeiro a renovação, depois o evento do provedor.
    auth.proximo = t2;
    expect(await sessao.renovarToken(), t2);
    auth.emitir(t2, sessao: _pessoa);
    await _assentar();
    expect(avisos, [('sessao_renovada', t2)]);

    // Pelo provedor: primeiro o evento, depois a renovação devolve o mesmo token.
    auth.emitir(t3, sessao: _pessoa);
    auth.proximo = t3;
    await sessao.renovarToken();
    await _assentar();
    expect(avisos, [('sessao_renovada', t2), ('sessao_renovada', t3)]);

    // Renovação que falha não avisa de novo.
    auth.proximo = null;
    await sessao.renovarToken();
    await _assentar();
    expect(avisos, hasLength(2));
  });

  test('sair e entrar de novo, ou outra conta, é login', () async {
    final (sessao, avisos) = _sessaoQueAnota();
    final auth = _Auth();
    LigacaoSessao(auth, sessao);
    auth.emitir(_token('u1', 1), sessao: _pessoa);
    await _assentar();
    auth.emitir(_token('u2', 1), sessao: _pessoa);
    await _assentar();
    auth.emitir(null);
    await _assentar();
    auth.emitir(_token('u2', 1), sessao: _pessoa);
    await _assentar();
    expect([for (final a in avisos) a.$1], ['login', 'login', 'login']);
  });
}
