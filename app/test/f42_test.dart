import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/servicos_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/telas/profissional_inicio/primeiros_passos.dart';
import 'package:trato/tema/tema.dart';

InicioProfissional _inicio({
  bool emAnalise = false,
  List<PedidoAberto> pedidos = const [
    PedidoAberto(
      id: 'p1',
      titulo: 'Trocar tomada',
      bairro: 'Savassi',
      prazo: 'hoje',
    ),
  ],
  List<OrcamentoEnviado> orcamentosEnviados = const [],
}) =>
    InicioProfissional(
      nome: 'Carlos',
      disponivelAgora: true,
      carteira: const ResumoCarteira(retidoCentavos: 0, paraSacarCentavos: 0),
      pedidos: pedidos,
      orcamentosEnviados: orcamentosEnviados,
      emAnalise: emAnalise,
    );

const _orcamentoExemplo = OrcamentoEnviado(
  pedidoId: 'p1',
  titulo: 'Trocar tomada',
  valorCentavos: 15000,
  versao: 1,
  situacao: 'aguardando',
);

const _dadosPendentes = DadosPrimeirosPassos(aprovado: true);

const _dadosPerfilCompleto = DadosPrimeirosPassos(
  aprovado: true,
  temDescricao: true,
  temCategoria: true,
  temRegiao: true,
  contaAtiva: true,
);

const _dados3Concluidos = DadosPrimeirosPassos(
  aprovado: true,
  temDescricao: true,
  temCategoria: true,
  temRegiao: true,
  contaAtiva: true,
  servicosConcluidos: 1,
);

