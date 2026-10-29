import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../profissional_apoio/apoio.dart';
import 'perfil_publico.dart';
import 'perfil_publico_tela.dart' show CartaoAvaliacao;

/// Lista das avaliações que o profissional recebeu. Só leitura.
class AvaliacoesRecebidasTela extends StatelessWidget {
  const AvaliacoesRecebidasTela({super.key, required this.servico});

  final ServicoPerfilPublico servico;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<List<Avaliacao>>(
      titulo: 'Avaliações recebidas',
      carregar: servico.carregarAvaliacoes,
      estaVazio: (l) => l.isEmpty,
      iconeVazio: Icons.star_border,
      tituloVazio: 'Nenhuma avaliação ainda',
      textoVazio: 'Depois do primeiro serviço concluído, as avaliações dos clientes aparecem aqui.',
      construir: (context, lista) => CorpoRolavel(
        children: [
          Text('${lista.length} ${lista.length == 1 ? 'avaliação' : 'avaliações'}',
              style: TipografiaTrato.tituloGrande),
          const SizedBox(height: EspacosTrato.x4),
          for (final a in lista) CartaoAvaliacao(avaliacao: a),
        ],
      ),
    );
  }
}
