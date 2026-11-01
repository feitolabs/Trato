import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import 'modelos.dart';

/// "R$ 200" (sem centavos quando redondo) ou "R$ 12,50". Só formata.
String reaisCurto(int centavos) {
  final reais = centavos ~/ 100;
  final cents = centavos % 100;
  final inteiro = reais.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
  return cents == 0 ? 'R\$ $inteiro' : 'R\$ $inteiro,${cents.toString().padLeft(2, '0')}';
}

/// "R$ 200 a R$ 500" ou "Sem faixa".
String textoFaixa(PedidoAberto p) =>
    p.temFaixa ? '${reaisCurto(p.faixaMinCentavos!)} a ${reaisCurto(p.faixaMaxCentavos!)}' : 'Sem faixa';

/// "2,1 km".
String textoDistancia(double? km) =>
    km == null ? 'distância indisponível' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

/// "3 de 5 orçaram", "1 de 5 orçou", "Ninguém orçou".
String textoOrcamentos(PedidoAberto p) {
  final orcaram = p.orcaram;
  if (orcaram == null || p.limiteOrcamentos == null) return '';
  if (orcaram == 0) return 'Ninguém orçou';
  return '$orcaram de ${p.limiteOrcamentos} ${orcaram == 1 ? 'orçou' : 'orçaram'}';
}

/// Opção em cartão com marca de seleção única (motivos de recusa).
class OpcaoUnica extends StatelessWidget {
  const OpcaoUnica({
    super.key,
    required this.texto,
    required this.selecionada,
    required this.aoTocar,
  });

  final String texto;
  final bool selecionada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raio);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selecionada,
      child: Material(
        color: selecionada ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: selecionada ? CoresTrato.petroleo : CoresTrato.borda,
            width: selecionada ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          onTap: aoTocar,
          borderRadius: raio,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              children: [
                Icon(
                  selecionada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: CoresTrato.petroleo,
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(child: Text(texto, style: TipografiaTrato.corpo)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
