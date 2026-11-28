import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'avaliacoes_modais.dart';

const kStatusRevisaoAvaliacao = {
  'aberta': 'Aberta',
  'em_analise': 'Em análise',
  'aceita': 'Aceita',
  'recusada': 'Recusada',
};

const kTiposRevisaoAvaliacao = {
  'revisao': 'Revisão de avaliação',
  'contestacao_ocultacao': 'Contestação de ocultação',
};

const kMotivosOcultacaoAvaliacao = {
  'ofensa_ou_ilegal': 'Ofensa ou conteúdo ilegal',
  'dados_pessoais': 'Dados pessoais expostos',
  'sem_pedido_real_ou_falsa': 'Sem pedido real ou falsa',
  'nao_participou': 'Quem avaliou não participou',
  'ordem_judicial': 'Ordem judicial',
};

String rotuloAvaliacao(Map<String, String> mapa, String codigo) => mapa[codigo] ?? codigo;

(String, Tom) _chip(String status) => (
      rotuloAvaliacao(kStatusRevisaoAvaliacao, status),
      switch (status) {
        'aberta' => Tom.alerta,
        'em_analise' => Tom.info,
        'aceita' => Tom.ok,
        'recusada' => Tom.neutro,
        _ => Tom.neutro,
      },
    );

/// Moderação e revisão de avaliações (Termos 12.6, 12.7 e 20.5).
class AvaliacoesTela extends StatefulWidget {
  const AvaliacoesTela({super.key});

  @override
  State<AvaliacoesTela> createState() => _AvaliacoesTelaState();
}

class _AvaliacoesTelaState extends State<AvaliacoesTela> {
  String? _status;
  String _avaliacaoId = '';
  int _versao = 0;

