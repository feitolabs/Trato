import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../cliente/modelos.dart';
import '../cliente/perfil_profissional_tela.dart' show CartaoAvaliacao;
import '../comuns/estados.dart';

/// Todas as avaliações que um profissional recebeu (a partir do perfil público).
class AvaliacoesProfissionalTela extends StatelessWidget {
  const AvaliacoesProfissionalTela({super.key, required this.profissional});

  final Profissional profissional;

  @override
  Widget build(BuildContext context) {
    final lista = profissional.detalhe?.avaliacoes ?? const <Avaliacao>[];
    return MolduraTelaComum(
      titulo: 'Avaliações de ${profissional.primeiroNome}',
      child: lista.isEmpty
          ? const EstadoVazio(
              icone: Icons.star_border,
              titulo: 'Ainda sem avaliações',
              texto: 'As avaliações aparecem aqui depois dos primeiros serviços.',
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (_, i) => CartaoAvaliacao(avaliacao: lista[i]),
            ),
    );
  }
}
