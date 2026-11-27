import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show EspacoFoto, LinhaValor, formatarData, formatarReais;
import '../medidas/modelos.dart' show ProvaEscolhida;
import '../profissional_apoio/apoio.dart';
import 'contestacao_material.dart';
import 'nota_material.dart';

/// F5.9 (cliente): nota dos materiais enviada pelo profissional, item por item.
/// Só leitura. Se ainda não há nota, mostra o estado vazio.
class VerNotaTela extends StatelessWidget {
  const VerNotaTela({super.key, required this.servico, required this.pedidoId, this.escolherFoto});

  /// Tira a foto para anexar à contestação (nulo se a pessoa cancelar).
  final Future<ProvaEscolhida?> Function()? escolherFoto;

  final ServicoNotaMaterial servico;
  final String pedidoId;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<List<NotaMaterial>>(
      textoNaoEncontrado: TextosNaoEncontrado.pedido,
      titulo: 'Nota dos materiais',
      carregar: () => servico.carregarTodas(pedidoId),
      estaVazio: (notas) => notas.every((n) => n.itens.isEmpty),
      iconeVazio: Icons.receipt_long_outlined,
      tituloVazio: 'Nenhuma nota enviada',
      textoVazio: 'Quando o profissional enviar a notinha dos materiais, ela aparece aqui.',
      construir: (context, todas) {
        final notas = [
          for (final n in todas)
            if (n.itens.isNotEmpty) n
        ];
        final varias = notas.length > 1;
        final primeira = notas.first;
        return CorpoRolavel(
          children: [
            Text('Materiais do serviço', style: TipografiaTrato.tituloGrande),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              varias
                  ? '${primeira.pedidoTitulo} · ${primeira.profissional} · ${notas.length} notas'
                  : '${primeira.pedidoTitulo} · ${primeira.profissional} · '
                      'enviada em ${formatarData(primeira.enviadaEm)}',
              style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
            ),
            for (var k = 0; k < notas.length; k++) ..._nota(notas[k], k + 1, varias),
            if (varias) ...[
              const TituloSecao('Total dos materiais'),
              CartaoTrato(
                child: LinhaValor(
                  rotulo: 'Soma das ${notas.length} notas',
                  valor: formatarReais(notas.fold<int>(0, (s, n) => s + n.somaCentavos)),
                ),
              ),
            ],
            const SizedBox(height: EspacosTrato.x3),
            Text(
              'A nota serve para você conferir o custo de cada material.',
              style: TipografiaTrato.legenda,
            ),
            if (servico case final ServicoContestacaoMaterial contestacao)
              SecaoContestacaoMaterial(
                servico: contestacao,
                pedidoId: pedidoId,
                notas: notas,
                escolherFoto: escolherFoto,
              ),
          ],
        );
      },
    );
  }

  /// Uma nota: foto (se houver), itens e soma. Com mais de uma, cada uma ganha "Nota N".
  List<Widget> _nota(NotaMaterial n, int numero, bool varias) {
    return [
      if (varias) TituloSecao('Nota $numero · ${formatarData(n.enviadaEm)}'),
      if (n.fotoNota != null) ...[
        const TituloSecao('Foto da nota'),
        EspacoFoto(
          legenda: 'Nota enviada pelo profissional',
          referencia: n.fotoNota,
          altura: 160,
        ),
      ],
      TituloSecao(varias ? 'Itens da nota $numero' : 'Itens'),
      CartaoTrato(
        child: Column(
          children: [
            for (final i in n.itens)
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                child: LinhaValor(
                  rotulo: i.rotuloComConta(formatarReais),
                  valor: formatarReais(i.centavos),
                ),
              ),
            const Divider(),
            const SizedBox(height: EspacosTrato.x1),
            LinhaValor(rotulo: 'Soma dos itens', valor: formatarReais(n.somaCentavos)),
          ],
        ),
      ),
    ];
  }
}
