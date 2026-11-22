import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'etiquetas_elogio.dart';
import 'modelos.dart';

String _iniciaisCliente(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first[0].toUpperCase();
  return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
}

/// Card de avaliação compartilhado entre o perfil público do profissional (visão cliente)
/// e a lista "Avaliações recebidas" (visão profissional).
class CartaoAvaliacaoVisual extends StatelessWidget {
  const CartaoAvaliacaoVisual({
    super.key,
    required this.avaliacao,
    this.rotuloResposta = 'Resposta do profissional',
    this.aoResponder,
  });

  final Avaliacao avaliacao;
  final String rotuloResposta;
  final VoidCallback? aoResponder;

  @override
  Widget build(BuildContext context) {
    final a = avaliacao;
    final comentarioLimpo = a.comentario.trim();
    final respostaLimpa = (a.resposta ?? '').trim();
    final itensCriterios = a.itensCriterios;
    final detalhesLimpo = a.detalhes.trim();
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);

    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.cores.azulSuave,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.cores.borda),
                ),
                child: Text(
                  _iniciaisCliente(a.cliente),
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: context.cores.petroleo,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.cliente,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TipografiaTrato.corpoForte,
                    ),
                    if (a.servico.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        a.servico.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: secundario,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: EspacosTrato.x2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: EspacosTrato.x2 + 2,
                  vertical: EspacosTrato.x1,
                ),
                decoration: BoxDecoration(
                  color: context.cores.sobrePetroleo,
                  borderRadius: BorderRadius.circular(EspacosTrato.raio),
                  border: Border.all(color: context.cores.borda),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 16, color: context.cores.petroleo),
                    const SizedBox(width: 4),
                    Text(
                      formatarNota(a.nota),
                      style: TipografiaTrato.corpoPequeno.copyWith(
                        color: context.cores.petroleo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (itensCriterios.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x3),
            Wrap(
              spacing: EspacosTrato.x2,
              runSpacing: EspacosTrato.x1 + 2,
              children: [
                for (final item in itensCriterios)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: EspacosTrato.x2,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.cores.sobrePetroleo,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.cores.borda),
                    ),
                    child: Text(
                      '${item.rotulo} ${item.nota}',
                      style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
                    ),
                  ),
              ],
            ),
          ] else if (detalhesLimpo.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              detalhesLimpo,
              style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
            ),
          ],
          if (comentarioLimpo.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x3),
            Text(comentarioLimpo, style: TipografiaTrato.corpo),
          ],
          EtiquetasDaAvaliacao(etiquetas: a.etiquetas),
          if (respostaLimpa.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(EspacosTrato.x3),
              decoration: BoxDecoration(
                color: context.cores.sobrePetroleo,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.cores.borda),
              ),
              child: Text(
                '$rotuloResposta: $respostaLimpa',
                style: TipografiaTrato.corpoPequeno,
              ),
            ),
          ] else if (aoResponder != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('responder-avaliacao-${a.id ?? ''}'),
                onPressed: aoResponder,
                child: const Text('Responder'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
