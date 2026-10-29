import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/carregador.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_fake.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

Future<void> _abrir(WidgetTester tester, Widget tela, {bool esperar = true}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _PedidosVazio extends RepositorioPedidosFake {
  @override
  Future<PedidosDoCliente> listar() async => const PedidosDoCliente();
}

class _PedidosQueFalham extends RepositorioPedidosFake {
  int tentativas = 0;

  @override
  Future<PedidosDoCliente> listar() async {
    tentativas++;
    if (tentativas == 1) throw ErroTrato.semInternet;
    return super.listar();
  }
}

class _PedidoComCodigo extends RepositorioPedidosFake {
  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => const PedidoEmExecucao(
        numero: '#4F2A',
        titulo: 'Serviço agendado',
        etapas: [
          EtapaLinhaDoTempo(titulo: 'Contratado', detalhe: '', estado: EstadoEtapa.atual),
        ],
        fotos: [],
        codigoInicio: '4821',
      );
}

RepositoriosTrato _repos({
  RepositorioPedidos? pedidos,
  RepositorioPagamento? pagamento,
  RepositorioOrcamentos? orcamentos,
  RepositorioNotificacoes? notificacoes,
}) =>
    RepositoriosTrato(
      pedidos: pedidos ?? RepositorioPedidosFake(),
      orcamentos: orcamentos ?? RepositorioOrcamentosFake(),
      pagamento: pagamento ?? RepositorioPagamentoFake(),
      chat: RepositorioChatFake(),
      notificacoes: notificacoes ?? RepositorioNotificacoesFake(),
      perfil: RepositorioPerfilFake(),
      profissional: RepositorioProfissionalFake(),
    );

void main() {
  setUpAll(carregarFontesTrato);
  tearDown(() => RotasTrato.repos = RepositoriosTrato.demo());

  group('Carregador', () {
    testWidgets('mostra carregando e depois o conteúdo', (tester) async {
      await _abrir(
        tester,
        Carregador<String>(
          carregar: () async => 'pronto',
          construir: (_, d) => Scaffold(body: Text(d)),
        ),
      );
      expect(find.text('pronto'), findsOneWidget);
    });

    testWidgets('erro mostra a mensagem em português e tenta de novo', (tester) async {
      var chamadas = 0;
      await _abrir(
        tester,
        Carregador<String>(
          carregar: () async {
            chamadas++;
            if (chamadas == 1) throw ErroTrato.sessaoExpirada;
            return 'voltou';
          },
          construir: (_, d) => Scaffold(body: Text(d)),
        ),
      );
      expect(find.text(ErroTrato.sessaoExpirada.mensagem), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();

      expect(find.text('voltou'), findsOneWidget);
    });

    testWidgets('vazio mostra o aviso, não uma tela em branco', (tester) async {
      await _abrir(
        tester,
        Carregador<List<int>>(
          carregar: () async => [],
          vazio: (l) => l.isEmpty,
          tituloVazio: 'Nada aqui',
          construir: (_, __) => const Scaffold(body: Text('lista')),
        ),
      );
      expect(find.text('Nada aqui'), findsOneWidget);
      expect(find.text('lista'), findsNothing);
    });
  });

  group('Seus pedidos', () {
    testWidgets('lista os pedidos do repositório', (tester) async {
      await _abrir(tester, RotasTrato.abaPedidos());
      expect(find.text('Troca de tomadas e chuveiro'), findsOneWidget);
      expect(find.text('Novo pedido'), findsOneWidget);
    });

    testWidgets('sem pedidos mostra o estado vazio', (tester) async {
      RotasTrato.repos = _repos(pedidos: _PedidosVazio());
      await _abrir(tester, RotasTrato.abaPedidos());
      expect(find.text('Você ainda não fez pedidos'), findsOneWidget);
    });

    testWidgets('erro de rede mostra mensagem e "Tentar de novo" recupera', (tester) async {
      RotasTrato.repos = _repos(pedidos: _PedidosQueFalham());
      await _abrir(tester, RotasTrato.abaPedidos());
      expect(find.text(ErroTrato.semInternet.mensagem), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();

      expect(find.text('Troca de tomadas e chuveiro'), findsOneWidget);
    });

    testWidgets('Novo pedido preenche, envia ao repositório e avisa', (tester) async {
      final pedidos = RepositorioPedidosFake();
      RotasTrato.repos = _repos(pedidos: pedidos);
      await _abrir(tester, const CascaClienteTela(abaInicial: 2));

      await tester.tap(find.text('Novo pedido'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Trocar duas tomadas da cozinha');
      final enviar = find.text('Próximo');
      await tester.ensureVisible(enviar.last);
      await tester.tap(enviar.last);
      await tester.pumpAndSettle();

      expect(pedidos.criados, ['Trocar duas tomadas da cozinha']);
      expect(find.textContaining('Pedido enviado'), findsOneWidget);
    });
  });

  group('Pagamento', () {
    testWidgets('mostra "Aguardando confirmação" e não "pago" antes do backend', (tester) async {
      var consultas = 0;
      var confirmado = false;
      await _abrir(
        tester,
        AguardandoPagamentoTela(
          intervalo: const Duration(seconds: 1),
          consultar: () async =>
              ++consultas < 3 ? StatusPagamento.aguardando : StatusPagamento.pago,
          aoConfirmar: () => confirmado = true,
        ),
        esperar: false,
      );
      expect(find.text('Aguardando confirmação do pagamento'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(confirmado, isFalse);
      expect(find.textContaining('pago'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(confirmado, isTrue);
    });

    testWidgets('falha de rede na consulta não derruba a espera', (tester) async {
      var consultas = 0;
      var confirmado = false;
      await _abrir(
        tester,
        AguardandoPagamentoTela(
          intervalo: const Duration(seconds: 1),
          consultar: () async {
            consultas++;
            if (consultas == 1) throw ErroTrato.semInternet;
            return StatusPagamento.pago;
          },
          aoConfirmar: () => confirmado = true,
        ),
        esperar: false,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(ErroTrato.semInternet.mensagem), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(confirmado, isTrue);
    });

    testWidgets('pagar cria a cobrança e abre a espera', (tester) async {
      final pagamento = RepositorioPagamentoFake();
      RotasTrato.repos = _repos(pagamento: pagamento);
      await _abrir(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => RotasTrato.abrirPedido(
                context,
                const PedidoResumo(
                  id: 'p1',
                  estadoApi: 'orcamento_aceito',
                  titulo: 'T',
                  subtitulo: 'S',
                  statusTexto: 'Aguardando pagamento',
                  statusTipo: TipoStatus.info,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(PagamentoTela), findsOneWidget);

      await tester.tap(find.textContaining('Pagar').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(pagamento.cobrancas, hasLength(1));
      expect(find.byType(AguardandoPagamentoTela), findsOneWidget);
      // Sai da tela para encerrar o relógio da consulta.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Pedido em execução', () {
    testWidgets('mostra o código de início que veio do backend', (tester) async {
      RotasTrato.repos = _repos(pedidos: _PedidoComCodigo());
      await _abrir(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => RotasTrato.abrirPedido(
                context,
                const PedidoResumo(
                  id: 'p1',
                  estadoApi: 'agendado',
                  titulo: 'T',
                  subtitulo: 'S',
                  statusTexto: 'Agendado',
                  statusTipo: TipoStatus.info,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(PedidoExecucaoTela), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
    });
  });

  group('Notificações e Carteira', () {
    testWidgets('lista as notificações do repositório', (tester) async {
      await _abrir(
        tester,
        NotificacoesTela(servico: ServicoNotificacoesRepositorio(RepositorioNotificacoesFake())),
      );
      expect(find.text('Carlos Mendes chegou'), findsOneWidget);
    });

    testWidgets('Carteira como extrato: sem saque e sem saldo próprio (D15)', (tester) async {
      await _abrir(
        tester,
        CarteiraTela(
          soExtrato: true,
          dados: DadosCarteira(extrato: await RepositorioProfissionalFake().extrato()),
        ),
      );
      expect(find.text('Sacar via Pix'), findsNothing);
      expect(find.text('Disponível para saque'), findsNothing);
      expect(find.text('Extrato por serviço'), findsOneWidget);
    });
  });
}
