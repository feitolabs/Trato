import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import 'modelos.dart';

/// Elogios em tags: lista fechada do backend (mesmos textos exatos). O app só escolhe e mostra.
const etiquetasDeElogio = [
  'Pontual',
  'Limpo',
  'Explicou bem',
  'Preço justo',
  'Educado',
  'Caprichoso',
];

/// Máximo de elogios por avaliação (regra do backend; a tela só impede o 4º toque).
const maxEtiquetasPorAvaliacao = 3;

/// Etiquetas de UMA avaliação, em chips pequenos. Vazio = nada na tela.
class EtiquetasDaAvaliacao extends StatelessWidget {
  const EtiquetasDaAvaliacao({super.key, required this.etiquetas});

  final List<String> etiquetas;

  @override
  Widget build(BuildContext context) {
    if (etiquetas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x1,
        children: [for (final e in etiquetas) _ChipElogio(texto: e)],
      ),
    );
  }
}

/// Elogios mais recebidos no perfil ("Pontual · 12"), vindos de `etiquetas_top`.
/// Vazio ou ausente = nada na tela.
class EtiquetasMaisElogiadas extends StatelessWidget {
  const EtiquetasMaisElogiadas({super.key, required this.etiquetas});

  final List<EtiquetaTop> etiquetas;

  @override
  Widget build(BuildContext context) {
    if (etiquetas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mais elogiado por',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Wrap(
            key: const Key('etiquetas-top'),
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [for (final e in etiquetas) _ChipElogio(texto: '${e.etiqueta} · ${e.total}')],
          ),
        ],
      ),
    );
  }
}

/// Selo de resposta real: o texto é fixo; a API só diz se vale. Sem valor, nada aparece.
class SeloRespostaReal extends StatelessWidget {
  const SeloRespostaReal({super.key, required this.faixa});

  final String? faixa;

  @override
  Widget build(BuildContext context) {
    if ((faixa ?? '').trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x3),
      child: Row(
        key: const Key('selo-resposta-real'),
        children: [
          const Icon(Icons.schedule, size: EspacosTrato.x4, color: CoresTrato.petroleo),
          const SizedBox(width: EspacosTrato.x2),
          Flexible(
            child: Text(
              'Costuma responder no mesmo dia',
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.petroleo),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipElogio extends StatelessWidget {
  const _ChipElogio({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3, vertical: EspacosTrato.x1),
      decoration: BoxDecoration(
        color: CoresTrato.azulSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
      ),
      child: Text(texto, style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.petroleo)),
    );
  }
}
