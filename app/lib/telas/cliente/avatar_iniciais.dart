import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Círculo azul-claro com as iniciais, no lugar da foto do profissional.
class AvatarIniciais extends StatelessWidget {
  const AvatarIniciais({super.key, required this.iniciais, this.tamanho = 56});

  final String iniciais;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: CoresTrato.azulClaro, shape: BoxShape.circle),
      child: Text(
        iniciais,
        style: (tamanho >= 80 ? TipografiaTrato.tituloOpcao : TipografiaTrato.corpoForte).copyWith(
          color: CoresTrato.petroleo,
        ),
      ),
    );
  }
}

/// Linha "escudo + Verificado Plus" do protótipo.
class SeloVerificacao extends StatelessWidget {
  const SeloVerificacao(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.shield_outlined, size: EspacosTrato.x4, color: CoresTrato.azulTexto),
        const SizedBox(width: EspacosTrato.x1),
        Flexible(
          child: Text(
            texto,
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: CoresTrato.azulTexto,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
            ),
          ),
        ),
      ],
    );
  }
}
