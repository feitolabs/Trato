import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:trato/auth/config_auth.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/auth/servico_auth_supabase.dart';

const _senha = 'segredo123';
const _outra = 'errada123';

const _dados = DadosCadastro(
  nome: 'Mariana Alves',
  email: 'mariana@email.com',
  senha: _senha,
  celular: '(31) 98765-4417',
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

/// Cliente do Supabase com a rede trocada por [resposta]; guarda os pedidos feitos.
({
  ServicoAuthSupabase servico,
  List<http.Request> pedidos,
  sb.SupabaseClient cliente
}) _montar(
  http.Response Function(http.Request) resposta,
) {
  final pedidos = <http.Request>[];
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
  return (
    servico: ServicoAuthSupabase(const ConfigAuth(), cliente: cliente),
    pedidos: pedidos,
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
      await m.cliente.dispose();
    });

    test('e-mail repetido (sem identidades) vira emailJaUsado', () async {
      final m = _montar((_) => _json(200, _usuario(identidades: const [])));
      await expectLater(m.servico.criarConta(_dados),
          throwsA(_erroAuth(TipoErroAuth.emailJaUsado)));
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
}
