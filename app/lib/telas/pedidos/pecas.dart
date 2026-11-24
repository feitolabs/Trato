import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'modelos.dart';

/// Espaço de foto do protótipo: bloco azul-claro com o rótulo embaixo à esquerda ou imagem real.
class EspacoFoto extends StatelessWidget {
  const EspacoFoto({
    super.key,
    required this.rotulo,
    this.largura,
    this.altura = 96,
    this.referencia,
  });

  final String rotulo;
  final double? largura;
  final double altura;
  final String? referencia;

  @override
  Widget build(BuildContext context) {
    final ref = referencia ?? rotulo;
    final imagemReal = construirImagemReal(ref);
    final textoExibido = rotuloAmigavelFoto(rotulo);
    return ToquePreviewImagem(
      referencia: ref,
      legenda: textoExibido,
      child: Container(
        width: largura,
        height: altura,
        clipBehavior: imagemReal != null ? Clip.antiAlias : Clip.none,
        padding: imagemReal != null ? EdgeInsets.zero : const EdgeInsets.all(EspacosTrato.x2),
        alignment: Alignment.bottomLeft,
        decoration: BoxDecoration(
          color: context.cores.azulSuave,
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
        ),
        child: imagemReal != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  imagemReal,
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CoresTrato.overlayFoto,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.zoom_in, size: 16, color: CoresTrato.textoSobreFoto),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: double.infinity,
                      color: CoresTrato.overlayFoto,
                      padding: const EdgeInsets.symmetric(
                        horizontal: EspacosTrato.x2,
                        vertical: EspacosTrato.x1,
                      ),
                      child: Text(
                        textoExibido,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: context.cores.sobrePetroleo,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                textoExibido,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TipografiaTrato.corpoPequeno.copyWith(fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

/// Botão SOS (pílula vermelha). A ação real (acionar ajuda) é da F5.13.
class BotaoSos extends StatelessWidget {
  const BotaoSos({super.key, required this.aoTocar});

  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cores.vermelhoSuave,
      shape: StadiumBorder(side: BorderSide(color: context.cores.vermelhoTexto, width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspacosTrato.x5,
            vertical: EspacosTrato.x3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: context.cores.vermelhoTexto),
              const SizedBox(width: EspacosTrato.x2),
              Text(
                'SOS',
                style: TipografiaTrato.corpoForte.copyWith(color: context.cores.vermelhoTexto),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão âmbar do aditivo. Aguardando: mostra Recusar / Aprovar aditivo.
/// Decidido: mostra só o resultado (a decisão final e o valor são do backend).
class CartaoAditivo extends StatelessWidget {
  const CartaoAditivo({
    super.key,
    required this.aditivo,
    required this.aoRecusar,
    required this.aoAprovar,
  });

  final Aditivo aditivo;
  final VoidCallback aoRecusar;
  final VoidCallback aoAprovar;

  @override
  Widget build(BuildContext context) {
    final aguardando = aditivo.estado == EstadoAditivo.aguardando;
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: BoxDecoration(
        color: context.cores.ambarSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: context.cores.ambarTexto),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: Text(
                  aguardando ? 'Aditivo aguardando sua resposta' : 'Aditivo',
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: context.cores.ambarTexto,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${aditivo.titulo} · ${formatarReais(aditivo.valorCentavos)}',
                      style: TipografiaTrato.tituloCartao,
                    ),
                    const SizedBox(height: EspacosTrato.x2),
                    Text(
                      aditivo.descricao,
                      style: TipografiaTrato.corpoPequeno.copyWith(
                        color: context.cores.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          if (aguardando) ...[
            Text(
              'Sem a sua aprovação, o profissional não pode cobrar a diferença.',
              style: TipografiaTrato.corpoPequeno,
            ),
            const SizedBox(height: EspacosTrato.x4),
            Row(
              children: [
                Expanded(child: BotaoSecundario(texto: 'Recusar', aoTocar: aoRecusar)),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(child: BotaoPrimario(texto: 'Aprovar aditivo', aoTocar: aoAprovar)),
              ],
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: ChipStatus(
                texto: aditivo.estado == EstadoAditivo.aprovado
                    ? 'Aditivo aprovado'
                    : 'Aditivo recusado',
                tipo: aditivo.estado == EstadoAditivo.aprovado
                    ? TipoStatus.sucesso
                    : TipoStatus.perigo,
              ),
            ),
        ],
      ),
    );
  }
}
