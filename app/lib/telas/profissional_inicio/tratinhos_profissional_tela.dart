/// Saldo e validade dos Tratinhos da carteira do profissional (Termos 13.3/13.4).
/// Só mostra o que o servidor manda; em API antiga sem lista, orienta a ver o aviso.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/desconto_moedas.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

class TratinhosProfissionalTela extends StatelessWidget {
  const TratinhosProfissionalTela({super.key, required this.resumo});

  final ResumoExclusividades resumo;

  @override
  Widget build(BuildContext context) {
    final corpo = TipografiaTrato.corpo.copyWith(color: context.cores.texto);
    return MolduraTelaComum(
      titulo: 'Seus Tratinhos de profissional',
      child: ListView(
        children: [
          CartaoTrato(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    textoTratinhos(resumo.saldoProfissional),
                    style: TipografiaTrato.tituloGrande.copyWith(color: context.cores.texto),
                  ),
                  const SizedBox(height: EspacosTrato.x2),
                  if (resumo.creditosProfissional.isNotEmpty) ...[
                    Text('Validade do seu saldo', style: TipografiaTrato.corpoForte),
                    const SizedBox(height: EspacosTrato.x1),
                    for (final c in resumo.creditosProfissional)
                      Text(
                        textoValidadeCreditoProfissional(c),
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: context.cores.textoSecundario),
                      ),
                  ] else
                    Text(
                      'A data de vencimento está no texto do aviso que você recebeu.',
                      style: corpo,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
