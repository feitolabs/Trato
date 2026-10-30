import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';
import 'package:trato/dados/repositorios.dart';
import 'package:trato/dados/repositorios_fake.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/dados_exemplo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/orcamentos/detalhe_orcamento_tela.dart';
import 'package:trato/telas/orcamentos/dados_exemplo.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pagamento/aguardando_pagamento_tela.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/tema/tema.dart';


/// Backend simulado em memória: guarda o estado do pedido e é o ÚNICO que diz quando está pago.
class _Backend {
  String estado = 'aberto';
  bool pagoNoProvedor = false;
  final List<String> chamadas = [];
  EnvioAvaliacao? avaliacao;
}

class _Pedidos extends RepositorioPedidosFake {
  _Pedidos(this.b);

  final _Backend b;

  @override
  Future<PedidosDoCliente> listar() async {
    final (texto, tipo) = switch (b.estado) {
      'aberto' => ('Aguardando orçamentos', TipoStatus.info),
      'orcamento_aceito' => ('Aguardando pagamento', TipoStatus.alerta),
      'em_andamento' => ('Em execução · pagamento retido', TipoStatus.info),
      _ => ('Finalizado', TipoStatus.sucesso),
    };
    final item = PedidoResumo(
      id: 'sim1',
      estadoApi: b.estado,
      titulo: 'Instalar ventilador',
      subtitulo: 'Aberto hoje',
      statusTexto: texto,
      statusTipo: tipo,
    );
    return b.estado == 'concluido'
        ? PedidosDoCliente(finalizados: [item])
        : PedidosDoCliente(emAndamento: [item]);
  }

  @override
  Future<void> confirmarConclusao(String pedidoId) async {
    b.chamadas.add('confirmar_conclusao');
    b.estado = 'concluido';
  }

  @override
  Future<void> avaliar(String pedidoId, EnvioAvaliacao avaliacao) async {
    b.chamadas.add('avaliar');
    b.avaliacao = avaliacao;
  }
}

class _Orcamentos extends RepositorioOrcamentosFake {
  _Orcamentos(this.b);

  final _Backend b;

  @override
  Future<void> aceitar(String pedidoId, String orcamentoId) async {
    b.chamadas.add('aceitar:$orcamentoId');
    b.estado = 'orcamento_aceito';
  }
}

class _Pagamento extends RepositorioPagamentoFake {
  _Pagamento(this.b);

  final _Backend b;

  @override
  Future<Cobranca> criarCobranca(String pedidoId, MetodoPagamento metodo) async {
    b.chamadas.add('cobranca:${metodo.name}');
    return const Cobranca(id: 'cb1', pixCopiaECola: '00020126-teste');
  }

  /// "Pago" só depois que o provedor confirmou (webhook); o app só consulta.
  @override
  Future<StatusPagamento> status(String pedidoId) async {
    b.chamadas.add('status');
    if (!b.pagoNoProvedor) return StatusPagamento.aguardando;
    b.estado = 'em_andamento';
    return StatusPagamento.pago;
  }
}

Future<void> _tocar(WidgetTester tester, String texto) async {
  await tester.tap(find.text(texto).last);
  await tester.pumpAndSettle();
}

void main() {

  testWidgets(
    'pedido → orçamento → aceite → pagamento aguardando → confirmado → execução → conclusão → avaliação',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = _Backend();
      final antes = RotasTrato.repos;
      addTearDown(() => RotasTrato.repos = antes);
      final base = RepositoriosTrato.demo();
      RotasTrato.repos = RepositoriosTrato(
        pedidos: _Pedidos(b),
        orcamentos: _Orcamentos(b),
        pagamento: _Pagamento(b),
        chat: base.chat,
        notificacoes: base.notificacoes,
        perfil: base.perfil,
        profissional: base.profissional,
      );

      await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: const CascaClienteTela()));
      await tester.pumpAndSettle();

      // 1. Pedido aberto → orçamentos recebidos.
      await _tocar(tester, 'Pedidos');
      await _tocar(tester, 'Instalar ventilador');
      expect(find.byType(OrcamentosRecebidosTela), findsOneWidget);

      // 2. Detalhe do orçamento e aceite (o app só pede; o estado muda no backend).
      await tester.tap(find.text('Ver orçamento').at(1));
      await tester.pumpAndSettle();
      expect(find.byType(DetalheOrcamentoTela), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Aceitar orçamento'));
      await tester.pumpAndSettle();
      expect(b.chamadas, contains('aceitar:${orcamentosExemplo[1].id}'));
      expect(b.estado, 'orcamento_aceito');
      expect(find.byType(PagamentoTela), findsOneWidget);

      // 3. Pagar cria a cobrança e fica esperando: nada de "pago" antes do backend.
      await tester.tap(find.textContaining('Pagar').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(b.chamadas, contains('cobranca:pix'));
      expect(find.byType(AguardandoPagamentoTela), findsOneWidget);
      expect(find.text('Aguardando confirmação do pagamento'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AguardandoPagamentoTela), findsOneWidget);
      expect(find.textContaining('pago'), findsNothing);

      // 4. O provedor confirma; só então o app avança para o pedido em andamento.
      b.pagoNoProvedor = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(b.estado, 'em_andamento');
      expect(find.byType(PedidoExecucaoTela), findsOneWidget);

      // 5. Conclusão: o cliente confirma e o backend conclui.
      await _tocar(tester, 'Ver conclusão');
      expect(find.byType(ConclusaoTela), findsOneWidget);
      await _tocar(tester, 'Confirmar serviço');
      expect(b.estado, 'concluido');
      expect(find.byType(AvaliacaoTela), findsOneWidget);

      // 6. Avaliação enviada de verdade ao repositório.
      await tester.tap(find.byKey(const Key('estrela_Qualidade_5')));
      await tester.pump();
      await tester.tap(find.text('Enviar avaliação'));
      await tester.pumpAndSettle();
      expect(b.avaliacao!.notas[1], 5);
      expect(b.chamadas.last, 'avaliar');
      expect(find.byType(AvaliacaoTela), findsNothing);
    },
  );
}
