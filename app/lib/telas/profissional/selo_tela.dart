// Termos 10.3: o aviso do selo, com o motivo e como contestar escritos pelo servidor.
import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/repositorios.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';

class SeloTela extends StatelessWidget {
  const SeloTela({super.key, required this.carregar, required this.aoFalar});

  /// Os avisos da pessoa, do mais novo para o mais antigo.
  final Future<List<Notificacao>> Function() carregar;
  final void Function(BuildContext context) aoFalar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpo.copyWith(color: c.texto);
    return MolduraTelaComum(
      titulo: 'Selo de verificação',
      child: CarregadorTela<List<Notificacao>>(
        carregar: carregar,
        construir: (context, avisos, _) {
          final aviso = avisos.where((n) => (n.tipo ?? '').startsWith('conta.selo_')).firstOrNull;
          return ListView(
            children: [
              if (aviso == null)
                Text(
                  'Não encontramos um aviso sobre o seu selo. Para saber o motivo ou '
                  'contestar, fale com o Trato.',
                  style: corpo,
                )
              else ...[
                Text(aviso.titulo, style: TipografiaTrato.titulo),
                const SizedBox(height: EspacosTrato.x3),
                Text(aviso.texto, style: corpo),
                const SizedBox(height: EspacosTrato.x2),
                Text(aviso.quando, style: TipografiaTrato.corpoPequeno),
              ],
              const SizedBox(height: EspacosTrato.x5),
              BotaoSecundario(
                key: const ValueKey('selo-falar'),
                texto: 'Falar com o Trato',
                aoTocar: () => aoFalar(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
