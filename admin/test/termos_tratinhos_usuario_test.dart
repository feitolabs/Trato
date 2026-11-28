import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder _noDialogo(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);
Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _escrever(WidgetTester tester, Finder campo, String texto) async {
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

void main() {
  group('Tratinhos por usuário — tela e modais', () {
    testWidgets('só aparece para quem tem moedasConfigurar (moderador não vê)', (tester) async {
      await abrirPainel(tester, papel: 'moderador', secao: 'moedas');
      expect(find.text('Tratinhos por usuário'), findsNothing);
      expect(find.byKey(const ValueKey('moedas-usuario-id')), findsNothing);
    });

    testWidgets('consulta usuário e mostra saldos, pendentes e extrato de ambas as carteiras', (tester) async {
      final api = ApiFake()
        ..moedasPorUsuario['usr-42'] = MoedasUsuario(
          usuarioId: 'usr-42',
          saldoCliente: 120,
          saldoProfissional: 45,
          pendentesCliente: [
            PendenteMoedaUsuario(
              chaveIdempotencia: 'pend-1',
              pedidoId: 'ped-1',
              quantidade: 15,
              liberarEm: DateTime.utc(2026, 12, 1, 15, 0),
              criadaEm: DateTime.utc(2026, 11, 24, 15, 0),
              tipoLancamento: 'bonus_avaliacao',
              status: 'pendente',
            ),
          ],
          pendentesProfissional: const [],
          extratoCliente: [
            LancamentoMoedaUsuario(
              tipo: 'bonus_avaliacao',
              quantidade: 120,
              carteira: 'cliente',
              chaveIdempotencia: 'l-1',
              criadaEm: DateTime.utc(2026, 11, 20, 15, 0),
            ),
          ],
        );

      await abrirPainel(tester, papel: 'financeiro', api: api, secao: 'moedas');
      expect(find.text('Tratinhos por usuário'), findsOneWidget);
      await _escrever(tester, find.byKey(const ValueKey('moedas-usuario-id')), 'usr-42');
      await _clicar(tester, find.text('Consultar'));

      expect(find.text('Usuário: usr-42'), findsOneWidget);
      expect(find.text('Saldo disponível: 120 Tratinhos'), findsOneWidget);
      expect(find.text('Saldo disponível: 45 Tratinhos'), findsOneWidget);
      expect(find.text('Pendentes: 1 (15 Tratinhos)'), findsOneWidget);
      expect(find.text('Pendentes: nenhum'), findsOneWidget);
      expect(find.text('Conceder Tratinhos (compensação)'), findsOneWidget);
      expect(find.text('Cancelar por fraude'), findsOneWidget);
      expect(find.textContaining('moeda'), findsNothing);
    });

    testWidgets('conceder compensação exige motivo >= 10 chars e confirmação, e atualiza saldo', (tester) async {
      final api = ApiFake()
        ..moedasPorUsuario['usr-10'] = const MoedasUsuario(
          usuarioId: 'usr-10',
          saldoCliente: 10,
          saldoProfissional: 20,
        );

      await abrirPainel(tester, papel: 'financeiro', api: api, secao: 'moedas');
      await _escrever(tester, find.byKey(const ValueKey('moedas-usuario-id')), 'usr-10');
      await _clicar(tester, find.text('Consultar'));
      await _clicar(tester, find.text('Conceder Tratinhos (compensação)'));

      // Muda carteira para profissional
      await _clicar(tester, find.byKey(const ValueKey('conceder-carteira')));
      await tester.tap(find.text('Profissional').last);
      await tester.pumpAndSettle();

      await _escrever(tester, find.byKey(const ValueKey('conceder-quantidade')), '50');
      await _escrever(tester, find.byKey(const ValueKey('conceder-validade')), '60');
      await _escrever(tester, find.byKey(const ValueKey('conceder-referencia')), 'PED-99');
      await _escrever(tester, find.byKey(const ValueKey('conceder-motivo')), 'curto');

      // Motivo curto não abre confirmação
      await _clicar(tester, _noDialogo(find.text('Revisar concessão')));
      expect(_noDialogo(find.text('Confirmar concessão')), findsNothing);

      await _escrever(
        tester,
        find.byKey(const ValueKey('conceder-motivo')),
        'Compensação por falha operacional no pedido PED-99',
      );
      await _clicar(tester, _noDialogo(find.text('Revisar concessão')));
      expect(_contem('Confirmar concessão?'), findsOneWidget);
      expect(api.concessoesMoedas, isEmpty);

      await _clicar(tester, _noDialogo(find.text('Confirmar concessão')));

      expect(api.concessoesMoedas, hasLength(1));
      expect(api.concessoesMoedas.single['usuario_id'], 'usr-10');
      expect(api.concessoesMoedas.single['carteira'], 'profissional');
      expect(api.concessoesMoedas.single['quantidade'], 50);
      expect(api.concessoesMoedas.single['validade_dias'], 60);
      expect(api.concessoesMoedas.single['referencia_id'], 'PED-99');
      expect(find.text('Saldo disponível: 70 Tratinhos'), findsOneWidget);
    });

    testWidgets('cancelar por fraude debita saldo e cancela pendentes, e mostra erro 409 do servidor', (tester) async {
      final api = ApiFake()
        ..moedasPorUsuario['usr-fraude'] = MoedasUsuario(
          usuarioId: 'usr-fraude',
          saldoCliente: 80,
          saldoProfissional: 0,
          pendentesCliente: [
            PendenteMoedaUsuario(
              chaveIdempotencia: 'p-1',
              pedidoId: 'ped-f',
              quantidade: 25,
              liberarEm: DateTime.utc(2026, 12, 5, 15, 0),
              criadaEm: DateTime.utc(2026, 11, 25, 15, 0),
              tipoLancamento: 'bonus_avaliacao',
              status: 'pendente',
            ),
          ],
        );

      await abrirPainel(tester, papel: 'administrador', api: api, secao: 'moedas');
      await _escrever(tester, find.byKey(const ValueKey('moedas-usuario-id')), 'usr-fraude');
      await _clicar(tester, find.text('Consultar'));
      await _clicar(tester, find.text('Cancelar por fraude'));

      // Quantidade 0 sem marcar pendentes não libera revisão
      await _escrever(tester, find.byKey(const ValueKey('fraude-motivo')), 'Autoavaliação combinada confirmada');
      await _clicar(tester, _noDialogo(find.text('Revisar cancelamento')));
      expect(_noDialogo(find.text('Confirmar cancelamento')), findsNothing);

      // Tenta debitar mais do que o saldo -> servidor devolve 409 e erro aparece no modal
      await _escrever(tester, find.byKey(const ValueKey('fraude-quantidade')), '200');
      await _clicar(tester, _noDialogo(find.text('Revisar cancelamento')));
      await _clicar(tester, _noDialogo(find.text('Confirmar cancelamento')));
      expect(_contem('Saldo insuficiente na carteira cliente'), findsOneWidget);
      expect(api.cancelamentosFraudeMoedas, isEmpty);

      // Agora debita 30 e cancela pendentes
      await _escrever(tester, find.byKey(const ValueKey('fraude-quantidade')), '30');
      await _clicar(tester, find.byKey(const ValueKey('fraude-cancelar-pendentes')));
      await _clicar(tester, _noDialogo(find.text('Revisar cancelamento')));
      expect(_contem('Confirmar cancelamento por fraude?'), findsOneWidget);
      await _clicar(tester, _noDialogo(find.text('Confirmar cancelamento')));

      expect(api.cancelamentosFraudeMoedas, hasLength(1));
      expect(api.cancelamentosFraudeMoedas.single['quantidade'], 30);
      expect(api.cancelamentosFraudeMoedas.single['cancelar_pendentes'], isTrue);
      expect(find.text('Saldo disponível: 50 Tratinhos'), findsOneWidget);
      expect(find.text('Pendentes: nenhum'), findsNWidgets(2));
    });
  });

  group('Auditoria de Tratinhos', () {
    test('descreve moedas.conceder_compensacao e moedas.cancelar_fraude em português', () {
      final conceder = EntradaAuditoria(
        id: 1,
        ocorridaEm: DateTime.utc(2026, 11, 27, 15, 0),
        ator: 'fin@trato.app',
        acao: 'moedas.conceder_compensacao',
        entidade: 'moedas_lancamentos',
        entidadeNome: 'usr-10',
        motivo: 'Compensação por atraso',
        detalhes: const {'carteira': 'profissional', 'quantidade': 50},
      );
      expect(
        descreverAcao(conceder),
        'concedeu Tratinhos como compensação para usr-10 (50 na carteira profissional)',
      );

      final cancelar = EntradaAuditoria(
        id: 2,
        ocorridaEm: DateTime.utc(2026, 11, 27, 15, 5),
        ator: 'admin@trato.app',
        acao: 'moedas.cancelar_fraude',
        entidade: 'moedas_lancamentos',
        entidadeNome: 'usr-fraude',
        motivo: 'Fraude comprovada',
        detalhes: const {'carteira': 'cliente', 'quantidade_debitada': 30, 'pendentes_cancelados': 1},
      );
      expect(
        descreverAcao(cancelar),
        'cancelou Tratinhos por fraude de usr-fraude (30 debitado(s), 1 pendente(s) cancelado(s) na carteira cliente)',
      );
    });
  });

  group('Contrato HTTP de Tratinhos por usuário', () {
    test('chama GET /usuarios/{id}, POST /conceder e POST /cancelar-fraude com corpo e retorno exatos', () async {
      final chamadas = <http.Request>[];
      final cliente = MockClient((req) async {
        chamadas.add(req);
        if (req.method == 'POST' && req.url.path == '/auth/v1/token') {
          return http.Response(jsonEncode({'access_token': 'tok'}), 200, headers: {'content-type': 'application/json'});
        }
        if (req.method == 'GET' && req.url.path == '/v1/admin/eu') {
          return http.Response(
            jsonEncode({'id': 'op-1', 'nome': 'Fin', 'email': 'f@t.local', 'papel': 'financeiro', 'alcada_centavos': 0}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'GET' && req.url.path == '/v1/admin/moedas/usuarios/u-1') {
          return http.Response(
            jsonEncode({
              'usuario_id': 'u-1',
              'saldo_cliente': 100,
              'saldo_profissional': 25,
              'pendentes_cliente': [
                {
                  'chave_idempotencia': 'pk-1',
                  'pedido_id': 'ped-1',
                  'quantidade': 10,
                  'liberar_em': '2026-12-01T12:00:00Z',
                  'criada_em': '2026-11-24T12:00:00Z',
                  'tipo_lancamento': 'bonus_avaliacao',
                  'status': 'pendente',
                }
              ],
              'pendentes_profissional': [],
              'extrato_cliente': [
                {
                  'tipo': 'ajuste',
                  'quantidade': 100,
                  'carteira': 'cliente',
                  'chave_idempotencia': 'ck-1',
                  'criada_em': '2026-11-20T12:00:00Z',
                  'expira_em': '2027-02-20T12:00:00Z',
                  'referencia_id': 'ref-1',
                }
              ],
              'extrato_profissional': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && req.url.path == '/v1/admin/moedas/usuarios/u-1/conceder') {
          return http.Response(
            jsonEncode({
              'usuario_id': 'u-1',
              'carteira': 'cliente',
              'quantidade': 40,
              'expira_em': '2027-01-26T12:00:00Z',
              'chave_idempotencia': 'admin-conceder:u-1:cliente:k1',
              'idempotente': false,
              'saldo_atual': 140,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && req.url.path == '/v1/admin/moedas/usuarios/u-1/cancelar-fraude') {
          return http.Response(
            jsonEncode({
              'usuario_id': 'u-1',
              'carteira': 'cliente',
              'quantidade_debitada': 30,
              'pendentes_cancelados': 1,
              'chave_idempotencia': 'admin-fraude:u-1:cliente:k2',
              'idempotente': false,
              'saldo_atual': 110,
            }),
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
      await api.entrar('f@t.local', 'senha');

      final consulta = await api.consultarMoedasUsuario('u-1', limite: 20);
      expect(consulta.saldoCliente, 100);
      expect(consulta.saldoProfissional, 25);
      expect(consulta.pendentesCliente.single.quantidade, 10);
      expect(consulta.extratoCliente.single.referenciaId, 'ref-1');
      final reqGet = chamadas.last;
      expect(reqGet.url.queryParameters['limite'], '20');

      final resConc = await api.concederMoedasUsuario(
        'u-1',
        carteira: 'cliente',
        quantidade: 40,
        validadeDias: 60,
        motivo: 'Compensação combinada com suporte',
        chaveIdempotencia: 'k1',
        referenciaId: 'ch-1',
      );
      expect(resConc.saldoAtual, 140);
      expect(resConc.idempotente, isFalse);
      final corpoConc = jsonDecode(chamadas.last.body) as Map<String, dynamic>;
      expect(corpoConc, {
        'carteira': 'cliente',
        'quantidade': 40,
        'validade_dias': 60,
        'motivo': 'Compensação combinada com suporte',
        'chave_idempotencia': 'k1',
        'referencia_id': 'ch-1',
      });

      final resCanc = await api.cancelarFraudeMoedasUsuario(
        'u-1',
        carteira: 'cliente',
        quantidade: 30,
        cancelarPendentes: true,
        motivo: 'Fraude detectada em bônus de avaliação',
        chaveIdempotencia: 'k2',
      );
      expect(resCanc.quantidadeDebitada, 30);
      expect(resCanc.pendentesCancelados, 1);
      expect(resCanc.saldoAtual, 110);
      final corpoCanc = jsonDecode(chamadas.last.body) as Map<String, dynamic>;
      expect(corpoCanc, {
        'carteira': 'cliente',
        'quantidade': 30,
        'cancelar_pendentes': true,
        'motivo': 'Fraude detectada em bônus de avaliação',
        'chave_idempotencia': 'k2',
      });
    });
  });
}
