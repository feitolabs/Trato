import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:trato/auth/config_auth.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/auth/servico_auth_supabase.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/sessao.dart';

const _senha = 'segredo123';
const _outra = 'errada123';

const _dados = DadosCadastro(
  nome: 'Mariana Alves',
  email: 'mariana@email.com',
  senha: _senha,
  celular: '(31) 98765-4417',
  cpf: '123.456.789-09',
  perfil: 'cliente',
);

Map<String, dynamic> _usuario(
        {List<Object?> identidades = const [
          {
            'id': 'i1',
            'user_id': '11111111-1111-1111-1111-111111111111',
            'provider': 'email'
          },
        ]}) =>
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'mariana@email.com',
      'created_at': '2026-10-30T12:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': {'nome': 'Mariana Alves', 'perfil': 'cliente'},
      'identities': identidades,
    };

http.Response _json(int status, Object corpo) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _erro(int status, String codigo, [Map<String, dynamic>? extra]) =>
    _json(status, {'error_code': codigo, 'msg': 'mensagem interna', ...?extra});

http.Response _apiPadrao(http.Request pedido) {
  if (pedido.url.path == '/v1/cadastro/cpf') {
    return _json(200, {'disponivel': true});
  }
  if (pedido.url.path == '/v1/me/dados-pessoais') return http.Response('', 204);
  return _json(404, {'detail': 'rota de teste não configurada'});
}

/// Cliente do Supabase e da API com a rede trocada; guarda os pedidos feitos.
({
  ServicoAuthSupabase servico,
  List<http.Request> pedidos,
  List<http.Request> apiPedidos,
  sb.SupabaseClient cliente
}) _montar(
  http.Response Function(http.Request) resposta, {
  http.Response Function(http.Request)? api,
  bool comApi = true,
}) {
  final pedidos = <http.Request>[];
  final apiPedidos = <http.Request>[];
  final cliente = sb.SupabaseClient(
    'https://teste.supabase.co',
    'chave-publica-de-teste',
    // Fluxo implícito: o PKCE exigiria um armazenamento assíncrono que o teste não precisa.
    authOptions:
        const sb.AuthClientOptions(authFlowType: sb.AuthFlowType.implicit),
    httpClient: MockClient((r) async {
      pedidos.add(r);
      return resposta(r);
    }),
  );
  final clienteApi = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato(),
    cliente: MockClient((r) async {
      apiPedidos.add(r);
      return (api ?? _apiPadrao)(r);
    }),
  );
  return (
    servico: ServicoAuthSupabase(
      const ConfigAuth(),
      cliente: cliente,
      api: comApi ? clienteApi : null,
    ),
    pedidos: pedidos,
    apiPedidos: apiPedidos,
    cliente: cliente
  );
}

Matcher _erroAuth(TipoErroAuth tipo) =>
    isA<ErroAuth>().having((e) => e.tipo, 'tipo', tipo);

