import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import 'modelos.dart';

/// "Inclui:" e "Não inclui:" de um orçamento, lado a lado. Mesmo rótulo e mesma ordem no
/// comparador e no detalhe. Só leitura do que a API já devolveu: nenhum valor é calculado.
class IncluiNaoInclui extends StatelessWidget {
  const IncluiNaoInclui({super.key, required this.detalhe});

  final DetalheOrcamento? detalhe;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Coluna(
            chave: const Key('orcamento-inclui'),
            rotulo: 'Inclui:',
            valor: textoInclui(detalhe),
          ),
        ),
        const SizedBox(width: EspacosTrato.x3),
        Expanded(
          child: _Coluna(
            chave: const Key('orcamento-nao-inclui'),
            rotulo: 'Não inclui:',
            valor: textoNaoInclui(detalhe),
          ),
        ),
      ],
    );
  }
}

class _Coluna extends StatelessWidget {
  const _Coluna({required this.chave, required this.rotulo, required this.valor});

  final Key chave;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: chave,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x1),
        Text(valor, style: TipografiaTrato.corpoForte),
      ],
    );
  }
}
