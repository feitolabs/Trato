import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import 'modelos.dart';

/// "Inclui:" e "Não inclui:" de um orçamento, lado a lado. Mesmo rótulo e mesma ordem no
/// comparador e no detalhe. Só leitura do que a API já devolveu: nenhum valor é calculado.
class IncluiNaoInclui extends StatelessWidget {
  const IncluiNaoInclui({super.key, required this.detalhe, this.maxLinhasNaoInclui});

  final DetalheOrcamento? detalhe;

  /// Limite de linhas do "Não inclui:" (reticências); nulo = texto completo (detalhe).
  final int? maxLinhasNaoInclui;

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
            maxLinhas: maxLinhasNaoInclui,
          ),
        ),
      ],
    );
  }
}

class _Coluna extends StatelessWidget {
  const _Coluna({
    required this.chave,
    required this.rotulo,
    required this.valor,
    this.maxLinhas,
  });

  final Key chave;
  final String rotulo;
  final String valor;
  final int? maxLinhas;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: chave,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          valor,
          maxLines: maxLinhas,
          overflow: maxLinhas == null ? null : TextOverflow.ellipsis,
          style: TipografiaTrato.corpoForte,
        ),
      ],
    );
  }
}
