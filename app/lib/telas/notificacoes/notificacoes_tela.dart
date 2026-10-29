import 'package:flutter/material.dart';

import '../../dados/repositorios.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

/// Lista simples de avisos do app. Só exibe o que o backend mandou; não decide nada.
class NotificacoesTela extends StatelessWidget {
  const NotificacoesTela({super.key, required this.notificacoes});

  final List<Notificacao> notificacoes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: ListView(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
            children: [
              Text('Notificações', style: TipografiaTrato.tituloGrande),
              const SizedBox(height: EspacosTrato.x4),
              for (final n in notificacoes) ...[
                CartaoTrato(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!n.lida) ...[
                            Semantics(
                              label: 'Não lida',
                              child: const Icon(Icons.circle, size: 10, color: CoresTrato.petroleo),
                            ),
                            const SizedBox(width: EspacosTrato.x2),
                          ],
                          Expanded(child: Text(n.titulo, style: TipografiaTrato.tituloCartao)),
                        ],
                      ),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(n.texto, style: TipografiaTrato.corpo),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(
                        n.quando,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: CoresTrato.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
