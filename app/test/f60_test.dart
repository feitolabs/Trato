import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/busca/busca_profissionais_tela.dart';
import 'package:trato/telas/busca/modelos.dart';
import 'package:trato/telas/catalogo/avaliacoes_profissional_tela.dart';
import 'package:trato/telas/cliente/modelos.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'package:trato/telas/perfil_publico/avaliacoes_recebidas_tela.dart';
import 'package:trato/telas/perfil_publico/perfil_publico.dart' as pub;
import 'package:trato/tema/tema.dart';

Widget _envolver(Widget child, {ThemeData? tema}) =>
    MaterialApp(theme: tema ?? TemaTrato.claro, home: child);

class _ServicoMensagensF60Fake implements ServicoMensagens {
  _ServicoMensagensF60Fake(this.itens);
  final List<ConversaResumo> itens;

  @override
  Future<List<ConversaResumo>> listar() async => itens;
}

class _ServicoBuscaF60Fake implements ServicoBusca {
  @override
  Future<List<Profissional>> buscar(String termo) async => const [];
}

class _ServicoPerfilPublicoF60Fake implements pub.ServicoPerfilPublico {
  _ServicoPerfilPublicoF60Fake(this.avaliacoes);
  final List<Avaliacao> avaliacoes;

  @override
  Future<List<Avaliacao>> carregarAvaliacoes() async => avaliacoes;

  @override
  Future<pub.PerfilPublico> carregarPerfil() async => throw UnimplementedError();

  @override
  Future<bool> temPerfilProfissional() async => true;
}