  Future<void> _abrirAcao(Future<bool> Function() abrir) async {
    if (await abrir() && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final podeModerar = context.pode(Permissao.avaliacoesModerar);
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              key: const ValueKey('avaliacao-situacao'),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final e in kStatusRevisaoAvaliacao.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              key: const ValueKey('avaliacao-id-filtro'),
              decoration: const InputDecoration(
                labelText: 'Código da avaliação',
                helperText: 'Enter para buscar',
              ),
              onSubmitted: (v) => setState(() => _avaliacaoId = v.trim()),
            ),
          ),
          // No cabeçalho, um terceiro botão estoura o layout em telas médias.
          if (podeModerar)
            BotaoTrato.secundario('Avisar o autor', aoPressionar: () => abrirAvisarAutor(context)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Avaliações',
          subtitulo: 'Moderação e pedidos de revisão (Termos 12.6)',
          acoes: [
            if (podeModerar) ...[
              BotaoTrato.secundario(
                'Ocultar avaliação',
                aoPressionar: () => _abrirAcao(() => abrirOcultarAvaliacao(context)),
              ),
              BotaoTrato.secundario(
                'Reverter ocultação',
                aoPressionar: () => _abrirAcao(() => abrirReverterOcultacao(context)),
              ),
            ],
          ],
        ),
        Expanded(
          child: FilaRemota<RevisaoAvaliacao>(
            key: ValueKey('fila-avaliacoes-$_versao'),
            filtro: (_status, _avaliacaoId),
            esqueleto: const EsqueletoPagina(),
            chave: (r) => r.id,
            carregar: (deslocamento, limite) => context.api.listarRevisoesAvaliacao(
              status: _status,
              avaliacaoId: _avaliacaoId.isEmpty ? null : _avaliacaoId,
              deslocamento: deslocamento,
              limite: limite,
            ),
            construir: (context, fila) => LayoutBuilder(
              builder: (context, tam) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: tam.maxHeight * 0.4),
                    child: SingleChildScrollView(child: filtros),
                  ),
                  Expanded(
                    child: MestreDetalhe<RevisaoAvaliacao>(
                      itens: fila.itens,
                      chave: (r) => r.id,
                      mensagemSemItens: 'Nenhum pedido de revisão com esse filtro.',
                      tituloDetalhe: (r) => r.protocolo,
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'pedidos'),
                      itemBuilder: (context, r, sel) {
                        final (texto, tom) = _chip(r.status);
                        return CartaoLista(
                          titulo: '${r.protocolo} · ${rotuloAvaliacao(kTiposRevisaoAvaliacao, r.tipo)}',
                          linhas: [
                            'Avaliação ${r.avaliacaoId}',
                            'Aberta em ${formatarData(r.abertaEm)}',
                            if (!r.decidida) 'Responder até ${formatarData(r.responderAte)}',
                          ],
                          chips: [
                            if (r.atrasada(DateTime.now())) const ChipEstado('Prazo vencido', tom: Tom.erro),
                            ChipEstado(texto, tom: tom),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, r) => _DetalheRevisao(
                        key: ValueKey('${r.id}-${r.status}'),
                        revisao: r,
                        aoMudar: () => fila.recarregar(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetalheRevisao extends StatefulWidget {
  const _DetalheRevisao({super.key, required this.revisao, required this.aoMudar});
  final RevisaoAvaliacao revisao;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalheRevisao> createState() => _DetalheRevisaoState();
}

class _DetalheRevisaoState extends State<_DetalheRevisao> {
  bool _enviando = false;
  String? _erro;

  Future<void> _iniciarAnalise() async {
    if (_enviando) return;
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Iniciar análise?',
      texto: 'O pedido ${widget.revisao.protocolo} passa para "Em análise" sob sua responsabilidade.',
      verbo: 'Iniciar análise',
    );
    if (!ok || !mounted) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.analisarRevisaoAvaliacao(widget.revisao.id);
      if (mounted) mostrarAviso(context, 'Pedido colocado em análise.');
      await widget.aoMudar();
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirE(Future<bool> Function() modal) async {
    if (await modal() && mounted) await widget.aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.revisao;
    final (texto, tom) = _chip(r.status);
    final atrasada = r.atrasada(DateTime.now());
    final podeModerar = context.pode(Permissao.avaliacoesModerar);
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(r.protocolo, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          children: [
            if (atrasada) const ChipEstado('Prazo vencido', tom: Tom.erro),
            ChipEstado(texto, tom: tom),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (atrasada) ...[
          BannerInfo(
            'O prazo para responder venceu em ${formatarData(r.responderAte)}.',
            titulo: 'Prazo vencido.',
            tom: Tom.erro,
            icone: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        Linha('Tipo', rotuloAvaliacao(kTiposRevisaoAvaliacao, r.tipo)),
        Linha('Avaliação', r.avaliacaoId),
        if (r.ocultacaoId != null) Linha('Ocultação', r.ocultacaoId!),
        Linha('Canal', r.canal),
        Linha('Justificativa', r.justificativa),
        Linha('Anexos', r.anexos.isEmpty ? 'Nenhum anexo' : '${r.anexos.length} arquivo(s)'),
        Linha('Aberta em', formatarData(r.abertaEm)),
        Linha('Responder até', formatarData(r.responderAte)),
        if (r.resposta != null) Linha('Resposta', r.resposta!),
        if (r.mesmoAnalistaJustificativa != null)
          Linha('Justificativa do mesmo analista', r.mesmoAnalistaJustificativa!),
        if (r.ocultacaoAplicadaId != null) Linha('Ocultação aplicada', r.ocultacaoAplicadaId!),
        if (r.decididaEm != null) Linha('Decidida em', formatarData(r.decididaEm!)),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (r.decidida)
          const BannerInfo('Pedido decidido: não recebe novas alterações.')
        else if (podeModerar)
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (r.status == 'aberta')
                BotaoTrato.secundario(
                  'Iniciar análise',
                  aoPressionar: _enviando ? null : _iniciarAnalise,
                ),
              BotaoTrato.primario(
                'Decidir revisão',
                aoPressionar: _enviando ? null : () => _abrirE(() => abrirDecidirRevisao(context, r)),
              ),
            ],
          ),
      ],
    );
  }
}
