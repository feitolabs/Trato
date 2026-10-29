import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'modelos.dart';
import 'pecas_profissional.dart';

/// Folha "Recusar pedido": pede o motivo (obrigatório) e devolve o escolhido,
/// ou null se o profissional desistir.
Future<MotivoRecusa?> pedirMotivoRecusa(BuildContext context) {
  return showModalBottomSheet<MotivoRecusa>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: CoresTrato.creme,
    builder: (_) => const _FolhaRecusa(),
  );
}

class _FolhaRecusa extends StatefulWidget {
  const _FolhaRecusa();

  @override
  State<_FolhaRecusa> createState() => _FolhaRecusaState();
}

class _FolhaRecusaState extends State<_FolhaRecusa> {
  MotivoRecusa? _motivo;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ConteudoResponsivo(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Recusar pedido', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'Por que você não vai orçar? O cliente não vê o motivo.',
                style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x4),
              for (final motivo in MotivoRecusa.values) ...[
                OpcaoUnica(
                  texto: motivo.texto,
                  selecionada: motivo == _motivo,
                  aoTocar: () => setState(() => _motivo = motivo),
                ),
                const SizedBox(height: EspacosTrato.x2),
              ],
              const SizedBox(height: EspacosTrato.x3),
              BotaoPrimario(
                texto: 'Confirmar recusa',
                aoTocar: _motivo == null ? null : () => Navigator.of(context).pop(_motivo),
              ),
              const SizedBox(height: EspacosTrato.x1),
              BotaoLink(texto: 'Voltar', aoTocar: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}
