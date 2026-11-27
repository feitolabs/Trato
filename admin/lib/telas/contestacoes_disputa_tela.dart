import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart' show confirmarAtendimento;
import 'compensacoes_modal.dart';

const _status = {
  'aberta': 'Aberta',
  'em_analise': 'Em análise',
  'aguardando_aprovacao': 'Aguardando aprovação',
  'mantida': 'Mantida',
  'alterada': 'Alterada',
  'revertida': 'Revertida',
};

const _efeitos = {
  'nenhum': 'Sem efeito no dinheiro',
  'pendente_financeiro': 'Dinheiro pendente',
  'executado': 'Executado',
};

const _decisoes = {
  'liberar_tudo': 'Liberar tudo ao profissional',
  'reembolso_total': 'Reembolso total ao cliente',
  'reembolso_parcial': 'Reembolso parcial',
  'nova_visita': 'Nova visita',
};

String _decisao(String codigo) => _decisoes[codigo] ?? codigo;

(String, Tom) _chip(String s) => (
      _status[s] ?? s,
      switch (s) {
        'aberta' || 'aguardando_aprovacao' => Tom.alerta,
        'em_analise' => Tom.info,
        _ => Tom.ok,
      },
    );

/// Contestação da decisão de disputa (Termos 8.7). Nada aqui move dinheiro; prazos, alçada,
/// impedimento e coerência da decisão são conferidos pelo backend.
class ContestacoesDisputaTela extends StatefulWidget {
  const ContestacoesDisputaTela({super.key});

  @override
  State<ContestacoesDisputaTela> createState() => _ContestacoesDisputaTelaState();
}

class _ContestacoesDisputaTelaState extends State<ContestacoesDisputaTela> {
  String? _situacao;
  String? _efeito;
  String _pedido = '';
  bool _atrasadas = false;

