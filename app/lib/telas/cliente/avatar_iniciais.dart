import 'package:flutter/material.dart';

import '../../componentes/imagem_trato.dart';
import '../../tema/tema.dart';

/// Círculo azul-claro com as iniciais ou foto de perfil, com opção de troca/visualização.
class AvatarIniciais extends StatelessWidget {
  const AvatarIniciais({
    super.key,
    required this.iniciais,
    this.tamanho = 56,
    this.fotoReferencia,
    this.aoTocar,
  });

  final String iniciais;
  final double tamanho;
  final String? fotoReferencia;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final imagemReal = construirImagemReal(fotoReferencia);
    final circulo = Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      clipBehavior: imagemReal != null ? Clip.antiAlias : Clip.none,
      decoration: const BoxDecoration(color: CoresTrato.azulClaro, shape: BoxShape.circle),
      child: imagemReal ??
          Text(
            iniciais,
            style:
                (tamanho >= 80 ? TipografiaTrato.tituloOpcao : TipografiaTrato.corpoForte).copyWith(
              color: CoresTrato.petroleo,
            ),
          ),
    );

    if (aoTocar == null) {
      if (imagemReal != null && fotoReferencia != null) {
        return ToquePreviewImagem(
          referencia: fotoReferencia!,
          legenda: 'Foto de perfil',
          child: circulo,
        );
      }
      return circulo;
    }

    return Semantics(
      button: true,
      label: 'Trocar foto de perfil',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: aoTocar,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            circulo,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: CoresTrato.petroleo,
                  shape: BoxShape.circle,
                  border: Border.all(color: CoresTrato.superficie, width: 2),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  size: 14,
                  color: CoresTrato.creme,
                ),
              ),
            ),
          ],
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
