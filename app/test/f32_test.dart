import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart' as cli;
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/modelos.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/telas/perfil_publico/avaliacoes_recebidas_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart';
import 'package:trato/tema/tema.dart';

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

class _ServicoAvaliacaoFake implements ServicoPerfilPublico, RespostaAvaliacao {
  String? resposta;
  String? ultimaIdRespondida;

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => [
        Avaliacao(
          id: 'av-1',
          cliente: 'Maria',
          servico: 'Eletricista',
          nota: 5.0,
          comentario: 'Excelente!',
          detalhes: 'Pontualidade 5',
          resposta: resposta,
        ),
      ];

  @override
  Future<PerfilPublico> carregarPerfil() async => throw UnimplementedError();

  @override
  Future<bool> temPerfilProfissional() async => true;

  @override
  Future<String?> responderAvaliacao(String avaliacaoId, String texto) async {
    ultimaIdRespondida = avaliacaoId;
    resposta = texto;
    return texto;
  }
}

void main() {
  group('F32', () {
    testWidgets('1. Cliente recusa orçamento com confirmação e chama POST /recusar',
        (tester) async {
      final chamadas = <String>[];
      final api = ClienteApi(
        urlBase: 'https://api.trato.teste',
        sessao: SessaoTrato()..entrar('tok'),
        cliente: MockClient((req) async {
          chamadas.add('${req.method} ${req.url.path}');
          return http.Response(
            jsonEncode({'orcamento_id': 'o1', 'pedido_id': 'p1', 'status': 'recusado'}),
            200,
          );
        }),
      );
      final repo = RepositorioOrcamentosApi(api);
      await repo.recusar('p1', 'o1');
      expect(chamadas, ['POST /v1/pedidos/p1/orcamentos/o1/recusar']);

      var recusou = false;
      final orcamento = Orcamento(
        id: 'o1',
        profissional: 'Carlos',
        iniciais: 'C',
        verificacao: 'Identidade verificada',
        nota: 4.9,
        notaResumo: '4,9',
        servicosResumo: '10 serviços',
        servicosConcluidos: 10,
        quando: 'Amanhã',
        inicio: DateTime(2026, 11, 22),
        garantia: '30 dias',
        observacao: '',
        totalCentavos: 15000,
        detalhe: const DetalheOrcamento(
          validoAte: '30/11',
          itens: [ItemOrcamento(descricao: 'Serviço', centavos: 15000)],
          notaMaterial: 'Não inclui materiais',
          agendaTitulo: 'Amanhã',
          agendaDetalhe: '09:00',
          garantiaTitulo: 'Garantia de 30 dias',
          garantiaDetalhe: 'Cobre mão de obra.',
          foraDoEscopo: 'Materiais',
          cancelamento: 'Grátis antes do início.',
        ),
      );
      await _abrir(
        tester,
        DetalheOrcamentoTela(
          orcamento: orcamento,
          aoRecusar: (_) => recusou = true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('botao-recusar-orcamento')));
      await tester.pumpAndSettle();
      expect(find.text('Recusar orçamento?'), findsOneWidget);
      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();
      expect(recusou, isTrue);
    });

    testWidgets('2. Profissional responde avaliação e cliente vê resposta no perfil público',
        (tester) async {
      final chamadas = <String>[];
      final api = ClienteApi(
        urlBase: 'https://api.trato.teste',
        sessao: SessaoTrato()..entrar('tok'),
        cliente: MockClient((req) async {
          chamadas.add('${req.method} ${req.url.path} ${req.body}');
          return http.Response(jsonEncode({'id': 'av-1', 'resposta': 'Obrigado!'}), 200);
        }),
      );
      final servicoApi = ServicoPerfilPublicoApi(api);
      final respApi = await servicoApi.responderAvaliacao('av-1', 'Obrigado!');
      expect(respApi, 'Obrigado!');
      expect(chamadas.single, contains('POST /v1/avaliacoes/av-1/responder'));

      final fake = _ServicoAvaliacaoFake();
      await _abrir(tester, AvaliacoesRecebidasTela(servico: fake));
      expect(find.text('Responder'), findsOneWidget);

      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('campo-resposta-avaliacao')),
        'Muito obrigado pela confiança!',
      );
      await tester.tap(find.byKey(const ValueKey('botao-enviar-resposta')));
      await tester.pumpAndSettle();

      expect(fake.ultimaIdRespondida, 'av-1');
      expect(find.text('Sua resposta: Muito obrigado pela confiança!'), findsOneWidget);
      expect(find.text('Responder'), findsNothing);

      // Visão cliente no perfil público
      await _abrir(
        tester,
        const Scaffold(
          body: cli.CartaoAvaliacao(
            avaliacao: Avaliacao(
              id: 'av-1',
              cliente: 'Maria',
              servico: 'Eletricista',
              nota: 5.0,
              comentario: 'Excelente!',
              detalhes: 'Pontualidade 5',
              resposta: 'Muito obrigado pela confiança!',
            ),
          ),
        ),
      );
      expect(find.text('Resposta do profissional: Muito obrigado pela confiança!'), findsOneWidget);
    });

    testWidgets('3. Cancelar exclusão LGPD chama DELETE /v1/me/exclusao e limpa banner',
        (tester) async {
      final chamadas = <String>[];
      final api = ClienteApi(
        urlBase: 'https://api.trato.teste',
        sessao: SessaoTrato()..entrar('tok'),
        cliente: MockClient((req) async {
          chamadas.add('${req.method} ${req.url.path}');
          return http.Response('', 204);
        }),
      );
      final servico = ServicoPrivacidadeApi(api);
      await servico.cancelarExclusao();
      expect(chamadas, ['DELETE /v1/me/exclusao']);

      var cancelou = false;
      await _abrir(
        tester,
        PerfilClienteTela(
          perfil: PerfilCliente(
            nome: 'João',
            iniciais: 'J',
            resumo: 'Nota 5,0',
            grupos: const [],
            exclusaoAgendadaEm: DateTime(2026, 11, 28),
          ),
          aoCancelarExclusao: () async {
            cancelou = true;
            return true;
          },
        ),
      );
      expect(find.byKey(const ValueKey('aviso-exclusao-agendada')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('botao-cancelar-exclusao')));
      await tester.pumpAndSettle();

      expect(cancelou, isTrue);
      expect(find.byKey(const ValueKey('aviso-exclusao-agendada')), findsNothing);
      expect(find.text('Exclusão cancelada. Sua conta continua ativa.'), findsOneWidget);
    });
  });
}
