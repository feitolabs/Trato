/// Termos 3.7: o que não pode ser pedido nem oferecido. O texto é o do documento, sem lista
/// própria do app. Qual categoria informa exigência de habilitação depende do servidor.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

const servicosNaoCobertos = <String>[
  'Serviços fora do catálogo do aplicativo.',
  'Serviços ilegais ou que exponham alguém a risco grave.',
  'Serviços que exijam habilitação, registro ou responsabilidade técnica (por exemplo, obra '
      'estrutural, instalação de gás ou elétrica de maior porte), salvo em categoria que informe '
      'essa exigência e conferida pelo Trato.',
  'Serviços a serem prestados fora do imóvel informado no Pedido ou em local diferente do '
      'endereço cadastrado.',
];

/// Cartão fechado por padrão: o resumo fica sempre à vista e o toque abre a lista.
class CartaoServicosNaoCobertos extends StatelessWidget {
  const CartaoServicosNaoCobertos({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpoPequeno.copyWith(color: c.texto);
    return CartaoTrato(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('servicos-nao-cobertos'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text('Serviços não cobertos', style: TipografiaTrato.corpoForte),
          subtitle: Text(
            'Inclui os que exigem habilitação ou registro. Toque para ver.',
            style: corpo,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Não podem ser pedidos nem oferecidos pelo Trato:', style: corpo),
            ),
            for (final item in servicosNaoCobertos)
              Padding(
                padding: const EdgeInsets.only(top: EspacosTrato.x2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: corpo),
                    Expanded(child: Text(item, style: corpo)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
