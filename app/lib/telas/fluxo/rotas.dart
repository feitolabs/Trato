import 'package:flutter/material.dart';

import '../cliente/casca_cliente_tela.dart';
import '../conclusao/avaliacao_tela.dart';
import '../conclusao/conclusao_tela.dart';
import '../conclusao/dados_exemplo.dart';
import '../conclusao/garantia_tela.dart';
import '../conclusao/relatar_problema_tela.dart';
import '../em_breve_tela.dart';
import '../orcamentos/detalhe_orcamento_tela.dart';
import '../orcamentos/orcamentos_recebidos_tela.dart';
import '../pagamento/pagamento_tela.dart';
import '../perfil_cliente/modelos.dart';
import '../perfil_cliente/perfil_cliente_tela.dart';
import '../pedidos/chat_pedido_tela.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedido_execucao_tela.dart';
import '../pedidos/seus_pedidos_tela.dart';
import '../profissional/calculadora_orcamento_tela.dart';
import '../profissional/check_in_tela.dart';
import '../profissional/servico_check_in_fake.dart';
import '../profissional/servico_orcamento_fake.dart';
import '../profissional_inicio/casca_profissional_tela.dart';

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

  /// Percentual só de demonstração: a taxa real é decidida pelo backend (P2).
  static const _taxaDemonstracaoBps = 750;

  /// Depois do cadastro de profissional (e em "Usar como profissional"): casca do profissional.
  /// Orçamento e check-in usam serviços de teste até a API entrar.
  static void irParaProfissional(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => _cascaProfissional()),
      (rota) => false,
    );
  }

  static Widget _cascaProfissional() => Builder(
        builder: (context) => CascaProfissionalTela(
          aoFazerCheckIn: () => _abrir<void>(
            context,
            CheckInTela(servico: ServicoCheckInFake(), tituloBarra: 'Mariana · hoje, 14h'),
          ),
          aoFazerOrcamento: () => _abrir<void>(
            context,
            CalculadoraOrcamentoTela(
              servico: ServicoOrcamentoFake(taxaBps: _taxaDemonstracaoBps),
              tituloPedido: 'Troca de tomadas e chuveiro',
            ),
          ),
        ),
      );

  /// Aba "Perfil" da casca do cliente.
  static Widget abaPerfil() => Builder(
        builder: (context) => PerfilClienteTela(
          aoTocarItem: (acao) => acao == AcaoPerfil.usarComoProfissional
              ? irParaProfissional(context)
              : _abrir<void>(context, EmBreveTela(titulo: acao.name)),
        ),
      );

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
    } else if (pedido.statusTexto.contains('orçamentos recebidos')) {
      _abrir<void>(context, _orcamentosRecebidos());
    } else {
      // Disputa em andamento ainda não tem tela.
      _abrir<void>(context, EmBreveTela(titulo: pedido.titulo));
    }
  }

  static Widget _orcamentosRecebidos() => Builder(
        builder: (context) => OrcamentosRecebidosTela(
          aoVerOrcamento: (orcamento) => _abrir<void>(
            context,
            // O protótipo só traz o detalhe de alguns orçamentos.
            orcamento.detalhe == null
                ? EmBreveTela(titulo: 'Orçamento de ${orcamento.profissional}')
                : DetalheOrcamentoTela(
                    orcamento: orcamento,
                    aoAceitar: (_) => _abrir<void>(
                      context,
                      PagamentoTela(aoPagar: (_) => _voltarAoInicio(context)),
                    ),
                  ),
          ),
        ),
      );

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