  Widget _escolha(String rotulo, String? valor, Map<String, String> opcoes, ValueChanged<String?> aoMudar) => SizedBox(
        width: 220,
        child: DropdownButtonFormField<String?>(
          key: ValueKey('contestacao-$rotulo'),
          initialValue: valor,
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo),
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => aoMudar(v)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final filtro = FiltroContestacoes(
      status: _situacao,
      efeito: _efeito,
      pedidoId: _pedido.isEmpty ? null : _pedido,
      atrasadas: _atrasadas,
    );
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(labelText: 'Código do pedido', helperText: 'Enter para buscar'),
              onSubmitted: (v) => setState(() => _pedido = v.trim()),
            ),
          ),
          _escolha('Situação', _situacao, _status, (v) => _situacao = v),
          _escolha('Dinheiro', _efeito, _efeitos, (v) => _efeito = v),
          FilterChip(
            label: const Text('Só atrasadas'),
            selected: _atrasadas,
            onSelected: (v) => setState(() => _atrasadas = v),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Contestação de decisão',
          subtitulo: 'Outra pessoa revê a decisão da disputa (Termos 8.7)',
        ),
        Expanded(
          child: FilaRemota<ContestacaoDisputa>(
            filtro: filtro,
            esqueleto: const EsqueletoPagina(),
            chave: (c) => c.id,
            carregar: (deslocamento, limite) =>
                context.api.listarContestacoesDisputa(filtro, deslocamento: deslocamento, limite: limite),
            construir: (context, fila) => LayoutBuilder(
              builder: (context, tam) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: tam.maxHeight * 0.4),
                    child: SingleChildScrollView(child: filtros),
                  ),
                  Expanded(
                    child: MestreDetalhe<ContestacaoDisputa>(
                      itens: fila.itens,
                      chave: (c) => c.id,
                      mensagemSemItens: 'Nenhuma contestação com esse filtro.',
                      tituloDetalhe: (c) => c.protocolo,
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'contestações'),
                      itemBuilder: (context, c, sel) {
                        final (texto, tom) = _chip(c.status);
                        return CartaoLista(
                          titulo: '${c.protocolo} · ${c.contestantePapel ?? 'parte'}',
                          linhas: ['Pedido ${c.pedidoId}', 'Responder até ${formatarData(c.responderAte)}'],
                          chips: [
                            if (c.atrasada) const ChipEstado('Atrasada', tom: Tom.erro),
                            ChipEstado(texto, tom: tom),
                            if (c.efeitoFinanceiro == ContestacaoDisputa.pendenteFinanceiro)
                              const ChipEstado('Dinheiro pendente', tom: Tom.erro),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, c) => CarregaDados<ContestacaoDisputa>(
                        key: ValueKey('contestacao-${c.id}'),
                        esqueleto: const EsqueletoPagina(),
                        atualizarSozinho: true,
                        carregar: () => context.api.obterContestacaoDisputa(c.id),
                        construir: (context, completa, recarregar) => _Detalhe(
                          key: ValueKey(c.id),
                          contestacao: completa,
                          aoMudar: () async {
                            await recarregar();
                            await fila.recarregar();
                          },
                        ),
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

class _Detalhe extends StatefulWidget {
  const _Detalhe({super.key, required this.contestacao, required this.aoMudar});
  final ContestacaoDisputa contestacao;
  final Future<void> Function() aoMudar;

  @override
  State<_Detalhe> createState() => _DetalheState();
}

class _DetalheState extends State<_Detalhe> {
  String? _resultado;
  String? _nova;
  final _valor = TextEditingController();
  final _resposta = TextEditingController();
  bool _tentou = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _valor.dispose();
    _resposta.dispose();
    super.dispose();
  }

  bool _souEu(String? id) {
    String limpo(String? s) => (s ?? '').replaceAll('-', '');
    final eu = limpo(context.eu?.id);
    return eu.isNotEmpty && limpo(id) == eu;
  }

  bool get _parcial => _resultado != 'mantida' && _nova == 'reembolso_parcial';

  /// Reembolso parcial precisa ser maior que zero; o teto quem confere é o backend.
  int? get _centavos {
    final v = lerReaisEmCentavos(_valor.text);
    return v == null || v <= 0 ? null : v;
  }

  String? get _erroValor {
    if (_valor.text.trim().isNotEmpty && lerReaisEmCentavos(_valor.text) == null) return kErroReais;
    return _tentou && _centavos == null ? 'Informe um valor maior que zero' : null;
  }

  Future<void> _enviar(Future<ContestacaoDisputa> Function() chamada, String Function(ContestacaoDisputa) aviso) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await chamada();
      if (mounted) mostrarAviso(context, aviso(r));
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      await widget.aoMudar();
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _decidir() async {
    if (_enviando) return;
    setState(() => _tentou = true);
    final resultado = _resultado;
    final resposta = _resposta.text.trim();
    final muda = resultado != null && resultado != 'mantida';
    final nova = muda ? _nova : null;
    final valor = muda && _parcial ? _centavos : null;
    if (resultado == null ||
        resposta.length < kMotivoMinimo ||
        (muda && (nova == null || (nova == 'reembolso_parcial' && valor == null)))) {
      return;
    }
    final ok = await confirmarAtendimento(
      context,
      titulo: 'Enviar a decisão da contestação?',
      texto: 'Resultado: ${_status[resultado]}'
          '${nova == null ? '' : ' · ${_decisao(nova)}'}'
          '${valor == null ? '' : ' de ${formatarReais(valor)}'}.\n\n'
          'As duas partes vão ler:\n$resposta\n\n'
          'Nenhum dinheiro é movimentado aqui. Se o valor do reembolso mudar, outra pessoa precisa aprovar.',
      verbo: 'Enviar decisão',
    );
    if (!ok || !mounted) return;
    final api = context.api;
    await _enviar(
      () => api.decidirContestacaoDisputa(widget.contestacao.id,
          resultado: resultado, resposta: resposta, novaDecisao: nova, novoValorReembolsoCentavos: valor),
      (r) => r.status == ContestacaoDisputa.aguardandoAprovacao
          ? 'Decisão enviada. Aguarda a aprovação de outra pessoa.'
          : 'Contestação decidida.',
    );
  }

  Future<void> _aprovar(bool aprovar) async {
    final motivo = await pedirMotivo(
      context,
      titulo: aprovar ? 'Aprovar a decisão da contestação?' : 'Devolver para nova análise?',
      descricao: aprovar
          ? 'A decisão passa a valer e as partes são avisadas. Nenhum dinheiro é movimentado aqui.'
          : 'A decisão proposta é apagada e o caso volta para análise.',
      rotuloConfirmar: aprovar ? 'Aprovar' : 'Devolver',
      destrutivo: !aprovar,
    );
    if (motivo == null || !mounted) return;
    final api = context.api;
    await _enviar(
      () => api.aprovarContestacaoDisputa(widget.contestacao.id, aprovar: aprovar, motivo: motivo),
      (r) => !aprovar
          ? 'Devolvida para análise.'
          : (r.efeitoFinanceiro == ContestacaoDisputa.pendenteFinanceiro
              ? 'Aprovada. Nenhum dinheiro foi movimentado: há pendência no financeiro.'
              : 'Aprovada.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contestacao;
    final (texto, tom) = _chip(c.status);
    final original = c.decisaoOriginal;
    final vigente = c.decisaoVigente;
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(c.protocolo, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [if (c.atrasada) const ChipEstado('Atrasada', tom: Tom.erro), ChipEstado(texto, tom: tom)],
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (c.efeitoFinanceiro == ContestacaoDisputa.pendenteFinanceiro) ..._pendencia(c),
        Linha('Pedido', c.pedidoId),
        Linha('Quem contesta', c.contestantePapel == 'profissional' ? 'Profissional' : 'Cliente'),
        Linha('Canal', c.canal == 'sac' ? 'Atendimento' : c.canal),
        Linha('Aberta em', formatarData(c.abertaEm)),
        Linha('Prazo para contestar', formatarData(c.contestarAte)),
        Linha('Responder até', formatarData(c.responderAte)),
        Linha('O que não foi considerado', c.oQueFaltou),
        Linha('Anexos', c.anexos.isEmpty ? 'Nenhum' : '${c.anexos.length} (o painel ainda não abre)'),
        const SizedBox(height: EspacosTrato.x4),
        Text('Decisão da disputa', style: TipografiaTrato.secao),
        if (c.valorCongeladoCentavos != null) Linha('Valor em disputa', formatarReais(c.valorCongeladoCentavos!)),
        if (original != null)
          Linha('Original',
              '${_decisao(original.resultado)} · volta ao cliente ${formatarReais(original.reembolsoCentavos)}'),
        if (vigente != null)
          Linha('Vale hoje',
              '${_decisao(vigente.resultado)} · volta ao cliente ${formatarReais(vigente.reembolsoCentavos)}'),
        if (c.novaDecisao != null)
          Linha(
            c.status == ContestacaoDisputa.aguardandoAprovacao ? 'Proposta' : 'Decisão desta contestação',
            '${_decisao(c.novaDecisao!)}'
            '${c.novoValorReembolsoCentavos == null ? '' : ' · ${formatarReais(c.novoValorReembolsoCentavos!)}'}',
          ),
        if (c.resposta != null) Linha('Resposta às partes', c.resposta!),
        if (c.decididaEm != null) Linha('Decidida em', formatarData(c.decididaEm!)),
        Linha('Efeito no dinheiro', _efeitos[c.efeitoFinanceiro] ?? c.efeitoFinanceiro),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (c.paraDecidir) ..._areaDeDecisao(c),
        if (c.status == ContestacaoDisputa.aguardandoAprovacao) ..._areaDeAprovacao(c),
      ],
    );
  }

  /// Dinheiro pendente: deixa claro que nada saiu e oferece a compensação quando o servidor
  /// mostra que a decisão que vale hoje devolve mais ao cliente que a original.
  List<Widget> _pendencia(ContestacaoDisputa c) {
    final original = c.decisaoOriginal;
    final vigente = c.decisaoVigente;
    final devolveMais =
        original != null && vigente != null && vigente.reembolsoCentavos > original.reembolsoCentavos;
    return [
      const BannerInfo(
        'A decisão mudou o valor, mas nenhum dinheiro saiu nem voltou. Falta resolver no financeiro.',
        titulo: 'Nada foi movimentado.',
        tom: Tom.erro,
        icone: Icons.warning_amber_outlined,
      ),
      const SizedBox(height: EspacosTrato.x2),
      if (devolveMais && context.pode(Permissao.disputasDecidir))
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoTrato.secundario(
            'Registrar compensação',
            aoPressionar: () => abrirRegistroDeCompensacao(context, pedidoId: c.pedidoId, contestacaoId: c.id),
          ),
        )
      else if (!devolveMais)
        Text(
          'A decisão de agora não devolve mais ao cliente que a original: compensação não se aplica.',
          style: TipografiaTrato.legenda,
        ),
      const SizedBox(height: EspacosTrato.x3),
    ];
  }

  List<Widget> _areaDeDecisao(ContestacaoDisputa c) {
    if (!context.pode(Permissao.disputasDecidir)) {
      return const [BannerInfo('Seu papel acompanha a contestação, mas não decide.')];
    }
    if (_souEu(c.decididaPor) || _souEu(c.disputaAprovadaPor)) {
      return const [
        BannerInfo('Você decidiu ou aprovou a disputa: outra pessoa analisa a contestação.', tom: Tom.alerta),
      ];
    }
    return [
      const Divider(),
      Text('Decidir a contestação', style: TipografiaTrato.secao),
      const SizedBox(height: EspacosTrato.x3),
      Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          for (final (v, r) in const [('mantida', 'Manter'), ('alterada', 'Alterar'), ('revertida', 'Reverter')])
            ChoiceChip(
              label: Text(r),
              selected: _resultado == v,
              onSelected: _enviando ? null : (_) => setState(() => _resultado = v),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
      if (_tentou && _resultado == null)
        Text('Escolha um resultado.', style: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto)),
      if (_resultado != null && _resultado != 'mantida') ...[
        const SizedBox(height: EspacosTrato.x3),
        DropdownButtonFormField<String>(
          initialValue: _nova,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Nova decisão',
            errorText: _tentou && _nova == null ? 'Escolha a nova decisão' : null,
          ),
          items: [for (final e in _decisoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: _enviando ? null : (v) => setState(() => _nova = v),
        ),
        if (_parcial) ...[
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: _valor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Novo valor do reembolso',
              prefixText: 'R\$ ',
              helperText: 'Total que volta ao cliente. O servidor confere o limite.',
              helperMaxLines: 2,
              errorText: _erroValor,
              errorMaxLines: 3,
            ),
          ),
        ],
      ],
      const SizedBox(height: EspacosTrato.x3),
      TextField(
        controller: _resposta,
        minLines: 3,
        maxLines: 6,
        maxLength: 4000,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Resposta que as duas partes vão ler',
          errorText: _tentou && _resposta.text.trim().length < kMotivoMinimo
              ? 'Escreva ao menos $kMotivoMinimo caracteres'
              : null,
        ),
      ),
      const AvisoAuditoria(),
      const SizedBox(height: EspacosTrato.x3),
      Align(
        alignment: Alignment.centerRight,
        child: BotaoTrato.primario(
          'Revisar decisão',
          aoPressionar: _enviando ? null : _decidir,
          carregando: _enviando,
          rotuloCarregando: 'Enviando',
        ),
      ),
    ];
  }

  List<Widget> _areaDeAprovacao(ContestacaoDisputa c) {
    if (!context.pode(Permissao.disputasSegundaPessoa)) {
      return const [BannerInfo('Aguarda a aprovação de uma segunda pessoa.', tom: Tom.alerta)];
    }
    if (_souEu(c.analistaId) || _souEu(c.decididaPor) || _souEu(c.disputaAprovadaPor)) {
      return const [
        BannerInfo('Você já atuou neste caso: a aprovação precisa ser de outra pessoa.', tom: Tom.alerta),
      ];
    }
    return [
      const BannerInfo('A decisão muda o valor do reembolso: confira antes de aprovar.', tom: Tom.alerta),
      const SizedBox(height: EspacosTrato.x3),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: EspacosTrato.x3,
        runSpacing: EspacosTrato.x3,
        children: [
          BotaoTrato.secundario('Devolver para análise', aoPressionar: _enviando ? null : () => _aprovar(false)),
          BotaoTrato.primario('Aprovar decisão', aoPressionar: _enviando ? null : () => _aprovar(true)),
        ],
      ),
    ];
  }
}
