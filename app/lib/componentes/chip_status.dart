import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Família de cor do chip, seguindo o protótipo.
enum TipoStatus {
  /// "Em execução · pagamento acompanhado", "2 orçamentos recebidos".
  info(CoresTrato.azulSuave, CoresTrato.azulTexto),

  /// "Disputa aberta · em análise", aditivo aguardando.
  alerta(CoresTrato.ambarSuave, CoresTrato.ambarTexto),

  /// "Finalizado", "Garantia ativa".
  sucesso(CoresTrato.verdeSuave, CoresTrato.verdeTexto),

  /// SOS, erro.
  perigo(CoresTrato.vermelhoSuave, CoresTrato.vermelhoTexto),

  /// "3 orçamentos novos".
  destaque(CoresTrato.laranja, CoresTrato.petroleo);

  const TipoStatus(this.fundo, this.texto);

  final Color fundo;
  final Color texto;
}

class ChipStatus extends StatelessWidget {
  const ChipStatus({super.key, required this.texto, required this.tipo, this.icone});

  final String texto;
  final TipoStatus tipo;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final estilo = TipografiaTrato.corpoPequeno.copyWith(
      color: tipo.texto,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x2, vertical: EspacosTrato.x1),
      decoration: BoxDecoration(
        color: tipo.fundo,
        borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: EspacosTrato.x4, color: tipo.texto),
            const SizedBox(width: EspacosTrato.x1),
          ],
          Flexible(child: Text(texto, style: estilo)),
        ],
      ),
    );
  }
}
