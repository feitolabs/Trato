import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

/// F5.13 — Central de ajuda (sem protótipo; o item "Central de ajuda" do Perfil abre esta).
/// Perguntas frequentes curtas, falar com o suporte (pessoas da equipe) e relatar problema.
class AjudaTela extends StatelessWidget {
  const AjudaTela({
    super.key,
    required this.servico,
    this.aoFalarComSuporte,
    this.aoRelatarProblema,
  });

  final ServicoAjuda servico;
  final VoidCallback? aoFalarComSuporte;
  final VoidCallback? aoRelatarProblema;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Central de ajuda',
      child: CarregadorTela<List<PerguntaFrequente>>(
        carregar: servico.perguntas,
        construir: (context, itens, _) => ListView(
          padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
          children: [
            Text('PERGUNTAS FREQUENTES', style: TipografiaTrato.sobretitulo),
            const SizedBox(height: EspacosTrato.x3),
            if (itens.isEmpty)
              Text(
                'Ainda não há perguntas por aqui. Fale com o suporte abaixo.',
                style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
              )
            else
              CartaoTrato(
                child: Column(
                  children: [
                    for (final p in itens)
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                          expandedAlignment: Alignment.centerLeft,
                          title: Text(p.pergunta, style: TipografiaTrato.corpoForte),
                          children: [Text(p.resposta, style: TipografiaTrato.corpo)],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: EspacosTrato.x6),
            Text('PRECISA DE MAIS AJUDA?', style: TipografiaTrato.sobretitulo),
            const SizedBox(height: EspacosTrato.x3),
            Text(
              'Nossa equipe responde por mensagem, com atenção a cada caso.',
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x4),
            BotaoPrimario(
              texto: 'Falar com o suporte',
              icone: Icons.support_agent,
              aoTocar: aoFalarComSuporte,
            ),
            const SizedBox(height: EspacosTrato.x3),
            BotaoSecundario(
              texto: 'Relatar um problema',
              icone: Icons.flag_outlined,
              aoTocar: aoRelatarProblema,
            ),
          ],
        ),
      ),
    );
  }
}