Future<void> _abrir(
  WidgetTester tester, {
  required InicioProfissional inicio,
  Future<DadosPrimeirosPassos> Function()? carregar,
  ValueChanged<DestinoCompletar>? aoCompletarPerfil,
  VoidCallback? aoVerPedidos,
  VoidCallback? aoVerAgenda,
}) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: InicioProfissionalTela(
        dados: inicio,
        carregarPrimeirosPassos: carregar,
        aoCompletarPerfil: aoCompletarPerfil,
        aoVerPedidos: aoVerPedidos,
        aoVerAgenda: aoVerAgenda,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('F42 · leitura segura da API', () {
    test('dados ausentes ou de tipo errado tratam passos como pendentes sem quebrar', () {
      final vazio = DadosPrimeirosPassos.deApi();
      expect(vazio.aprovado, isFalse);
      expect(vazio.perfilCompleto, isFalse);
      expect(vazio.servicosConcluidos, 0);

      final errado = DadosPrimeirosPassos.deApi(
        perfil: {
          'status': 123,
          'bio': 42,
          'categorias': 'eletricista',
          'regioes': null,
          'conta_recebimento': 'sim',
        },
        servicosConcluidos: 'dois',
      );
      expect(errado.aprovado, isFalse);
      expect(errado.temDescricao, isFalse);
      expect(errado.temCategoria, isFalse);
      expect(errado.temRegiao, isFalse);
      expect(errado.contaAtiva, isFalse);
      expect(errado.servicosConcluidos, 0);
    });

    test('destinoCompletar aponta para perfil ou conta de recebimento conforme o que falta', () {
      const faltaPerfil = DadosPrimeirosPassos(aprovado: true, temDescricao: true);
      expect(faltaPerfil.destinoCompletar, DestinoCompletar.perfil);

      const faltaConta = DadosPrimeirosPassos(
        aprovado: true,
        temDescricao: true,
        temCategoria: true,
        temRegiao: true,
        contaAtiva: false,
      );
      expect(faltaConta.destinoCompletar, DestinoCompletar.contaRecebimento);
      expect(faltaConta.perfilCompleto, isFalse);
    });

    test('ServicoPrimeirosPassosApi tolera falha em uma das rotas', () async {
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: SessaoTrato()..entrar('token'),
        cliente: MockClient((r) async {
          if (r.url.path == '/v1/profissional/perfil') {
            return http.Response(
              jsonEncode({
                'status': 'aprovado',
                'bio': 'Eletricista',
                'categorias': ['eletricista'],
                'regioes': ['Savassi'],
                'conta_recebimento': {'cadastrada': true},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('erro', 500);
        }),
      );
      final dados = await ServicoPrimeirosPassosApi(api).carregar();
      expect(dados.aprovado, isTrue);
      expect(dados.perfilCompleto, isTrue);
      expect(dados.servicosConcluidos, 0);
    });
  });

  group('F42 · cartão dos 3 primeiros passos', () {
    testWidgets('profissional aprovado vê o cartão e os 3 passos pendentes', (tester) async {
      await _abrir(
        tester,
        inicio: _inicio(),
        carregar: () async => _dadosPendentes,
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsOneWidget);
      expect(find.text('Seus primeiros passos'), findsOneWidget);
      expect(find.text('0 de 3'), findsOneWidget);
      expect(find.text('Complete seu perfil.'), findsOneWidget);
      expect(find.text('Leva 2 minutos.'), findsOneWidget);
      expect(find.text('Completar'), findsOneWidget);
      expect(find.text('Envie seu 1º orçamento.'), findsOneWidget);
      expect(find.text('Veja os pedidos perto de você.'), findsOneWidget);
      expect(find.text('Ver pedidos'), findsOneWidget);
      expect(find.text('Faça seu 1º serviço.'), findsOneWidget);
      expect(find.text('Quando um cliente aceitar, ele aparece na Agenda.'), findsOneWidget);
      expect(find.text('Ver agenda'), findsOneWidget);
      expect(find.text('Dispensar'), findsOneWidget);
    });

    testWidgets('profissional não aprovado ou em análise não vê o cartão', (tester) async {
      await _abrir(
        tester,
        inicio: _inicio(),
        carregar: () async => const DadosPrimeirosPassos(aprovado: false),
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsNothing);

      await _abrir(
        tester,
        inicio: _inicio(emAnalise: true),
        carregar: () async => _dadosPendentes,
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsNothing);
    });

    testWidgets('passo 2 sem pedidos abertos mostra linha sem promessa de aviso', (tester) async {
      await _abrir(
        tester,
        inicio: _inicio(pedidos: const []),
        carregar: () async => _dadosPendentes,
      );
      expect(find.text('Ainda não há pedidos perto de você.'), findsOneWidget);
      expect(find.textContaining('Avisamos'), findsNothing);
    });

    testWidgets('mostra progresso e marca passos concluídos individualmente', (tester) async {
      await _abrir(
        tester,
        inicio: _inicio(orcamentosEnviados: const [_orcamentoExemplo]),
        carregar: () async => _dadosPerfilCompleto,
      );
      expect(find.text('2 de 3'), findsOneWidget);
      expect(find.text('Perfil completo ✓'), findsOneWidget);
      expect(find.text('1º orçamento enviado ✓'), findsOneWidget);
      expect(find.text('Faça seu 1º serviço.'), findsOneWidget);
    });

    testWidgets('botões acionam os callbacks certos', (tester) async {
      DestinoCompletar? destino;
      var pediuPedidos = false;
      var pediuAgenda = false;
      await _abrir(
        tester,
        inicio: _inicio(),
        carregar: () async => const DadosPrimeirosPassos(
          aprovado: true,
          temDescricao: true,
          temCategoria: true,
          temRegiao: true,
          contaAtiva: false,
        ),
        aoCompletarPerfil: (d) => destino = d,
        aoVerPedidos: () => pediuPedidos = true,
        aoVerAgenda: () => pediuAgenda = true,
      );
      await tester.tap(find.text('Completar'));
      await tester.tap(find.text('Ver pedidos'));
      await tester.tap(find.text('Ver agenda'));
      expect(destino, DestinoCompletar.contaRecebimento);
      expect(pediuPedidos, isTrue);
      expect(pediuAgenda, isTrue);
    });

    testWidgets('Dispensar esconde o cartão e persiste no aparelho', (tester) async {
      await _abrir(
        tester,
        inicio: _inicio(),
        carregar: () async => _dadosPendentes,
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dispensar-primeiros-passos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsNothing);

      // Nova abertura da tela continua dispensada.
      await _abrir(
        tester,
        inicio: _inicio(),
        carregar: () async => _dadosPendentes,
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsNothing);
    });

    testWidgets('com os 3 passos concluídos mostra mensagem uma única vez', (tester) async {
      await _abrir(
        tester,
        inicio: _inicio(orcamentosEnviados: const [_orcamentoExemplo]),
        carregar: () async => _dados3Concluidos,
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsNothing);
      expect(find.byKey(const Key('primeiros-passos-concluidos')), findsOneWidget);
      expect(find.text('Primeiros passos concluídos.'), findsOneWidget);
      expect(find.text('Você fez os 3. Acompanhe seus pedidos no Início.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('fechar-primeiros-passos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('primeiros-passos-concluidos')), findsNothing);

      // Reabertura seguinte não mostra mais a mensagem nem o cartão.
      await _abrir(
        tester,
        inicio: _inicio(orcamentosEnviados: const [_orcamentoExemplo]),
        carregar: () async => _dados3Concluidos,
      );
      expect(find.byKey(const Key('primeiros-passos-concluidos')), findsNothing);
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsNothing);
    });

    testWidgets('dois usuários no mesmo aparelho têm estados independentes (F46)', (tester) async {
      // Usuário 1 dispensa o cartão.
      await _abrir(
        tester,
        inicio: _inicio(),
        carregar: () async => const DadosPrimeirosPassos(usuarioId: 'pro-1', aprovado: true),
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dispensar-primeiros-passos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsNothing);

      // Usuário 2 faz login no mesmo aparelho: ainda vê o cartão.
      await tester.pumpWidget(const SizedBox.shrink());
      await _abrir(
        tester,
        inicio: _inicio(),
        carregar: () async => const DadosPrimeirosPassos(usuarioId: 'pro-2', aprovado: true),
      );
      expect(find.byKey(const Key('cartao-primeiros-passos')), findsOneWidget);

      // Usuário 1 conclui os 3 passos e vê a mensagem; usuário 2 também vê a própria uma vez.
      await tester.pumpWidget(const SizedBox.shrink());
      await _abrir(
        tester,
        inicio: _inicio(orcamentosEnviados: const [_orcamentoExemplo]),
        carregar: () async => const DadosPrimeirosPassos(
          usuarioId: 'pro-3',
          aprovado: true,
          temDescricao: true,
          temCategoria: true,
          temRegiao: true,
          contaAtiva: true,
          servicosConcluidos: 1,
        ),
      );
      expect(find.byKey(const Key('primeiros-passos-concluidos')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _abrir(
        tester,
        inicio: _inicio(orcamentosEnviados: const [_orcamentoExemplo]),
        carregar: () async => const DadosPrimeirosPassos(
          usuarioId: 'pro-4',
          aprovado: true,
          temDescricao: true,
          temCategoria: true,
          temRegiao: true,
          contaAtiva: true,
          servicosConcluidos: 1,
        ),
      );
      expect(find.byKey(const Key('primeiros-passos-concluidos')), findsOneWidget);
    });
  });
}
