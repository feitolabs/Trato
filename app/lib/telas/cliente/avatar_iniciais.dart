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
    this.permitirAmpliacao = true,
  });

  final String iniciais;
  final double tamanho;
  final String? fotoReferencia;
  final VoidCallback? aoTocar;
  final bool permitirAmpliacao;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final imagemReal = construirImagemReal(fotoReferencia);
    final circulo = Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      clipBehavior: imagemReal != null ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(color: c.azulSuave, shape: BoxShape.circle),
      child: imagemReal ??
          Text(
            iniciais,
            style:
                (tamanho >= 80 ? TipografiaTrato.tituloOpcao : TipografiaTrato.corpoForte).copyWith(
              color: c.azulTexto,
            ),
          ),
    );

    if (aoTocar == null) {
      if (permitirAmpliacao && imagemReal != null && fotoReferencia != null) {
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
                  color: c.petroleo,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.superficie, width: 2),
                ),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 14,
                  color: c.sobrePetroleo,
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
  const SeloVerificacao(this.texto, {super.key, this.conferidoEm});

  final String texto;

  /// Termos 10.2 (`selo_conferido_em`): nula não mostra a data.
  final DateTime? conferidoEm;

  static String _comData(String texto, DateTime? quando) {
    if (quando == null) return texto;
    final d = quando.toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '$texto\nConferido em ${dois(d.day)}/${dois(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield_outlined, size: EspacosTrato.x4, color: c.azulTexto),
        const SizedBox(width: EspacosTrato.x1),
        Flexible(
          child: Text(
            _comData(texto, conferidoEm),
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: c.azulTexto,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
            ),
          ),
        ),
      ],
    );
  }
}