void main() {
  group('criarConta', () {
    test('com sessão (confirmação desligada) entra direto', () async {
      final m = _montar((_) => _json(200, {
            'access_token': 'a.b.c',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'r',
            'user': _usuario(),
          }));
      final r = await m.servico.criarConta(_dados);
      expect(r, isA<CadastroComSessao>());
      expect((r as CadastroComSessao).sessao.email, 'mariana@email.com');
      await m.cliente.dispose();
    });

    test('com sessão: grava o CPF na API com o token do cadastro', () async {
      final m = _montar((_) => _json(200, {
            'access_token': 'a.b.c',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'r',
            'user': _usuario(),
          }));
      await m.servico.criarConta(_dados);

      expect(
        m.apiPedidos.map((r) => r.url.path),
        ['/v1/cadastro/cpf', '/v1/cadastro/vincular', '/v1/me/dados-pessoais'],
      );
      final salvar = m.apiPedidos.last;
      expect(salvar.headers['Authorization'], 'Bearer a.b.c');
      expect(jsonDecode(salvar.body), {'cpf': '12345678909'});
      await m.cliente.dispose();
    });

    test('modo demo (sem API) cadastra sem conferir nem gravar o CPF', () async {
      final m = _montar(
        (_) => _json(200, {
          'access_token': 'a.b.c',
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'r',
          'user': _usuario(),
        }),
        comApi: false,
      );
      final r = await m.servico.criarConta(_dados);
      expect(r, isA<CadastroComSessao>());
      expect(m.apiPedidos, isEmpty);
      await m.cliente.dispose();
    });

    test('CPF de outra conta nem chega a criar a conta', () async {
      final m = _montar(
        (_) => _json(200, _usuario()),
        api: (_) => _json(200, {'disponivel': false}),
      );
      await expectLater(
        m.servico.criarConta(_dados),
        throwsA(_erroAuth(TipoErroAuth.cpfJaUsado)),
      );
      expect(m.pedidos, isEmpty);
      await m.cliente.dispose();
    });

    test('409 ao gravar o CPF desloga e vira cpfJaUsado', () async {
      final m = _montar(
        (r) => r.url.path == '/auth/v1/logout'
            ? http.Response('', 204)
            : _json(200, {
                'access_token': 'a.b.c',
                'token_type': 'bearer',
                'expires_in': 3600,
                'refresh_token': 'r',
                'user': _usuario(),
              }),
        api: (r) => r.url.path == '/v1/me/dados-pessoais'
            ? _json(409, {'detail': 'Este CPF já está cadastrado em outra conta.'})
            : _json(200, {'disponivel': true}),
      );
      await expectLater(
        m.servico.criarConta(_dados),
        throwsA(_erroAuth(TipoErroAuth.cpfJaUsado)),
      );
      expect(m.pedidos.any((r) => r.url.path == '/auth/v1/logout'), isTrue);
      await m.cliente.dispose();
    });

    test('sem sessão (confirmação de e-mail ligada) aguarda confirmação',
        () async {
      final m = _montar((_) => _json(200, _usuario()));
      final r = await m.servico.criarConta(_dados);
      expect(r, isA<CadastroAguardandoEmail>());
      expect((r as CadastroAguardandoEmail).email, 'mariana@email.com');
      await m.cliente.dispose();
    });

    test('guarda o celular nos metadados (sem CPF) e não chama updateUser',
        () async {
      final m = _montar((_) => _json(200, _usuario()));
      await m.servico.criarConta(_dados);

      expect(m.pedidos, hasLength(1));
      final p = m.pedidos.single;
      expect(p.method, 'POST');
      expect(p.url.path, '/auth/v1/signup');
      final corpo = jsonDecode(p.body) as Map<String, dynamic>;
      final data = corpo['data'] as Map<String, dynamic>;
      expect(data['celular'], '+5531987654417');
      expect(data.containsKey('cpf'), isFalse);
      expect(data.containsKey('nascimento'), isFalse);
      expect(data['nome'], 'Mariana Alves');
      expect(m.pedidos.where((r) => r.method == 'PUT'), isEmpty);
      // Sem sessão: conferência do CPF e vinculo cadastral; gravação autenticada espera o primeiro login.
      expect(
        m.apiPedidos.map((r) => r.url.path),
        ['/v1/cadastro/cpf', '/v1/cadastro/vincular'],
      );
      expect(jsonDecode(m.apiPedidos.first.body), {'cpf': '12345678909'});
      await m.cliente.dispose();
    });

    test('e-mail repetido (sem identidades) vira emailJaUsado', () async {
      final m = _montar((_) => _json(200, _usuario(identidades: const [])));
      await expectLater(m.servico.criarConta(_dados),
          throwsA(_erroAuth(TipoErroAuth.emailJaUsado)));
      await m.cliente.dispose();
    });
  });

  group('registrarCpf', () {
    test('grava na conta logada com o token da sessão', () async {
      final m = _montar((_) => _json(200, {
            'access_token': 'a.b.c',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'r',
            'user': _usuario(),
          }));
      await m.servico.entrarComEmail(email: 'mariana@email.com', senha: _senha);
      await m.servico.registrarCpf('123.456.789-09');

      final salvar = m.apiPedidos.single;
      expect(salvar.url.path, '/v1/me/dados-pessoais');
      expect(salvar.headers['Authorization'], 'Bearer a.b.c');
      expect(jsonDecode(salvar.body), {'cpf': '12345678909'});
      await m.cliente.dispose();
    });

    test('sem sessão devolve cpfNaoVerificado e não chama a API', () async {
      final m = _montar((_) => _json(200, _usuario()));
      await expectLater(
        m.servico.registrarCpf('123.456.789-09'),
        throwsA(_erroAuth(TipoErroAuth.cpfNaoVerificado)),
      );
      expect(m.apiPedidos, isEmpty);
      await m.cliente.dispose();
    });
  });

  group('traduz o código do erro', () {
    final casos = <String, TipoErroAuth>{
      'email_not_confirmed': TipoErroAuth.emailNaoConfirmado,
      'signup_disabled': TipoErroAuth.cadastroDesativado,
      'over_email_send_rate_limit': TipoErroAuth.limiteEmail,
      'validation_failed': TipoErroAuth.dadosInvalidos,
      'weak_password': TipoErroAuth.senhaFraca,
      'user_already_exists': TipoErroAuth.emailJaUsado,
      'invalid_credentials': TipoErroAuth.credenciaisInvalidas,
    };
    for (final e in casos.entries) {
      test('${e.key} no cadastro', () async {
        final m = _montar((_) => _erro(
              422,
              e.key,
              e.key == 'weak_password'
                  ? {
                      'weak_password': {
                        'reasons': ['length']
                      }
                    }
                  : null,
            ));
        await expectLater(
            m.servico.criarConta(_dados), throwsA(_erroAuth(e.value)));
        await m.cliente.dispose();
      });
    }

    test('email_not_confirmed no login', () async {
      final m = _montar((_) => _erro(400, 'email_not_confirmed'));
      await expectLater(
        m.servico.entrarComEmail(email: 'mariana@email.com', senha: _senha),
        throwsA(_erroAuth(TipoErroAuth.emailNaoConfirmado)),
      );
      await m.cliente.dispose();
    });

    test('senha errada continua credenciaisInvalidas', () async {
      final m = _montar((_) => _erro(400, 'invalid_credentials'));
      await expectLater(
        m.servico.entrarComEmail(email: 'mariana@email.com', senha: _outra),
        throwsA(_erroAuth(TipoErroAuth.credenciaisInvalidas)),
      );
      await m.cliente.dispose();
    });

    test('código desconhecido vira desconhecido', () {
      expect(
        ServicoAuthSupabase.traduzirErro(
                const sb.AuthApiException('x', code: 'coisa_nova'))
            .tipo,
        TipoErroAuth.desconhecido,
      );
    });
  });

  group('reenviarEmailConfirmacao', () {
    test('pede o reenvio do tipo signup com o link de retorno do app',
        () async {
      final m = _montar((_) => _json(200, {'message_id': 'x'}));
      await m.servico.reenviarEmailConfirmacao(' mariana@email.com ');
      final p = m.pedidos.single;
      expect(p.url.path, '/auth/v1/resend');
      final corpo = jsonDecode(p.body) as Map<String, dynamic>;
      expect(corpo['type'], 'signup');
      expect(corpo['email'], 'mariana@email.com');
      expect(p.url.queryParameters['redirect_to'], kUrlRetornoEmail);
      await m.cliente.dispose();
    });

    test('limite de e-mails vira limiteEmail', () async {
      final m = _montar((_) => _erro(429, 'over_email_send_rate_limit'));
      await expectLater(
        m.servico.reenviarEmailConfirmacao('mariana@email.com'),
        throwsA(_erroAuth(TipoErroAuth.limiteEmail)),
      );
      await m.cliente.dispose();
    });
  });

  group('recuperação de senha', () {
    http.Response sessao(http.Request _) => _json(200, {
          'access_token': 'a.b.c',
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'r',
          'user': _usuario(),
        });

    test('o e-mail de recuperação volta para o app (redirect_to)', () async {
      final m = _montar((_) => _json(200, <String, dynamic>{}));
      await m.servico.recuperarSenha(' mariana@email.com ');
      final p = m.pedidos.single;
      expect(p.url.path, '/auth/v1/recover');
      expect(p.url.queryParameters['redirect_to'], kUrlRetornoEmail);
      expect((jsonDecode(p.body) as Map<String, dynamic>)['email'], 'mariana@email.com');
      await m.cliente.dispose();
    });

    test('definirNovaSenha troca a senha da sessão do link', () async {
      final m = _montar((r) => r.url.path == '/auth/v1/user' ? _json(200, _usuario()) : sessao(r));
      await m.servico.entrarComEmail(email: 'mariana@email.com', senha: _senha);
      await m.servico.definirNovaSenha('NovaSenha123');
      final p = m.pedidos.lastWhere((r) => r.url.path == '/auth/v1/user');
      expect(p.method, 'PUT');
      expect((jsonDecode(p.body) as Map<String, dynamic>)['password'], 'NovaSenha123');
      await m.cliente.dispose();
    });

    test('senha fraca recusada pelo Supabase vira senhaFraca', () async {
      final m = _montar((r) => r.url.path == '/auth/v1/user' ? _erro(422, 'weak_password') : sessao(r));
      await m.servico.entrarComEmail(email: 'mariana@email.com', senha: _senha);
      await expectLater(
        m.servico.definirNovaSenha('123'),
        throwsA(_erroAuth(TipoErroAuth.senhaFraca)),
      );
      await m.cliente.dispose();
    });

    test('sem sessão (link vencido) a troca falha com erro tratado', () async {
      final m = _montar((_) => _json(200, <String, dynamic>{}));
      await expectLater(m.servico.definirNovaSenha('NovaSenha123'), throwsA(isA<ErroAuth>()));
      await m.cliente.dispose();
    });
  });
}
