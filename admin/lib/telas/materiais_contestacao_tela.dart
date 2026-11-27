import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'materiais_contestacao_modais.dart';
import 'provas_modal.dart';

const kStatusContestacaoMaterial = {
  'aberta': 'Aberta',
  'em_analise': 'Em análise',
  'procedente': 'Procedente',
  'parcial': 'Parcial',
  'improcedente': 'Improcedente',
};

const kMotivosContestacaoMaterial = {
  'nao_comprovado': 'Material não comprovado',
  'diferente_do_combinado': 'Diferente do combinado',
};

String _situacao(String status) => kStatusContestacaoMaterial[status] ?? 'Situação não reconhecida';

Tom _tom(String status) => switch (status) {
      'aberta' => Tom.alerta,
      'em_analise' => Tom.info,
      'procedente' || 'parcial' => Tom.ok,
      _ => Tom.neutro,
    };

/// Fila e decisão das contestações de materiais (Termos 6.9). A tela não move dinheiro.
class MateriaisContestacaoTela extends StatefulWidget {
  const MateriaisContestacaoTela({super.key});

  @override
  State<MateriaisContestacaoTela> createState() => _MateriaisContestacaoTelaState();
}

class _MateriaisContestacaoTelaState extends State<MateriaisContestacaoTela> {
  String? _status;
  String _pedidoId = '';

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              key: const ValueKey('material-status'),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final e in kStatusContestacaoMaterial.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              key: const ValueKey('material-pedido-filtro'),
              decoration: const InputDecoration(labelText: 'Código do pedido', helperText: 'Enter para buscar'),
              onSubmitted: (v) => setState(() => _pedidoId = v.trim()),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Contestação de materiais',
          subtitulo: 'Materiais não comprovados ou diferentes dos combinados (Termos 6.9)',
        ),
        Expanded(
          child: FilaRemota<ContestacaoMaterial>(
            filtro: (_status, _pedidoId),
            esqueleto: const EsqueletoPagina(),
            chave: (c) => c.id,
            carregar: (deslocamento, limite) => context.api.listarContestacoesMaterial(
              status: _status,
              pedidoId: _pedidoId.isEmpty ? null : _pedidoId,
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
                    child: MestreDetalhe<ContestacaoMaterial>(
                      itens: fila.itens,
                      chave: (c) => c.id,
                      mensagemSemItens: 'Nenhuma contestação de materiais com esse filtro.',
                      tituloDetalhe: (c) => c.protocolo,
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'contestações'),
                      itemBuilder: (context, c, sel) => CartaoLista(
                        titulo: '${c.protocolo} · Pedido ${c.pedidoId}',
                        linhas: [
                          'Contestado: ${formatarReais(c.valorContestadoCentavos)}',
                          if (c.pendenteDeDecisao) 'Responder até ${formatarData(c.responderAte)}',
                        ],
                        chips: [
                          if (c.atrasada(DateTime.now())) const ChipEstado('Prazo vencido', tom: Tom.erro),
                          ChipEstado(_situacao(c.status), tom: _tom(c.status)),
                        ],
                        selecionado: sel,
                      ),
                      detalheBuilder: (context, c) => _DetalheContestacao(
                        key: ValueKey('${c.id}-${c.status}'),
                        contestacao: c,
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

class _DetalheContestacao extends StatefulWidget {
  const _DetalheContestacao({super.key, required this.contestacao, required this.aoMudar});
  final ContestacaoMaterial contestacao;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalheContestacao> createState() => _DetalheContestacaoState();
}

class _DetalheContestacaoState extends State<_DetalheContestacao> {
  bool _enviando = false;
  String? _erro;

  Future<void> _iniciarAnalise() async {
    if (_enviando) return;
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Iniciar análise?',
      texto: 'A contestação ${widget.contestacao.protocolo} passa para "Em análise" sob sua responsabilidade.',
      verbo: 'Iniciar análise',
    );
    if (!ok || !mounted) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.analisarContestacaoMaterial(widget.contestacao.id);
      if (mounted) mostrarAviso(context, 'Contestação colocada em análise.');
      await widget.aoMudar();
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _decidir() async {
    if (await abrirDecidirContestacaoMaterial(context, widget.contestacao) && mounted) {
      await widget.aoMudar();
    }
  }

  /// Texto do efeito financeiro. O painel nunca afirma devolução, estorno ou pagamento.
  Widget? _efeito(ContestacaoMaterial c) => switch (c.efeitoFinanceiro) {
        'nenhum' => c.status == 'procedente' || c.status == 'parcial'
            ? const BannerInfo(
                'O valor reconhecido é só o resultado da análise. Esta decisão não movimenta dinheiro.',
                tom: Tom.info,
              )
            : null,
        'pendente_financeiro' => const BannerInfo(
            'Nada deve ser informado como concluído.',
            titulo: 'Efeito financeiro pendente.',
            tom: Tom.alerta,
          ),
        _ => const BannerInfo(
            'O painel não reconhece a situação do efeito financeiro. Confira com o Financeiro antes de informar alguém.',
            tom: Tom.alerta,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.contestacao;
    final atrasada = c.atrasada(DateTime.now());
    final efeito = _efeito(c);
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(c.protocolo, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          children: [
            if (atrasada) const ChipEstado('Prazo vencido', tom: Tom.erro),
            ChipEstado(_situacao(c.status), tom: _tom(c.status)),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (atrasada) ...[
          BannerInfo(
            'O prazo de resposta venceu em ${formatarData(c.responderAte)}.',
            titulo: 'Prazo vencido.',
            tom: Tom.erro,
            icone: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        Linha('Motivo', kMotivosContestacaoMaterial[c.motivo] ?? c.motivo),
        Linha('Descrição do cliente', c.descricao.isEmpty ? 'Sem descrição' : c.descricao),
        Linha('Valor contestado', formatarReais(c.valorContestadoCentavos)),
        Linha('Pedido', c.pedidoId),
        Linha('Nota', c.notaId),
        Linha('Item', c.itemId ?? 'Nota inteira'),
        Linha('Cliente', c.clienteId),
        Linha('Provas do cliente', c.anexos.isEmpty ? 'Nenhuma' : '${c.anexos.length}'),
        Linha('Aberta em', formatarData(c.abertaEm)),
        Linha('Responder até', formatarData(c.responderAte)),
        if (c.analistaId != null) Linha('Analista', c.analistaId!),
        if (c.decidida && c.valorReconhecidoCentavos != null)
          Linha('Valor reconhecido na análise', formatarReais(c.valorReconhecidoCentavos!)),
        if (c.resposta != null) Linha('Resposta', c.resposta!),
        if (c.decididaEm != null) Linha('Decidida em', formatarData(c.decididaEm!)),
        const SizedBox(height: EspacosTrato.x3),
        // Os links só são pedidos dentro do modal, depois do motivo (o acesso é auditado).
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoTrato.secundario(
            'Ver nota e provas',
            aoPressionar: () => abrirAnexosDoMaterial(context, c.id, c.protocolo),
          ),
        ),
        if (efeito != null) ...[const SizedBox(height: EspacosTrato.x3), efeito],
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (c.decidida)
          const BannerInfo('Contestação decidida: a decisão não pode ser mudada.')
        else if (c.pendenteDeDecisao)
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (c.status == 'aberta')
                BotaoTrato.secundario('Iniciar análise', aoPressionar: _enviando ? null : _iniciarAnalise),
              BotaoTrato.primario('Decidir contestação', aoPressionar: _enviando ? null : _decidir),
            ],
          )
        else
          const BannerInfo('Situação não reconhecida: nenhuma ação disponível.', tom: Tom.alerta),
      ],
    );
  }
}