void main() {
  group('F60 — MensagensTela (busca, chips rápidos, #código, estado e não lidas)', () {
    const conversas = [
      ConversaResumo(
        pedidoId: 'fdda-1111-2222',
        tituloPedido: 'Pintura de interiores',
        interlocutor: 'Carlos Silva',
        iniciais: 'CS',
        ultimaMensagem: 'Posso chegar às 14h',
        quando: '13:55',
        naoLidas: 2,
        contratado: true,
        encerrada: false,
      ),
      ConversaResumo(
        pedidoId: '4a75-3333-4444',
        tituloPedido: 'Pintura de interiores',
        interlocutor: 'Carlos Silva',
        iniciais: 'CS',
        ultimaMensagem: 'Serviço finalizado, obrigado!',
        quando: 'ontem',
        naoLidas: 0,
        contratado: true,
        encerrada: true,
      ),
    ];

    testWidgets('exibe #XXXX e estado, destaca não lidas em negrito e filtra por busca e chips',
        (tester) async {
      await tester.pumpWidget(
        _envolver(MensagensTela(servico: _ServicoMensagensF60Fake(conversas))),
      );
      await tester.pumpAndSettle();

      // Subtítulo com #XXXX evita dois cards idênticos do mesmo profissional.
      expect(find.text('Pintura de interiores · #FDDA'), findsOneWidget);
      expect(find.text('Pintura de interiores · #4A75'), findsOneWidget);
      expect(find.text('Em andamento'), findsOneWidget);
      expect(find.text('Concluído'), findsOneWidget);

      // Badge laranja de não lidas e prévia em negrito.
      expect(find.byKey(const ValueKey('badge-nao-lidas-fdda-1111-2222')), findsOneWidget);
      final previaNaoLida = tester.widget<Text>(find.text('Posso chegar às 14h'));
      expect(previaNaoLida.style?.fontWeight, FontWeight.w700);

      // Filtro por chip "Não lidas (1)".
      await tester.tap(find.byKey(const ValueKey('chip-mensagens-naoLidas')));
      await tester.pumpAndSettle();
      expect(find.text('Pintura de interiores · #FDDA'), findsOneWidget);
      expect(find.text('Pintura de interiores · #4A75'), findsNothing);

      // Filtro por chip "Finalizadas (1)".
      await tester.ensureVisible(find.byKey(const ValueKey('chip-mensagens-finalizadas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chip-mensagens-finalizadas')));
      await tester.pumpAndSettle();
      expect(find.text('Pintura de interiores · #4A75'), findsOneWidget);
      expect(find.text('Pintura de interiores · #FDDA'), findsNothing);

      // Volta para "Todas (2)" e filtra pelo código #FDDA na busca.
      await tester.ensureVisible(find.byKey(const ValueKey('chip-mensagens-todas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chip-mensagens-todas')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('campo-busca-mensagens')), '#FDDA');
      await tester.pumpAndSettle();
      expect(find.text('Pintura de interiores · #FDDA'), findsOneWidget);
      expect(find.text('Pintura de interiores · #4A75'), findsNothing);
    });
  });

  group('F60 — BuscaProfissionaisTela (card "Não achou o que procura?")', () {
    testWidgets('exibe card e botão "Pedir orçamento" dispara aoPedirOrcamento',
        (tester) async {
      var pediuOrcamento = false;
      await tester.pumpWidget(
        _envolver(
          BuscaProfissionaisTela(
            servico: _ServicoBuscaF60Fake(),
            sugestoes: const [
              CategoriaServico('Eletricista', Icons.bolt),
            ],
            aoPedirOrcamento: () => pediuOrcamento = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Não achou o que procura?'), findsOneWidget);
      expect(
        find.text('Descreva o serviço e receba orçamentos de profissionais verificados.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('botao-pedir-orcamento-busca')));
      await tester.pumpAndSettle();
      expect(pediuOrcamento, isTrue);
    });
  });

  group('F60 — Filtro por estrelas nas Avaliações', () {
    testWidgets('AvaliacoesProfissionalTela filtra 5,0 em ★ 5 e 4,8 em ★ 4', (tester) async {
      const prof = Profissional(
        id: 'p1',
        nome: 'Carlos Silva',
        iniciais: 'CS',
        verificacao: 'Verificado',
        especialidade: 'Eletricista',
        servicosConcluidos: 12,
        nota: 4.9,
        distanciaKm: 2.5,
        detalhe: DetalhePerfil(
          noTratoDesde: 2025,
          totalAvaliacoes: 2,
          taxaConclusao: 98,
          verificacoes: ['Identidade conferida'],
          avaliacoes: [
            Avaliacao(
              cliente: 'Ana Paula',
              servico: 'Troca de disjuntor',
              detalhes: 'ontem',
              nota: 5.0,
              comentario: 'Perfeito, nota 5 fechada!',
            ),
            Avaliacao(
              cliente: 'Bruno Costa',
              servico: 'Instalação de tomada',
              detalhes: 'há 3 dias',
              nota: 4.8,
              comentario: 'Muito bom atendimento 4,8.',
            ),
          ],
        ),
      );

      await tester.pumpWidget(_envolver(const AvaliacoesProfissionalTela(profissional: prof)));
      await tester.pumpAndSettle();

      expect(find.text('Todas (2)'), findsOneWidget);
      expect(find.text('★ 5 (1)'), findsOneWidget);
      expect(find.text('★ 4 (1)'), findsOneWidget);

      // Filtra ★ 5 -> só Ana Paula (5,0).
      await tester.tap(find.byKey(const ValueKey('filtro-estrela-5')));
      await tester.pumpAndSettle();
      expect(find.text('Ana Paula'), findsOneWidget);
      expect(find.text('Bruno Costa'), findsNothing);

      // Filtra ★ 4 -> só Bruno Costa (4,8).
      await tester.tap(find.byKey(const ValueKey('filtro-estrela-4')));
      await tester.pumpAndSettle();
      expect(find.text('Bruno Costa'), findsOneWidget);
      expect(find.text('Ana Paula'), findsNothing);

      // Filtra ★ 3 (vazio) e clica em "Ver todas".
      await tester.tap(find.byKey(const ValueKey('filtro-estrela-3')));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma avaliação com 3 estrelas'), findsOneWidget);
      await tester.tap(find.text('Ver todas'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Paula'), findsOneWidget);
      expect(find.text('Bruno Costa'), findsOneWidget);
    });

    testWidgets('AvaliacoesRecebidasTela filtra por estrelas no perfil do profissional',
        (tester) async {
      final servico = _ServicoPerfilPublicoF60Fake(const [
        Avaliacao(
          id: 'av1',
          cliente: 'Mariana',
          servico: 'Elétrica',
          detalhes: 'hoje',
          nota: 5.0,
          comentario: 'Excelente!',
        ),
        Avaliacao(
          id: 'av2',
          cliente: 'Pedro',
          servico: 'Iluminação',
          detalhes: 'ontem',
          nota: 4.6,
          comentario: 'Bom trabalho.',
        ),
      ]);

      await tester.pumpWidget(_envolver(AvaliacoesRecebidasTela(servico: servico)));
      await tester.pumpAndSettle();

      expect(find.text('Todas (2)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filtro-estrela-4')));
      await tester.pumpAndSettle();
      expect(find.text('Pedro'), findsOneWidget);
      expect(find.text('Mariana'), findsNothing);
    });
  });
}
