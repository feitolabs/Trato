import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/cliente/cartao_avaliacao.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/modelos.dart';
import 'package:trato/telas/nota_material/enviar_nota_tela.dart';
import 'package:trato/telas/nota_material/nota_material.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/perfil_cliente/extrato_tratinhos_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/perfil_cliente/perfil_cliente_tela.dart';
import 'package:trato/tema/tema.dart';

Widget _envolver(Widget child) => MaterialApp(theme: TemaTrato.claro, home: child);

Profissional _profissionalComAvaliacoes(List<Avaliacao> lista, {int? total}) => Profissional(
      id: 'pro1',
      nome: 'Carlos Silva',
      iniciais: 'CS',
      verificacao: 'Identidade conferida',
      especialidade: 'Eletricista',
      servicosConcluidos: 12,
      nota: 4.9,
      distanciaKm: 2.3,
      detalhe: DetalhePerfil(
        noTratoDesde: 2025,
        totalAvaliacoes: total ?? lista.length,
        taxaConclusao: 100,
        verificacoes: const ['CPF conferido'],
        avaliacoes: lista,
      ),
    );

void main() {
  group('F55 — Avaliações (5 critérios, card novo e prévia de 3)', () {
    test('avaliar envia criterios mapeados para as 5 chaves exatas do backend', () async {
      Map<String, dynamic>? corpoEnviado;
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('jwt'),
        cliente: MockClient((req) async {
          if (req.method == 'POST' && req.url.path == '/v1/contratos/p1/avaliacao') {
            corpoEnviado = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'id': 'a1', 'moedas_ganhas': 50}), 201);
          }
          return http.Response('{}', 200);
        }),
      );
      final repo = RepositorioPedidosApi(api);
      await repo.avaliar(
        'p1',
        const EnvioAvaliacao(
          notas: [5, 5, 4, 5, 4],
          comentario: 'Excelente',
          gorjetaCentavos: 0,
        ),
      );
      expect(corpoEnviado?['criterios'], {
        'pontualidade': 5,
        'qualidade': 5,
        'limpeza': 4,
        'comunicacao': 5,
        'preco_justo': 4,
      });
    });

    test('perfil do catálogo lê criterios com fallback seguro', () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('jwt'),
        cliente: MockClient((req) async {
          if (req.url.path == '/v1/profissionais/pro1') {
            return http.Response(
              jsonEncode({
                'id': 'pro1',
                'nome': 'Carlos Silva',
                'nota_media': 4.8,
                'avaliacoes': [
                  {
                    'id': 'av1',
                    'cliente_nome': 'Tester C.',
                    'servico': 'Troca de tomada',
                    'nota_geral': 5,
                    'nota_decimal': 4.8,
                    'comentario': '',
                    'criterios': {
                      'pontualidade': 5,
                      'qualidade': 5,
                      'limpeza': 5,
                      'comunicacao': 5,
                      'preco_justo': 4,
                    },
                  },
                  {
                    'id': 'av2',
                    'cliente_nome': 'Ana M.',
                    'nota_geral': 5,
                    'comentario': 'Ótimo!',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('[]', 200);
        }),
      );
      final repo = RepositorioCatalogoApi(api);
      final pro = await repo.perfil('pro1');
      final av1 = pro.detalhe!.avaliacoes[0];
      final av2 = pro.detalhe!.avaliacoes[1];
      expect(av1.criterios['preco_justo'], 4);
      expect(
        av1.detalhes,
        'Pontualidade 5 · Qualidade 5 · Limpeza 5 · Comunicação 5 · Preço justo 4',
      );
      expect(av2.criterios, isEmpty);
      expect(av2.detalhes, isEmpty);
    });

    testWidgets('CartaoAvaliacaoVisual mostra iniciais, 5 critérios e esconde comentário vazio',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          const Scaffold(
            body: CartaoAvaliacaoVisual(
              avaliacao: Avaliacao(
                cliente: 'Tester C.',
                servico: 'Troca de tomada · 22/11',
                nota: 4.8,
                comentario: '   ',
                detalhes: '',
                criterios: {
                  'pontualidade': 5,
                  'qualidade': 5,
                  'limpeza': 5,
                  'comunicacao': 5,
                  'preco_justo': 4,
                },
                etiquetas: ['Pontual'],
              ),
            ),
          ),
        ),
      );
      expect(find.text('TC'), findsOneWidget);
      expect(find.text('Tester C.'), findsOneWidget);
      expect(find.text('4,8'), findsOneWidget);
      expect(find.text('Pontualidade 5'), findsOneWidget);
      expect(find.text('Preço justo 4'), findsOneWidget);
      expect(find.text('   '), findsNothing);
      expect(find.text(''), findsNothing);
    });

    testWidgets('PerfilProfissionalTela mostra prévia de 3 e só exibe "Ver todas" quando total > 3',
        (tester) async {
      final tres = [
        for (var i = 1; i <= 3; i++)
          Avaliacao(
            cliente: 'Cliente $i',
            servico: 'Serviço $i',
            nota: 5,
            comentario: 'Muito bom $i',
            detalhes: '',
          ),
      ];
      await tester.pumpWidget(
        _envolver(
          PerfilProfissionalTela(
            profissional: _profissionalComAvaliacoes(tres, total: 3),
            aoVerAvaliacoes: (_) {},
          ),
        ),
      );
      expect(find.text('Cliente 1'), findsOneWidget);
      expect(find.text('Cliente 3'), findsOneWidget);
      expect(find.textContaining('Ver todas'), findsNothing);

      final cinco = [
        ...tres,
        const Avaliacao(
          cliente: 'Cliente 4',
          servico: 'Serviço 4',
          nota: 4.5,
          comentario: 'Bom 4',
          detalhes: '',
        ),
        const Avaliacao(
          cliente: 'Cliente 5',
          servico: 'Serviço 5',
          nota: 4.0,
          comentario: 'Bom 5',
          detalhes: '',
        ),
      ];
      await tester.pumpWidget(
        _envolver(
          PerfilProfissionalTela(
            profissional: _profissionalComAvaliacoes(cinco, total: 5),
            aoVerAvaliacoes: (_) {},
          ),
        ),
      );
      expect(find.text('Cliente 1'), findsOneWidget);
      expect(find.text('Cliente 3'), findsOneWidget);
      expect(find.text('Cliente 4'), findsNothing);
      expect(find.text('Ver todas (5)'), findsOneWidget);
    });
  });

  group('F55 — Tratinhos (bônus condicional e extrato do cliente)', () {
    testWidgets('AvaliacaoTela só mostra legenda de bônus quando bonusDisponivel == true',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          const AvaliacaoTela(
            dados: DadosAvaliacao(
              nomeProfissional: 'Carlos',
              valorLiberadoCentavos: 15000,
              criterios: ['Pontualidade'],
              gorjetasCentavos: [],
              gorjetaDisponivel: false,
              bonusDisponivel: false,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('legenda-bonus-tratinhos')), findsNothing);

      await tester.pumpWidget(
        _envolver(
          const AvaliacaoTela(
            dados: DadosAvaliacao(
              nomeProfissional: 'Carlos',
              valorLiberadoCentavos: 15000,
              criterios: ['Pontualidade'],
              gorjetasCentavos: [],
              gorjetaDisponivel: false,
              bonusDisponivel: true,
              bonusMoedas: 50,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('legenda-bonus-tratinhos')), findsOneWidget);
      expect(find.textContaining('+50 Tratinhos'), findsOneWidget);
    });

    testWidgets('Tocar em "Seus Tratinhos" abre ExtratoTratinhosTela com saldo e lançamentos',
        (tester) async {
      final perfil = PerfilCliente(
        nome: 'Tester Cliente',
        iniciais: 'TC',
        resumo: 'Nota 5,0',
        grupos: const [],
        moedas: 50,
        moedasPendentes: 25,
        moedasValorCentavos: 1,
        moedasExtrato: [
          LancamentoTratinho(
            tipo: 'bonus_avaliacao',
            quantidade: 50,
            criadaEm: DateTime(2026, 11, 22),
          ),
        ],
      );
      await tester.pumpWidget(_envolver(PerfilClienteTela(perfil: perfil)));
      await tester.tap(find.byKey(const ValueKey('cartao-seus-tratinhos')));
      await tester.pumpAndSettle();

      expect(find.byType(ExtratoTratinhosTela), findsOneWidget);
      expect(find.text('50 Tratinhos'), findsOneWidget);
      expect(find.text('Bônus por avaliação'), findsOneWidget);
      expect(find.text('+50 Tratinhos'), findsOneWidget);
    });
  });

  group('F55 — Polimentos (pedido finalizado e nota de materiais)', () {
    testWidgets('PedidoEmExecucao finalizado esconde banner de Pagamento protegido',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          const PedidoExecucaoTela(
            pedido: PedidoEmExecucao(
              numero: '#123',
              titulo: 'Troca de tomada',
              etapas: [],
              fotos: [],
              pagamentoConfirmado: true,
              estadoApi: 'concluido',
            ),
          ),
        ),
      );
      expect(
        find.text('Pagamento protegido: fica guardado até o serviço ser confirmado.'),
        findsNothing,
      );
    });

    testWidgets('EnviarNotaTela mostra aviso claro quando serviço não está em andamento',
        (tester) async {
      await tester.pumpWidget(
        _envolver(
          EnviarNotaTela(
            servico: _ServicoNotaFake(),
            pedidoId: 'p1',
            tituloPedido: 'Troca de tomada',
            servicoEmAndamento: false,
          ),
        ),
      );
      expect(
        find.text('Envio disponível após iniciar o serviço (check-in).'),
        findsOneWidget,
      );
    });
  });
}

class _ServicoNotaFake implements ServicoNotaMaterial {
  @override
  Future<NotaMaterial?> carregar(String pedidoId) async => null;

  @override
  Future<List<NotaMaterial>> carregarTodas(String pedidoId) async => const [];

  @override
  Future<NotaMaterial> enviar(EnvioNota envio) async => throw UnimplementedError();
}
