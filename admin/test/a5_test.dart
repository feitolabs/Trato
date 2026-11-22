import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/componentes/lista.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

void main() {
  group('A5 · permissão moedas_configurar', () {
    test('só Financeiro e Administrador têm', () {
      for (final p in Papel.values) {
        final deve = p == Papel.financeiro || p == Papel.administrador;
        expect(p.pode(Permissao.moedasConfigurar), deve, reason: p.codigo);
      }
    });

    testWidgets('moderador vê a configuração, mas sem campo editável nem botão Salvar', (tester) async {
      await abrirPainel(tester, papel: 'moderador', secao: 'moedas');
      final campo = find.byKey(const ValueKey('moedas-campo-valor_moeda_centavos'));
      expect(campo, findsOneWidget);
      expect(tester.widget<TextField>(campo).enabled, isFalse);
      expect(find.text('Salvar configuração'), findsNothing);
    });

    testWidgets('financeiro edita e salva', (tester) async {
      await abrirPainel(tester, papel: 'financeiro', secao: 'moedas');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('moedas-campo-valor_moeda_centavos'))).enabled, isTrue);
      expect(find.text('Salvar configuração'), findsOneWidget);
    });
  });

  group('A5 · Tratinhos', () {
    testWidgets('validade vazia vai como null (nunca 0)', (tester) async {
      final api = ApiFake();
      await abrirPainel(tester, api: api, secao: 'moedas');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-validade_dias')), '');
      await tester.pump();
      final salvar = find.widgetWithText(FilledButton, 'Salvar configuração');
      await tester.ensureVisible(salvar);
      expect(tester.widget<FilledButton>(salvar).onPressed, isNotNull);
      await tester.tap(salvar);
      await tester.pumpAndSettle();
      await confirmarMotivo(tester, 'Salvar configuração');
      expect(api.moedasConfigAtual.validadeDias, isNull);
    });

    testWidgets('validade 0 e custo de exclusividade 0 mostram erro inline e bloqueiam salvar', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-validade_dias')), '0');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-exclusividade_custo_moedas')), '0');
      await tester.pump();
      expect(find.text('Informe um número a partir de 1'), findsNWidgets(2));
      final salvar = find.widgetWithText(FilledButton, 'Salvar configuração');
      await tester.ensureVisible(salvar);
      expect(tester.widget<FilledButton>(salvar).onPressed, isNull);
    });

    testWidgets('dias de bloqueio aceitam 0 e o máximo por profissional tem sufixo "por mês"', (tester) async {
      await abrirPainel(tester, secao: 'moedas');
      await tester.enterText(find.byKey(const ValueKey('moedas-campo-exclusividade_bloqueio_recusa_dias')), '0');
      await tester.pump();
      expect(find.text('Informe um número a partir de 0'), findsNothing);
      expect(find.text('por mês'), findsOneWidget);
    });
  });

  group('A5 · Pagamentos e Configurações', () {
    testWidgets('filtro "Falhou" mostra só o lançamento que falhou', (tester) async {
      await abrirPainel(tester, papel: 'financeiro', secao: 'pagamentos');
      expect(find.text('PED-10471'), findsOneWidget);
      expect(find.text('PED-10490'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Falhou').last);
      await tester.pumpAndSettle();
      expect(find.text('PED-10471'), findsOneWidget);
      expect(find.text('PED-10490'), findsNothing);
      // E "Em andamento" não traz mais o que falhou.
      await tester.tap(find.byKey(const ValueKey('status-falhou')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Em andamento').last);
      await tester.pumpAndSettle();
      expect(find.text('PED-10471'), findsNothing);
    });

    testWidgets('SeletorTrato desabilitado não deixa mudar o valor', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SeletorTrato<String>(
            rotulo: 'Valor proposto',
            habilitado: false,
            valor: '0',
            opcoes: const [('0', 'Desligada'), ('1', 'Ligada')],
            aoMudar: (_) {},
          ),
        ),
      ));
      expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).onChanged, isNull);
    });
  });

  group('A5 · trava de duplo clique', () {
    testWidgets('segundo toque em Exportar CSV enquanto o primeiro está em voo não gera 2 relatórios', (tester) async {
      final api = ApiFake();
      await abrirPainel(tester, papel: 'seguranca', api: api, secao: 'auditoria');
      await tester.tap(find.text('Exportar CSV'));
      await tester.pumpAndSettle();
      await confirmarMotivo(tester, 'Exportar CSV');
      expect(api.downloads.length, 1);
    });
  });

  group('A5 · download autenticado', () {
    ApiAdminHttp criar(MockClient cliente) => ApiAdminHttp(
          urlApi: 'https://api.teste',
          urlSupabase: 'https://sb.teste',
          chaveAnonSupabase: 'chave',
          cliente: cliente,
        );

    Future<ApiAdminHttp> logada(List<http.Request> chamadas, int statusDownload) async {
      final api = criar(MockClient((req) async {
        chamadas.add(req);
        if (req.url.path == '/auth/v1/token') {
          return http.Response(jsonEncode({'access_token': 'tok-teste'}), 200);
        }
        if (req.url.path == '/v1/admin/eu') {
          return http.Response(
            jsonEncode({'id': 'u', 'nome': 'M', 'email': 'm@t.l', 'papel': 'financeiro', 'alcada_centavos': 0}),
            200,
          );
        }
        if (statusDownload == 200) return http.Response('a;b', 200, headers: {'content-type': 'text/csv'});
        return http.Response.bytes(utf8.encode(jsonEncode({'detail': 'Este link já foi usado ou expirou.'})), statusDownload);
      }));
      await api.entrar('m@t.l', 'senha');
      return api;
    }

    test('manda o login no cabeçalho e não põe o token na URL', () async {
      final chamadas = <http.Request>[];
      final api = await logada(chamadas, 200);
      await api.baixarArquivo('https://api.teste/v1/admin/relatorios/baixar/abc', 'r.csv');
      final c = chamadas.last;
      expect(c.headers['Authorization'], 'Bearer tok-teste');
      expect(c.url.toString(), isNot(contains('tok-teste')));
    });

    test('link usado ou vencido (404) vira erro com a mensagem do servidor', () async {
      final api = await logada([], 404);
      await expectLater(
        api.baixarArquivo('https://api.teste/v1/admin/relatorios/baixar/abc', 'r.csv'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', contains('já foi usado'))),
      );
    });

    test('recusa baixar de outro endereço (o login não vaza)', () async {
      final chamadas = <http.Request>[];
      final api = await logada(chamadas, 200);
      final antes = chamadas.length;
      await expectLater(api.baixarArquivo('https://outro.site/x', 'r.csv'), throwsA(isA<ErroApi>()));
      expect(chamadas.length, antes);
    });
  });
}
