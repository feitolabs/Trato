import 'package:flutter/material.dart';

import '../tema/tema.dart';

enum EstadoEtapa { feita, atual, futura }

class EtapaLinhaDoTempo {
  const EtapaLinhaDoTempo({required this.titulo, required this.detalhe, required this.estado});

  final String titulo;
  final String detalhe;
  final EstadoEtapa estado;
}

/// Linha do tempo do pedido (Contratado → A caminho → Chegou → Em execução → Finalizado).
class LinhaDoTempo extends StatelessWidget {
  const LinhaDoTempo({super.key, required this.etapas});

  final List<EtapaLinhaDoTempo> etapas;

  static const _tamanhoMarcador = 28.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < etapas.length; i++)
          _LinhaEtapa(etapa: etapas[i], ultima: i == etapas.length - 1),
      ],
    );
  }
}

class _LinhaEtapa extends StatelessWidget {
  const _LinhaEtapa({required this.etapa, required this.ultima});

  final EtapaLinhaDoTempo etapa;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final futura = etapa.estado == EstadoEtapa.futura;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: LinhaDoTempo._tamanhoMarcador,
            child: Column(
              children: [
                _Marcador(estado: etapa.estado),
                if (!ultima)
                  Expanded(
                    child: VerticalDivider(width: 2, thickness: 2, color: c.borda),
                  ),
              ],
            ),
          ),
          const SizedBox(width: EspacosTrato.x4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: ultima ? 0 : EspacosTrato.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etapa.titulo,
                    style: futura
                        ? TipografiaTrato.tituloCartao.copyWith(
                            color: c.textoSecundario,
                            fontWeight: FontWeight.w500,
                            fontVariations: const [FontVariation('wght', 500)],
                          )
                        : TipografiaTrato.tituloCartao.copyWith(color: c.texto),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    etapa.detalhe,
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: c.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Marcador extends StatelessWidget {
  const _Marcador({required this.estado});

  final EstadoEtapa estado;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final (fundo, borda) = switch (estado) {
      EstadoEtapa.feita => (c.petroleo, c.petroleo),
      EstadoEtapa.atual => (c.azulSuave, c.azulTexto),
      EstadoEtapa.futura => (c.superficie, c.textoSecundario),
    };
    return Container(
      width: LinhaDoTempo._tamanhoMarcador,
      height: LinhaDoTempo._tamanhoMarcador,
      decoration: BoxDecoration(
        color: fundo,
        shape: BoxShape.circle,
        border: Border.all(color: borda, width: 2),
      ),
      child: estado == EstadoEtapa.feita
          ? Icon(Icons.check, size: EspacosTrato.x4, color: c.sobrePetroleo)
          : null,
    );
  }
}
