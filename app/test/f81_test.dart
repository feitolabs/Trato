import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/perfil_cliente/extrato_tratinhos_tela.dart';
import 'package:trato/telas/perfil_cliente/modelos.dart';
import 'package:trato/telas/profissional/calculadora_orcamento_tela.dart';
import 'package:trato/telas/recorrencias/modelos.dart';
import 'package:trato/telas/recorrencias/servico_fake.dart';
import 'package:trato/telas/recorrencias/servicos_recorrentes_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/profissional/servico_orcamento_fake.dart';
import 'apoio/fontes.dart';

final _quando = DateTime.utc(2030, 12, 5, 17);

Recorrencia _serie({String papel = 'cliente', int? proposto}) => Recorrencia(
      id: 'r1',
      status: 'ativa',
      frequencia: 'semanal',
      valorCentavos: 18000,
      valorPropostoCentavos: proposto,
      proximaVisita: _quando,
      meuPapel: papel,
      propostoPorMim: false,
      outraParteNome: 'Carlos M.',
      pedidoOrigemId: 'p',
      visitas: [VisitaRecorrente(id: 'v1', dataPrevista: _quando, status: 'agendada')],
    );

Future<void> _tela(WidgetTester t, {double fonte = 1, Size tamanho = const Size(390, 844)}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 40);
  t.view.viewPadding = const FakeViewPadding(top: 40);
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Abre a tela como o app abre: empurrada por cima de outra (por isso há "voltar").
Future<void> _empurrar(WidgetTester t, Widget tela) async {
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: Builder(
      builder: (c) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => tela)),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('BUG-J01: detalhe do serviço recorrente', () {
    for (final papel in ['cliente', 'profissional']) {
      testWidgets('$papel: barra com título e voltar, cartões na largura toda e ações agrupadas',
          (t) async {
        await _tela(t, tamanho: const Size(390, 1600));
        await _empurrar(
          t,
          DetalheRecorrenciaTela(
            servico: ServicoRecorrenciasFake(
                series: [_serie(papel: papel, proposto: papel == 'cliente' ? 20000 : null)]),
            recorrenciaId: 'r1',
          ),
        );
        expect(find.descendant(of: find.byType(AppBar), matching: find.text('Serviço recorrente')),
            findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);
        // Sem espaço vazio grande no topo: o nome vem logo abaixo da barra.
        final barra = t.getRect(find.byType(AppBar));
        expect(t.getTopLeft(find.text('Carlos M.')).dy - barra.bottom, lessThan(40));

        final visita = t.getRect(find.byKey(const ValueKey('visita-v1')));
        final acoes = t.getRect(find.byKey(const ValueKey('acoes-serie')));
        expect(visita.width, closeTo(acoes.width, 0.5));
        expect(visita.width, greaterThan(390 - 48), reason: 'cartão de visita encolhido');
        expect(visita.left, closeTo(acoes.left, 0.5));
        if (papel == 'cliente') {
          final reajuste = t.getRect(find.byKey(const ValueKey('cartao-reajuste')));
          expect(reajuste.width, closeTo(visita.width, 0.5));
        }
        // Ações alinhadas à esquerda, com ícone; "Cancelar série" por último e em vermelho.
        final xs = [
          for (final k in ['pausar-serie', 'pular-proxima', 'cancelar-serie'])
            t.getTopLeft(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Text))).dx
        ];
        expect(xs.toSet().length, 1);
        expect(
          t.getTopLeft(find.byKey(const ValueKey('cancelar-serie'))).dy,
          greaterThan(t.getTopLeft(find.byKey(const ValueKey('pular-proxima'))).dy),
        );
        final cancelar = t.widget<Text>(find.text('Cancelar série'));
        final cores = t.element(find.text('Cancelar série')).cores;
        expect(cancelar.style!.color, cores.vermelhoTexto);
        expect(find.byKey(const ValueKey('propor-reajuste')),
            papel == 'profissional' ? findsOneWidget : findsNothing);
        expect(find.text('Próxima visita: qui, 05/12 · 14:00 (Brasília)'), findsOneWidget);
        expect(find.textContaining('horário de Brasília'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('carregando e erro também têm barra com voltar', (t) async {
      await _tela(t);
      await _empurrar(
        t,
        DetalheRecorrenciaTela(
            servico: ServicoRecorrenciasFake(falharAoCarregar: true), recorrenciaId: 'r1'),
      );
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('lista: cartões na largura toda (sem margem dobrada) e com voltar', (t) async {
      await _tela(t);
      await _empurrar(
          t, ServicosRecorrentesTela(servico: ServicoRecorrenciasFake(series: [_serie()])));
      expect(find.byType(BackButton), findsOneWidget);
      final cartao = t.getRect(find.byKey(const ValueKey('serie-r1')));
      expect(cartao.left, lessThanOrEqualTo(24), reason: 'margem dobrada');
      expect(cartao.width, greaterThan(390 - 48));
      expect(cartao.center.dx, closeTo(195, 0.5));
    });
  });

  group('BUG-J02: banner "Sem internet"', () {
    for (final fonte in [1.0, 1.3]) {
      for (final (nome, casca) in <(String, Widget Function())>[
        ('profissional', () => RotasTrato.cascaProfissionalParaTeste()),
        ('cliente', () => const CascaClienteTela()),
      ]) {
        testWidgets('$nome em 390x844 fonte x$fonte: fundo até o topo e textos sem quebrar',
            (t) async {
          ligarDemoNosTestes();
          await _tela(t, fonte: fonte);
          final online = ValueNotifier<bool>(false);
          final salvos = ValueNotifier<bool>(true);
          await t.pumpWidget(MaterialApp(
            theme: TemaTrato.claro,
            builder: (context, filho) => EscalaFonteLimitada(
              child: MoldeConexao(estado: online, dadosSalvos: salvos, child: filho!),
            ),
            home: casca(),
          ));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 150));
          }
          expect(t.takeException(), isNull);
          for (final texto in ['Sem internet', 'Mostrando dados salvos', 'Tentar novamente']) {
            expect(find.text(texto), findsOneWidget);
            final altura = t.getSize(find.text(texto)).height;
            expect(altura, lessThan(14 * fonte * 2), reason: '"$texto" quebrou em duas linhas');
            final r = t.getRect(find.text(texto));
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(390));
          }
          expect(find.textContaining('— sem internet'), findsNothing);
          // A área da barra de status tem o fundo do app (nem preta nem branca).
          final fundo = find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == TemaTrato.claro.scaffoldBackgroundColor);
          expect(t.getRect(fundo.first).top, 0);
          expect(t.getRect(fundo.first).width, 390);
          final banner = t.getRect(find.byKey(const ValueKey('banner-sem-conexao')));
          expect(banner.top, greaterThanOrEqualTo(40)); // abaixo da barra de status

          online.value = true;
          await t.pump();
          expect(find.text('Sem internet'), findsNothing);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 30));
        });
      }
    }

    testWidgets('sem dados salvos mostra só a linha principal', (t) async {
      await _tela(t);
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: Scaffold(
          body: BannerSemConexao(
              estado: ValueNotifier<bool>(false), dadosSalvos: ValueNotifier<bool>(false)),
        ),
      ));
      expect(find.text('Sem internet'), findsOneWidget);
      expect(find.text('Mostrando dados salvos'), findsNothing);
    });
  });

  group('Defeitos vistos no PDF', () {
    testWidgets('extrato mostra "Bônus de indicação" (não o código cru)', (t) async {
      await _tela(t);
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: ExtratoTratinhosTela(
          perfil: PerfilCliente(
            nome: 'Ana',
            iniciais: 'A',
            resumo: '',
            grupos: const [],
            moedas: 300,
            moedasValorCentavos: 1,
            moedasExtrato: [
              LancamentoTratinho(
                  tipo: 'bonus_indicacao', quantidade: 300, criadaEm: DateTime(2030, 1, 1)),
            ],
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Bônus de indicação'), findsOneWidget);
      expect(find.textContaining('bonus_indicacao'), findsNothing);
      expect(find.textContaining('bonus indicacao'), findsNothing);
    });

    testWidgets('campo Garantia da calculadora é legível (cor do texto do tema)', (t) async {
      await _tela(t, tamanho: const Size(390, 1600));
      await t.pumpWidget(MaterialApp(
        theme: TemaTrato.claro,
        home: CalculadoraOrcamentoTela(servico: ServicoOrcamentoFake(), tituloPedido: 'Tomadas'),
      ));
      await t.pumpAndSettle();
      final texto = find.text('90 dias');
      expect(texto, findsOneWidget);
      final rico = t.widget<RichText>(find.descendant(of: texto, matching: find.byType(RichText)));
      expect(rico.text.style!.color, t.element(texto).cores.texto);
    });
  });
}
