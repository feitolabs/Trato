import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'modelos.dart';

/// Espaço de foto do protótipo: bloco azul-claro com o rótulo embaixo à esquerda.
class EspacoFoto extends StatelessWidget {
  const EspacoFoto({super.key, required this.rotulo, this.largura, this.altura = 96});

  final String rotulo;
  final double? largura;
  final double altura;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largura,
      height: altura,
      padding: const EdgeInsets.all(EspacosTrato.x2),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        color: CoresTrato.azulClaro,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Text(
        rotulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TipografiaTrato.corpoPequeno.copyWith(fontWeight: FontWeight.w600),
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
      color: CoresTrato.vermelhoSuave,
      shape: const StadiumBorder(side: BorderSide(color: CoresTrato.vermelhoTexto, width: 1.5)),
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
              const Icon(Icons.warning_amber_rounded, size: 20, color: CoresTrato.vermelhoTexto),
              const SizedBox(width: EspacosTrato.x2),
              Text(
                'SOS',
                style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.vermelhoTexto),
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
        color: CoresTrato.ambarSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: CoresTrato.ambarTexto),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: Text(
                  aguardando ? 'Aditivo aguardando sua resposta' : 'Aditivo',
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: CoresTrato.ambarTexto,
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
              const EspacoFoto(rotulo: '[Foto]', largura: 80, altura: 80),
              const SizedBox(width: EspacosTrato.x3),
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
                        color: CoresTrato.textoSecundario,
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
