import 'package:flutter/material.dart';

import '../comuns/textos_dos_termos.dart';
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
    this.aoVerTour,
    this.aoRelatarBug,
    this.verificarAtendimento,
    this.aoFalarComOTrato,
    this.aoVerTermos,
  });

  /// Termos 1.4: os textos e o registro do aceite, consultados pela central de ajuda.
  final VoidCallback? aoVerTermos;

  /// Falso: o servidor não tem o atendimento pelo app (fica só o e-mail, como antes).
  final Future<bool> Function()? verificarAtendimento;

  /// "Falar com o Trato" (Termos 25.1): chamados com protocolo.
  final VoidCallback? aoFalarComOTrato;

  final ServicoAjuda servico;

  /// "Relatar bug": abre o e-mail com o relato do app. Sem ele, o botão não aparece.
  final VoidCallback? aoRelatarBug;
  final VoidCallback? aoFalarComSuporte;
  final VoidCallback? aoRelatarProblema;
  final VoidCallback? aoVerTour;

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
          aoVerTour: aoVerTour,
          aoRelatarBug: aoRelatarBug,
          verificarAtendimento: verificarAtendimento,
          aoFalarComOTrato: aoFalarComOTrato,
          aoVerTermos: aoVerTermos,
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
    this.aoVerTour,
    this.aoRelatarBug,
    this.verificarAtendimento,
    this.aoFalarComOTrato,
    this.aoVerTermos,
  });

  final VoidCallback? aoVerTermos;
  final Future<bool> Function()? verificarAtendimento;
  final VoidCallback? aoFalarComOTrato;
  final VoidCallback? aoRelatarBug;
  final List<PerguntaFrequente> itens;
  final VoidCallback? aoFalarComSuporte;
  final VoidCallback? aoRelatarProblema;
  final VoidCallback? aoVerTour;

  @override
  State<_ConteudoAjuda> createState() => _ConteudoAjudaState();
}

class _ConteudoAjudaState extends State<_ConteudoAjuda> {
  final _busca = TextEditingController();
  var _temAtendimento = false;

  @override
  void initState() {
    super.initState();
    _conferirAtendimento();
  }

  Future<void> _conferirAtendimento() async {
    final conferir = widget.verificarAtendimento;
    if (conferir == null || widget.aoFalarComOTrato == null) return;
    var tem = true;
    try {
      tem = await conferir();
    } on Object {
      // Falha passageira: o atendimento aparece e a tela dele tem "tentar de novo".
    }
    if (mounted) setState(() => _temAtendimento = tem);
  }

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
            style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
          )
        else if (filtradas.isEmpty)
          Text(
            'Nenhuma dúvida encontrada para "${_busca.text.trim()}".',
            style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
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
        if (widget.aoVerTermos != null) ...[
          const SizedBox(height: EspacosTrato.x5),
          BotaoSecundario(
            key: const Key('ajuda-termos'),
            texto: 'Termos e meu aceite',
            icone: Icons.description_outlined,
            aoTocar: widget.aoVerTermos,
          ),
        ],
        if (widget.aoVerTour != null) ...[
          const SizedBox(height: EspacosTrato.x5),
          BotaoSecundario(
            key: const Key('ver-tour-de-novo'),
            texto: 'Ver tour de novo',
            icone: Icons.explore_outlined,
            aoTocar: widget.aoVerTour,
          ),
        ],
        if (_temAtendimento ||
            widget.aoFalarComSuporte != null ||
            widget.aoRelatarProblema != null ||
            widget.aoRelatarBug != null) ...[
          const SizedBox(height: EspacosTrato.x6),
          Text('PRECISA DE MAIS AJUDA?', style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Nossa equipe responde por mensagem, com atenção a cada caso. '
            '$textoAtendimentoHumano',
            style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x4),
          if (_temAtendimento) ...[
            BotaoPrimario(
              key: const Key('falar-com-o-trato'),
              texto: 'Falar com o Trato',
              icone: Icons.support_agent,
              aoTocar: widget.aoFalarComOTrato,
            ),
            if (widget.aoFalarComSuporte != null) ...[
              const SizedBox(height: EspacosTrato.x3),
              BotaoSecundario(
                texto: 'Escrever por e-mail',
                icone: Icons.mail_outline,
                aoTocar: widget.aoFalarComSuporte,
              ),
            ],
          ] else if (widget.aoFalarComSuporte != null)
            BotaoPrimario(
              texto: 'Falar com o suporte',
              icone: Icons.support_agent,
              aoTocar: widget.aoFalarComSuporte,
            ),
          if ((_temAtendimento || widget.aoFalarComSuporte != null) &&
              widget.aoRelatarProblema != null)
            const SizedBox(height: EspacosTrato.x3),
          if (widget.aoRelatarProblema != null)
            !_temAtendimento && widget.aoFalarComSuporte == null
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
          if (widget.aoRelatarBug != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            BotaoSecundario(
              key: const Key('botao-relatar-bug'),
              texto: 'Relatar bug',
              icone: Icons.bug_report_outlined,
              aoTocar: widget.aoRelatarBug,
            ),
          ],
        ],
      ],
    );
    return recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista);
  }
}
