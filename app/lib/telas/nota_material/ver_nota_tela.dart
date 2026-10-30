import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show EspacoFoto, LinhaValor, formatarData, formatarReais;
import '../profissional_apoio/apoio.dart';
import 'nota_material.dart';

/// F5.9 (cliente): nota dos materiais enviada pelo profissional, item por item.
/// Só leitura. Se ainda não há nota, mostra o estado vazio.
class VerNotaTela extends StatelessWidget {
  const VerNotaTela({super.key, required this.servico, required this.pedidoId});

  final ServicoNotaMaterial servico;
  final String pedidoId;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<NotaMaterial?>(
      titulo: 'Nota dos materiais',
      carregar: () => servico.carregar(pedidoId),
      estaVazio: (n) => n == null || n.itens.isEmpty,
      iconeVazio: Icons.receipt_long_outlined,
      tituloVazio: 'Nenhuma nota enviada',
      textoVazio: 'Quando o profissional enviar a notinha dos materiais, ela aparece aqui.',
      construir: (context, nota) {
        final n = nota!;
        return CorpoRolavel(
          children: [
            Text('Materiais do serviço', style: TipografiaTrato.tituloGrande),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              '${n.pedidoTitulo} · ${n.profissional} · enviada em ${formatarData(n.enviadaEm)}',
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            ),
            if (n.fotoNota != null) ...[
              const TituloSecao('Foto da nota'),
              const EspacoFoto(legenda: 'Nota enviada pelo profissional', altura: 160),
            ],
            const TituloSecao('Itens'),
            CartaoTrato(
              child: Column(
                children: [
                  for (final i in n.itens)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                      child: LinhaValor(rotulo: i.descricao, valor: formatarReais(i.centavos)),
                    ),
                  const Divider(),
                  const SizedBox(height: EspacosTrato.x1),
                  LinhaValor(rotulo: 'Soma dos itens', valor: formatarReais(n.somaCentavos)),
                ],
              ),
            ),
            const SizedBox(height: EspacosTrato.x3),
            Text(
              'A nota serve para você conferir o custo de cada material.',
              style: TipografiaTrato.legenda,
            ),
          ],
        );
      },
    );
  }
}
