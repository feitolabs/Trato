import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../tema/tema.dart';

/// Termos 20.6: só estas medidas cancelam pedidos futuros, quando entram em vigor.
bool medidaCancelaPedidos(String tipo) => tipo == 'suspensao' || tipo == 'encerramento';

const kPedidosCancelados = 'Quando a suspensão ou o encerramento entra em vigor, os pedidos futuros são cancelados '
    'automaticamente, sem custo de cancelamento e com reembolso integral do valor retido, e as séries recorrentes '
    'são pausadas. Pedidos em andamento e futuros que ficarem pendentes exigem conferência manual (Termos 20.6). '
    'Não há reagendamento: reverter a medida não restaura pedidos nem retoma séries.';

const kReverterNaoRestauraPedidos = 'Reverter não restaura pedidos cancelados nem retoma séries recorrentes.';

const kResumoNaoInformado = 'O servidor não informou o resumo dos pedidos. Confira os pedidos desta conta manualmente '
    '(Termos 20.6).';

const avisoPedidosCancelados = BannerInfo(kPedidosCancelados, titulo: 'Pedidos desta conta.', tom: Tom.alerta);

/// Mostra o que o servidor informou. [resumo] nulo = campos ausentes na resposta.
class ResumoDosPedidos extends StatelessWidget {
  const ResumoDosPedidos(this.resumo, {super.key});
  final ResumoPedidos? resumo;

  @override
  Widget build(BuildContext context) {
    final r = resumo;
    if (r == null) return const BannerInfo(kResumoNaoInformado, tom: Tom.alerta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Linha('Futuros cancelados', '${r.futurosCancelados}'),
        Linha('Em andamento', '${r.emAndamento}'),
        ..._codigos('Em andamento: conferir manualmente', r.emAndamentoIds),
        Linha('Futuros pendentes', '${r.futurosPendentesIds.length}'),
        ..._codigos('Futuros não cancelados: conferir manualmente', r.futurosPendentesIds),
      ],
    );
  }

  List<Widget> _codigos(String titulo, List<String> ids) => [
        if (ids.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text(titulo, style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x1),
          SelectableText(ids.join('\n'), style: TipografiaTrato.corpo),
          const SizedBox(height: EspacosTrato.x2),
        ],
      ];
}

/// Resultado logo após suspender, encerrar ou bloquear. Só informa.
Future<void> mostrarResumoDosPedidos(BuildContext context, ResumoPedidos? resumo) => mostrarModal<void>(
      context,
      construir: (ctx) => CorpoModal(
        titulo: 'Pedidos desta conta',
        consequencia: 'Reverter a medida não restaura pedidos nem retoma séries. Não há reagendamento.',
        filhos: [ResumoDosPedidos(resumo)],
        acoes: [BotaoTrato.primario('Fechar', aoPressionar: () => Navigator.of(ctx).pop())],
      ),
    );
