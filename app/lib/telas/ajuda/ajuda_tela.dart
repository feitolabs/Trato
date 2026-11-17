import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import 'modelos.dart';

/// F5.13 — Central de ajuda. Perguntas frequentes com busca, suporte e relatar problema.
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
        construir: (context, itens, _) => _ConteudoAjuda(
          itens: itens,
          aoFalarComSuporte: aoFalarComSuporte,
          aoRelatarProblema: aoRelatarProblema,
        ),
      ),
    );
  }
}

class _ConteudoAjuda extends StatefulWidget {
  const _ConteudoAjuda({
    required this.itens,
    this.aoFalarComSuporte,
    this.aoRelatarProblema,
  });

  final List<PerguntaFrequente> itens;
  final VoidCallback? aoFalarComSuporte;
  final VoidCallback? aoRelatarProblema;

  @override
  State<_ConteudoAjuda> createState() => _ConteudoAjudaState();
}

class _ConteudoAjudaState extends State<_ConteudoAjuda> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final termo = normalizarTextoBusca(_busca.text);
    final filtradas = [
      for (final p in widget.itens)
        if (termo.isEmpty ||
            normalizarTextoBusca(p.pergunta).contains(termo) ||
            normalizarTextoBusca(p.resposta).contains(termo))
          p,
    ];
    final recarregar = AtualizadorTela.de(context);
    final lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        if (widget.itens.isNotEmpty) ...[
          TextField(
            controller: _busca,
            style: TipografiaTrato.corpo,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar nas dúvidas frequentes',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _busca.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _busca.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: EspacosTrato.x5),
        ],
        Text('PERGUNTAS FREQUENTES', style: TipografiaTrato.sobretitulo),
        const SizedBox(height: EspacosTrato.x3),
        if (widget.itens.isEmpty)
          Text(
            'Ainda não há perguntas por aqui. Fale com o suporte abaixo.',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          )
        else if (filtradas.isEmpty)
          Text(
            'Nenhuma dúvida encontrada para "${_busca.text.trim()}".',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          )
        else
          CartaoTrato(
            child: Column(
              children: [
                for (final p in filtradas)
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
        if (widget.aoFalarComSuporte != null || widget.aoRelatarProblema != null) ...[
          const SizedBox(height: EspacosTrato.x6),
          Text('PRECISA DE MAIS AJUDA?', style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Nossa equipe responde por mensagem, com atenção a cada caso.',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x4),
          if (widget.aoFalarComSuporte != null)
            BotaoPrimario(
              texto: 'Falar com o suporte',
              icone: Icons.support_agent,
              aoTocar: widget.aoFalarComSuporte,
            ),
          if (widget.aoFalarComSuporte != null && widget.aoRelatarProblema != null)
            const SizedBox(height: EspacosTrato.x3),
          if (widget.aoRelatarProblema != null)
            widget.aoFalarComSuporte == null
                ? BotaoPrimario(
                    texto: 'Relatar um problema',
                    icone: Icons.flag_outlined,
                    aoTocar: widget.aoRelatarProblema,
                  )
                : BotaoSecundario(
                    texto: 'Relatar um problema',
                    icone: Icons.flag_outlined,
                    aoTocar: widget.aoRelatarProblema,
                  ),
        ],
      ],
    );
    return recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista);
  }
}
