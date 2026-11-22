import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional/dinheiro.dart';
import '../profissional_apoio/apoio.dart';
import 'modelos.dart';
import 'regra_liberacao.dart';

/// Valores de um pedido para o profissional: o valor inteiro que o cliente pagou, a taxa do
/// Trato descontada e o que fica para ele. Também lista aditivos e notas de materiais.
/// Nada é calculado aqui: tudo vem pronto do backend.
class DetalheValoresTela extends StatelessWidget {
  const DetalheValoresTela({super.key, required this.carregar, this.aoAvaliarCliente});

  final Future<DetalheValoresPedido> Function() carregar;

  /// Abre a avaliação do cliente (o botão só aparece em pedido concluído e ainda não avaliado).
  final VoidCallback? aoAvaliarCliente;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<DetalheValoresPedido>(
      titulo: 'Valores do pedido',
      carregar: carregar,
      estaVazio: (_) => false,
      iconeVazio: Icons.receipt_long_outlined,
      tituloVazio: '',
      textoVazio: '',
      construir: (context, d) {
        final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
        return CorpoRolavel(
          children: [
            Text('Pedido ${d.pedidoNumero}', style: TipografiaTrato.tituloGrande),
            const SizedBox(height: EspacosTrato.x2),
            Text(d.situacao, style: secundario),
            const SizedBox(height: EspacosTrato.x1),
            RegraLiberacao(libera: d.liberaEm, chave: const ValueKey('regra-liberacao')),
            const SizedBox(height: EspacosTrato.x4),
            CartaoTrato(
              key: const ValueKey('valores-do-pedido'),
              child: Column(
                children: [
                  _Linha('Valor pago pelo cliente', Dinheiro.formatar(d.pagoPeloClienteCentavos)),
                  const Divider(),
                  _Linha('Você recebe', Dinheiro.formatar(d.voceRecebeCentavos), forte: true),
                ],
              ),
            ),
            const SizedBox(height: EspacosTrato.x5),
            Text('Aditivos', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x2),
            if (d.aditivos.isEmpty)
              Text('Nenhum aditivo neste pedido.', style: secundario)
            else
              CartaoTrato(
                key: const ValueKey('aditivos-do-pedido'),
                child: Column(
                  children: [
                    for (final a in d.aditivos)
                      _Linha(a.rotulo, Dinheiro.formatar(a.centavos), nota: a.nota),
                  ],
                ),
              ),
            const SizedBox(height: EspacosTrato.x5),
            Text('Notas de materiais', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x2),
            if (d.notas.isEmpty)
              Text('Nenhuma nota enviada.', style: secundario)
            else ...[
              CartaoTrato(
                key: const ValueKey('notas-do-pedido'),
                child: Column(
                  children: [
                    for (final n in d.notas) _Linha(n.rotulo, Dinheiro.formatar(n.centavos)),
                  ],
                ),
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'As notas são só o registro do custo dos materiais: não geram cobrança nem '
                'pagamento. Para cobrar um valor a mais, use um aditivo.',
                style: secundario,
              ),
            ],
            if (d.podeAvaliarCliente && aoAvaliarCliente != null) ...[
              const SizedBox(height: EspacosTrato.x5),
              BotaoSecundario(
                texto: 'Avaliar o cliente',
                icone: Icons.star_outline,
                aoTocar: aoAvaliarCliente,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor, {this.nota, this.forte = false});

  final String rotulo;
  final String valor;
  final String? nota;
  final bool forte;

  @override
  Widget build(BuildContext context) {
    final estilo = forte ? TipografiaTrato.tituloCartao : TipografiaTrato.corpo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(rotulo, style: estilo)),
              const SizedBox(width: EspacosTrato.x3),
              Text(valor, style: estilo),
            ],
          ),
          if (nota != null)
            Text(
              nota!,
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
        ],
      ),
    );
  }
}
