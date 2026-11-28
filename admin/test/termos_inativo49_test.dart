import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';
import 'package:trato_admin/telas/avisos_previos.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  group('Conta inativa (Termos 4.9) — tela Busca', () {
    testWidgets('filtra por status Inativo e exibe chip Inativo', (tester) async {
      final api = ApiFake();
      final usuarios = api.usuariosFake;
      api.definirStatusUsuarioFake(usuarios.first.id, 'inativo');

      await abrirPainel(tester, papel: 'administrador', api: api, secao: 'busca');

      await _clicar(tester, find.byKey(const ValueKey('status-null')));
      await tester.tap(find.text('Inativo').last);
      await tester.pumpAndSettle();

      expect(find.text(usuarios.first.nome), findsWidgets);
      expect(find.text('Inativo'), findsWidgets);
      expect(find.text('Reativar conta'), findsOneWidget);
      expect(find.text('Inativar conta'), findsNothing);
      expect(find.text('Alterar status'), findsNothing);
    });

    testWidgets('quem não tem usuariosStatus não vê Inativar conta nem Reativar conta', (tester) async {
      final api = ApiFake();
      await abrirPainel(tester, papel: 'atendente_n1', api: api, secao: 'busca');
      expect(find.text('Inativar conta'), findsNothing);
      expect(find.text('Reativar conta'), findsNothing);
    });

    testWidgets('inativar conta exige motivo >= 10 chars, mostra erro 409 e atualiza status quando aceito',
        (tester) async {
      final api = ApiFake()
        ..falhaInativarUsuario = const ErroApi(
          'É obrigatório enviar aviso prévio de inatividade com pelo menos 30 dias de antecedência antes de inativar a conta (Termos 4.9).',
          status: 409,
        );
      await abrirPainel(tester, papel: 'administrador', api: api, secao: 'busca');

      await _clicar(tester, find.text('Inativar conta'));
      await confirmarMotivo(tester, 'Inativar conta', motivo: 'Conta sem uso há mais de doze meses');
      expect(_contem('pelo menos 30 dias de antecedência'), findsWidgets);
      expect(api.acoesInatividadeUsuario, isEmpty);

      // Agora o aviso de 30 dias foi cumprido
      api.falhaInativarUsuario = null;
      await _clicar(tester, find.text('Inativar conta'));
      await confirmarMotivo(tester, 'Inativar conta', motivo: 'Aviso prévio de 30 dias cumprido sem resposta');

      expect(api.acoesInatividadeUsuario, hasLength(1));
      expect(api.acoesInatividadeUsuario.single.acao, 'inativar');
      expect(find.text('Reativar conta'), findsOneWidget);
      expect(find.text('Inativar conta'), findsNothing);
    });

    testWidgets('reativar conta inativa não abre modal de medida punitiva e volta para Ativo', (tester) async {
      final api = ApiFake();
      final usuarios = api.usuariosFake;
      api.definirStatusUsuarioFake(usuarios.first.id, 'inativo');

      await abrirPainel(tester, papel: 'administrador', api: api, secao: 'busca');
      await _clicar(tester, find.text('Reativar conta'));

      // Modal simples de motivo, sem campos de medida punitiva/cláusulas
      expect(_contem('Reativação gratuita de conta inativa (Termos 4.9), sem medida punitiva'), findsOneWidget);
      expect(find.text('Cláusulas'), findsNothing);

      await confirmarMotivo(tester, 'Reativar conta', motivo: 'Usuário solicitou retorno gratuito da conta');
      expect(api.acoesInatividadeUsuario, hasLength(1));
      expect(api.acoesInatividadeUsuario.single.acao, 'reativar');
      expect(find.text('Inativar conta'), findsOneWidget);
      expect(find.text('Reativar conta'), findsNothing);
    });
  });

  group('Texto de aviso prévio e auditoria (4.9)', () {
    test('kInatividadeSoAvisa esclarece que não é automática e aponta para a tela Busca após 30 dias', () {
      expect(kInatividadeSoAvisa, contains('não é inativada automaticamente'));
      expect(kInatividadeSoAvisa, contains('30 dias'));
    });

    test('auditoria descreve usuario.inativar e usuario.reativar', () {
      final inativar = EntradaAuditoria(
        id: 1,
        ocorridaEm: DateTime.utc(2026, 11, 27, 15, 0),
        ator: 'admin@trato.app',
        acao: 'usuario.inativar',
        entidade: 'usuarios',
        entidadeNome: 'Carla Mendes',
        motivo: 'Inatividade 4.9',
      );
      expect(descreverAcao(inativar), 'inativou a conta de Carla Mendes');

      final reativar = EntradaAuditoria(
        id: 2,
        ocorridaEm: DateTime.utc(2026, 11, 27, 15, 5),
        ator: 'admin@trato.app',
        acao: 'usuario.reativar',
        entidade: 'usuarios',
        entidadeNome: 'Carla Mendes',
        motivo: 'Retorno gratuito 4.9',
      );
      expect(descreverAcao(reativar), 'reativou a conta de Carla Mendes');
    });
  });

  group('Contrato HTTP inativar/reativar', () {
    test('chama POST /inativar e POST /reativar e desserializa UsuarioOut', () async {
      final chamadas = <http.Request>[];
      final cliente = MockClient((req) async {
        chamadas.add(req);
        if (req.method == 'POST' && req.url.path == '/auth/v1/token') {
          return http.Response(jsonEncode({'access_token': 'tok'}), 200, headers: {'content-type': 'application/json'});
        }
        if (req.method == 'GET' && req.url.path == '/v1/admin/eu') {
          return http.Response(
            jsonEncode({'id': 'op-1', 'nome': 'Adm', 'email': 'a@t.local', 'papel': 'administrador', 'alcada_centavos': 0}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && req.url.path == '/v1/admin/usuarios/u-9/inativar') {
          return http.Response(
            jsonEncode({'id': 'u-9', 'nome': 'Carla', 'tipo': 'cliente', 'status': 'inativo'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && req.url.path == '/v1/admin/usuarios/u-9/reativar') {
          return http.Response(
            jsonEncode({'id': 'u-9', 'nome': 'Carla', 'tipo': 'cliente', 'status': 'ativo'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'detail': '404'}), 404);
      });

      final api = ApiAdminHttp(
        urlApi: 'https://api.teste/',
        urlSupabase: 'https://sb.teste',
        chaveAnonSupabase: 'anon',
        cliente: cliente,
      );
      await api.entrar('a@t.local', 'senha');

      final uInat = await api.inativarUsuario('u-9', motivo: 'Sem uso após aviso de 30 dias');
      expect(uInat.status, 'inativo');
      expect(jsonDecode(chamadas.last.body), {'motivo': 'Sem uso após aviso de 30 dias'});

      final uReat = await api.reativarUsuario('u-9', motivo: 'Solicitação gratuita de reativação');
      expect(uReat.status, 'ativo');
      expect(jsonDecode(chamadas.last.body), {'motivo': 'Solicitação gratuita de reativação'});
    });
  });
}
