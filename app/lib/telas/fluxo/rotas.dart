import 'package:flutter/material.dart';

import '../cliente/casca_cliente_tela.dart';
import '../conclusao/avaliacao_tela.dart';
import '../conclusao/conclusao_tela.dart';
import '../conclusao/dados_exemplo.dart';
import '../conclusao/garantia_tela.dart';
import '../conclusao/relatar_problema_tela.dart';
import '../em_breve_tela.dart';
import '../pedidos/chat_pedido_tela.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedido_execucao_tela.dart';
import '../pedidos/seus_pedidos_tela.dart';
import '../profissional/area_profissional_provisoria.dart';

/// Liga as telas entre si. As telas não se conhecem: quem sabe para onde cada botão vai é
/// este arquivo. Os dados ainda são de exemplo (provisórios); a API entra depois.
abstract final class RotasTrato {
  static Future<T?> _abrir<T>(BuildContext context, Widget tela) =>
      Navigator.of(context).push(MaterialPageRoute<T>(builder: (_) => tela));

  static void _voltarAoInicio(BuildContext context) =>
      Navigator.of(context).popUntil((rota) => rota.isFirst);

  /// Depois do login ou do cadastro de cliente: casca do cliente, sem voltar às telas de acesso.
  static void irParaCliente(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CascaClienteTela()),
      (rota) => false,
    );
  }

  /// Depois do cadastro de profissional. O app completo do profissional (F6.1 e F6.2) ainda
  /// não existe: abre uma área provisória que dá acesso às telas já prontas.
  static void irParaProfissional(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AreaProfissionalProvisoria()),
      (rota) => false,
    );
  }

  /// Aba "Pedidos" da casca do cliente.
  static Widget abaPedidos() => Builder(
        builder: (context) => SeusPedidosTela(
          aoAbrirPedido: (pedido) => abrirPedido(context, pedido),
        ),
      );

  static void abrirPedido(BuildContext context, PedidoResumo pedido) {
    if (pedido.statusTexto.startsWith('Em execução')) {
      _abrir<void>(context, _pedidoEmExecucao());
    } else if (pedido.statusTexto.startsWith('Finalizado')) {
      abrirGarantia(context);
    } else {
      // Orçamentos recebidos (tela 12) e disputa em andamento ainda não têm tela.
      _abrir<void>(context, EmBreveTela(titulo: pedido.titulo));
    }
  }

  static void abrirGarantia(BuildContext context) => _abrir<void>(
        context,
        GarantiaTela(
          dados: dadosGarantiaExemplo,
          aoPedirRetrabalho: () => _abrir<void>(context, const EmBreveTela(titulo: 'Retrabalho')),
          aoVerContrato: () => _abrir<void>(context, const EmBreveTela(titulo: 'Contrato')),
        ),
      );

  static Widget _pedidoEmExecucao() => Builder(
        builder: (context) => PedidoExecucaoTela(
          aoTocarSos: () => _abrir<void>(context, const EmBreveTela(titulo: 'SOS')),
          aoConversar: () => _abrir<void>(context, const ChatPedidoTela()),
          aoVerConclusao: () => _abrir<void>(context, _conclusao(context)),
        ),
      );

  static Widget _conclusao(BuildContext context) => ConclusaoTela(
        aoConfirmar: () => _abrir<void>(
          context,
          AvaliacaoTela(
            aoEnviar: (_) => _voltarAoInicio(context),
            aoAvaliarDepois: () => _voltarAoInicio(context),
          ),
        ),
        aoRelatarProblema: () => _abrir<void>(
          context,
          RelatarProblemaTela(aoEnviar: (_) => _voltarAoInicio(context)),
        ),
      );
}
