// FL-VALIDADE-13.3: validade dos Tratinhos na carteira do profissional, avaliação e indicações.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/carteira/avaliar_cliente_tela.dart';
import 'package:trato/telas/comuns/moedas_ganhas_tela.dart';
import 'package:trato/telas/comuns/prazo_avaliacao.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/indicacoes/indique_e_ganhe_tela.dart';
import 'package:trato/telas/indicacoes/modelos.dart';
import 'package:trato/telas/indicacoes/servico_fake.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/profissional_inicio/tratinhos_profissional_tela.dart';

import 'apoio/fontes.dart';

ClienteApi _apiSimulado(Future<http.Response> Function(http.Request) responder) => ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('valor-de-teste'),
      cliente: MockClient(responder),
    );

http.Response _json(Object corpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(carregarFontesTrato);

  group('1. Carteira do profissional — creditos_profissional (13.3)', () {
    test('RepositorioProfissionalApi.exclusividades mapeia creditos_profissional com fallback',
        () async {
      final api = _apiSimulado((req) async {
        if (req.url.path == '/v1/profissional/exclusividades') {
          return _json({
            'itens': [],
            'ativas_ou_pendentes': 0,
            'limite_maximo': 3,
            'saldo_profissional': 70,
          });
        }
        return _json({
          'saldo': 0,
          'saldo_profissional': 70,
          'moedas_pendentes_profissional': 0,
          'creditos_profissional': [
            {'moedas': 50, 'expira_em': '2026-12-20T12:00:00Z'},
            {'moedas': 20, 'expira_em': null},
          ],
        });
      });

      final resumo = await RepositorioProfissionalApi(api).minhasExclusividades();
      expect(resumo.creditosProfissional, hasLength(2));
      expect(resumo.creditosProfissional[0].moedas, 50);
      expect(resumo.creditosProfissional[0].expiraEm, isNotNull);
      expect(resumo.creditosProfissional[1].moedas, 20);
      expect(resumo.creditosProfissional[1].expiraEm, isNull);

      // Fallback quando backend antigo omite creditos_profissional.
      final apiAntigo = _apiSimulado((req) async {
        if (req.url.path == '/v1/profissional/exclusividades') {
          return _json({
            'itens': [],
            'ativas_ou_pendentes': 0,
            'limite_maximo': 3,
            'saldo_profissional': 10,
          });
        }
        return _json({'saldo': 0, 'saldo_profissional': 10});
      });
      final resumoAntigo = await RepositorioProfissionalApi(apiAntigo).minhasExclusividades();
      expect(resumoAntigo.creditosProfissional, isEmpty);
    });

    testWidgets('TratinhosProfissionalTela exibe validade dos créditos e mantém fallback',
        (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: TratinhosProfissionalTela(
            resumo: ResumoExclusividades(
              saldoProfissional: 70,
              creditosProfissional: [
                CreditoPorValidade(moedas: 50, expiraEm: DateTime(2026, 12, 20)),
                const CreditoPorValidade(moedas: 20),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Validade do seu saldo'), findsOneWidget);
      expect(find.text('50 Tratinhos: vence em 20/12/2026'), findsOneWidget);
      expect(find.text('20 Tratinhos: vencimento não informado'), findsOneWidget);
      expect(find.textContaining('R\$'), findsNothing);

      // Sem créditos detalhados (API antiga): mantém fallback.
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: const TratinhosProfissionalTela(
            resumo: ResumoExclusividades(saldoProfissional: 10),
          ),
        ),
      );
      expect(
        find.text('A data de vencimento está no texto do aviso que você recebeu.'),
        findsOneWidget,
      );
    });
  });

  group('2. Avaliação — bonus_validade_dias (13.3)', () {
    test('PrazoAvaliacao.deJson lê bonus_validade_dias e faz fallback quando ausente', () {
      final comValidade = PrazoAvaliacao.deJson({
        'bonus_moedas': 50,
        'bonus_validade_dias': 180,
      });
      expect(comValidade.bonusMoedas, 50);
      expect(comValidade.bonusValidadeDias, 180);

      final semValidade = PrazoAvaliacao.deJson({'bonus_moedas': 50});
      expect(semValidade.bonusValidadeDias, isNull);
    });

    testWidgets('AvaliacaoTela mostra validade do bônus quando presente e omite quando nulo',
        (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: const AvaliacaoTela(
            dados: DadosAvaliacao(
              nomeProfissional: 'Carlos',
              valorLiberadoCentavos: 10000,
              criterios: ['Pontualidade'],
              gorjetasCentavos: [],
              gorjetaDisponivel: false,
              bonusDisponivel: true,
              bonusMoedas: 50,
              bonusValidadeDias: 90,
            ),
          ),
        ),
      );
      expect(find.textContaining('Validade de 90 dias após o crédito.'), findsOneWidget);

      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: const AvaliacaoTela(
            dados: DadosAvaliacao(
              nomeProfissional: 'Carlos',
              valorLiberadoCentavos: 10000,
              criterios: ['Pontualidade'],
              gorjetasCentavos: [],
              gorjetaDisponivel: false,
              bonusDisponivel: true,
              bonusMoedas: 50,
            ),
          ),
        ),
      );
      expect(find.textContaining('Validade de'), findsNothing);
    });

    testWidgets('AvaliarClienteTela e MoedasGanhasTela exibem bonus_validade_dias', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: AvaliarClienteTela(
            pedidoNumero: '#1234',
            prazo: const PrazoAvaliacao(bonusMoedas: 30, bonusValidadeDias: 120),
            aoEnviar: (_, __) async => 30,
          ),
        ),
      );
      expect(find.textContaining('Validade de 120 dias após o crédito.'), findsOneWidget);

      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: TemaTrato.claro,
            home: MoedasGanhasTela(
              moedas: 50,
              validadeDias: 90,
              aoContinuar: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tratinhos-validade')), findsOneWidget);
      expect(find.text('Validade de 90 dias após o crédito.'), findsOneWidget);
    });
  });

  group('3. Indicações — validade_dias (13.3)', () {
    test('ResumoIndicacoes.deJson mapeia validade_dias com fallback seguro', () {
      final novo = ResumoIndicacoes.deJson({
        'cadastradas': 2,
        'aguardando_liberacao': 1,
        'liberadas': 1,
        'limite_mensal': 5,
        'limite_mensal_restante': 4,
        'validade_dias': 180,
      });
      expect(novo.validadeDias, 180);

      final antigo = ResumoIndicacoes.deJson({
        'cadastradas': 1,
        'aguardando_liberacao': 0,
        'liberadas': 0,
        'limite_mensal': 5,
        'limite_mensal_restante': 5,
      });
      expect(antigo.validadeDias, isNull);
    });

    testWidgets('IndiqueEGanheTela exibe validade dos Tratinhos de indicação quando presente',
        (t) async {
      final servicoComValidade = ServicoIndicacoesFake(
        meu: const MeuCodigoIndicacao(
          codigo: 'TRATO-ABC',
          resumo: ResumoIndicacoes(
            cadastradas: 1,
            aguardandoLiberacao: 0,
            liberadas: 1,
            limiteMensal: 5,
            limiteMensalRestante: 4,
            validadeDias: 180,
          ),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: IndiqueEGanheTela(servico: servicoComValidade),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('resumo-validade')), findsOneWidget);
      expect(
        find.text('Os Tratinhos de indicação valem por 180 dias após o crédito.'),
        findsOneWidget,
      );

      final servicoSemValidade = ServicoIndicacoesFake(
        meu: const MeuCodigoIndicacao(
          codigo: 'TRATO-ABC',
          resumo: ResumoIndicacoes(
            cadastradas: 0,
            limiteMensal: 5,
            limiteMensalRestante: 5,
          ),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          home: IndiqueEGanheTela(key: const ValueKey('sem-validade'), servico: servicoSemValidade),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('resumo-validade')), findsNothing);
    });
  });
}
