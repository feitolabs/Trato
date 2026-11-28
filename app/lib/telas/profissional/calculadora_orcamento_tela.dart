import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../auth/estrutura_auth.dart';
import '../comuns/foco_rolagem.dart';
import '../profissional_apoio/apoio.dart';
import 'dinheiro.dart';
import 'servico_orcamento.dart';

export 'servico_orcamento.dart' show ItemMaterial, OrcamentoPronto;

enum ModoOrcamento { porHora, valorFechado }

/// Sugestões para "O que não está incluído": acrescentam o texto, não precisam ser usadas.
const sugestoesNaoInclui = [
  'Material',
  'Limpeza e retirada de entulho',
  'Deslocamento adicional',
  'Reparos além do combinado',
];

/// Tela 25: "Seu orçamento". Soma (horas de deslocamento + horas trabalhadas) x valor da hora +
/// material (só para exibir). O cliente vê o total de horas.
/// Taxa e líquido NÃO são calculados aqui: vêm de [servico] (regra de dinheiro é do backend).
class CalculadoraOrcamentoTela extends StatefulWidget {
  const CalculadoraOrcamentoTela({
    super.key,
    required this.servico,
    required this.tituloPedido,
    this.aoEnviar,
    this.deslocamentoInicial,
    this.horasInicial,
    this.valorHoraInicial,
    this.garantiaInicialDias,
    this.prazoExecucaoInicialDias,
    this.itensIniciais = const [],
    this.faixaRegiaoCentavos,
    this.opcoesGarantiaDias = const [30, 60, 90],
    this.garantiaMinimaDias = 30,
    this.foraDoEscopoInicial,
    this.observacoesInicial,
    this.edicao = false,
    this.modoInicial = ModoOrcamento.porHora,
    this.valorFechadoInicial,
    this.remoto = false,
  });

  /// Pedido remoto: abre em "Valor fechado", sem deslocamento nem material.
  final bool remoto;

  final ServicoOrcamento servico;
  final String tituloPedido;
  final FutureOr<void> Function(OrcamentoPronto pronto)? aoEnviar;
  final String? deslocamentoInicial;
  final String? horasInicial;
  final String? valorHoraInicial;

  /// Nulos num orçamento novo: o app não escolhe pelo profissional (Termos 5.2).
  final int? garantiaInicialDias;
  final int? prazoExecucaoInicialDias;
  final List<ItemMaterial> itensIniciais;

  final String? foraDoEscopoInicial;
  final String? observacoesInicial;

  /// Verdadeiro quando o profissional está editando uma proposta já enviada.
  final bool edicao;
  final ModoOrcamento modoInicial;
  final String? valorFechadoInicial;

  /// "Serviços parecidos na região" (mínimo, máximo), vindo do backend. Sem dado, a linha some.
  final (int, int)? faixaRegiaoCentavos;

  /// Opções de garantia: configuração, não número fixo da tela.
  final List<int> opcoesGarantiaDias;

  /// Garantia mínima (CDC): 30 dias para serviço não durável e 90 para durável. O backend
  /// valida e devolve a regra por categoria; sem ela, o mínimo é 30. Nunca se oferece menos.
  final int garantiaMinimaDias;

  List<int> get _opcoesGarantia {
    final lista = {
      for (final d in opcoesGarantiaDias)
        if (d >= garantiaMinimaDias) d,
      garantiaMinimaDias,
    }.toList()
      ..sort();
    return lista;
  }

  @override
  State<CalculadoraOrcamentoTela> createState() => _CalculadoraOrcamentoTelaState();
}

class _CalculadoraOrcamentoTelaState extends State<CalculadoraOrcamentoTela> {
  final _scroll = ScrollController();
  late final _deslocamento = TextEditingController(text: widget.deslocamentoInicial);
  late final _horas = TextEditingController(text: widget.horasInicial);
  late final _valorHora = TextEditingController(text: widget.valorHoraInicial);
  late final _valorFechado = TextEditingController(text: widget.valorFechadoInicial);
  late final _diasExecucao =
      TextEditingController(text: widget.prazoExecucaoInicialDias?.toString());
  // Sempre em branco, também na edição: cada versão enviada tem a validade escolhida na hora.
  final _diasValidade = TextEditingController();
  late final _foraDoEscopo = TextEditingController(text: widget.foraDoEscopoInicial);
  final _sugestoesForaUsadas = <String>{};
  late final _observacoes = TextEditingController(text: widget.observacoesInicial);
  final _keyDeslocamento = GlobalKey();
  final _keyHoras = GlobalKey();
  final _keyValorHora = GlobalKey();
  final _keyValorFechado = GlobalKey();
  final _keyDias = GlobalKey();
  final _keyGarantia = GlobalKey();
  final _keyValidade = GlobalKey();
  final _keyForaDoEscopo = GlobalKey();
  final _focoDeslocamento = FocusNode();
  final _focoHoras = FocusNode();
  final _focoValorHora = FocusNode();
  final _focoValorFechado = FocusNode();
  final _focoDias = FocusNode();
  final _focoGarantia = FocusNode();
  final _focoValidade = FocusNode();
  final _focoForaDoEscopo = FocusNode();
  late ModoOrcamento _modo = widget.remoto ? ModoOrcamento.valorFechado : widget.modoInicial;

  /// Garantia antiga abaixo do mínimo fica sem escolha: o profissional escolhe de novo.
  late int? _garantia = (widget.garantiaInicialDias ?? -1) < widget.garantiaMinimaDias
      ? null
      : widget.garantiaInicialDias;
  late final List<ItemMaterial> _itens = [...widget.itensIniciais];
  bool _materialPorMim = true;
  bool _pedirSinal = false;
  bool _mostrarErros = false;
  bool _enviando = false;

  ResumoOrcamento? _resumo;
  var _resumoFalhou = false;
  int _ultimoPedido = -1;

  static final _formatadoresDeslocamento = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    LengthLimitingTextInputFormatter(5),
  ];
  static final _formatadoresHoras = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    LengthLimitingTextInputFormatter(5),
  ];
  static final _formatadoresValorHora = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    LengthLimitingTextInputFormatter(8),
  ];

  /// Mesmo limite do servidor.
  static final _formatadoresForaDoEscopo = [LengthLimitingTextInputFormatter(1000)];
  static final _formatadoresDias = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(3),
  ];

  @override
  void initState() {
    super.initState();
    _atualizarResumo();
  }

  bool get _temMaterialNoOrcamento => !widget.remoto && _itens.isNotEmpty;

  String _rotuloSugestaoFora(String chave) =>
      chave == 'Material' && _temMaterialNoOrcamento ? 'Demais materiais' : chave;

  /// Chip de sugestão: acrescenta o texto ao campo (editável) e o chip usado some.
  void _acrescentarForaDoEscopo(String chave, String texto) {
    final atual = _foraDoEscopo.text.trimRight();
    final novo = atual.isEmpty ? texto : '$atual, $texto';
    _foraDoEscopo.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
    setState(() => _sugestoesForaUsadas.add(chave));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _deslocamento.dispose();
    _horas.dispose();
    _valorHora.dispose();
    _valorFechado.dispose();
    _diasExecucao.dispose();
    _diasValidade.dispose();
    _foraDoEscopo.dispose();
    _observacoes.dispose();
    _focoDeslocamento.dispose();
    _focoHoras.dispose();
    _focoValorHora.dispose();
    _focoValorFechado.dispose();
    _focoDias.dispose();
    _focoGarantia.dispose();
    _focoValidade.dispose();
    _focoForaDoEscopo.dispose();
    super.dispose();
  }

  int get _materialCentavos =>
      _materialPorMim ? _itens.fold(0, (soma, item) => soma + item.centavos) : 0;

  /// Horas de deslocamento em décimos de hora (vazio = 0).
  int get _decimosDeslocamento =>
      _deslocamento.text.trim().isEmpty ? 0 : (Dinheiro.lerDecimosDeHora(_deslocamento.text) ?? 0);

  int get _decimosTrabalhadas => Dinheiro.lerDecimosDeHora(_horas.text) ?? 0;

  int get _total {
    if (_modo == ModoOrcamento.valorFechado) {
      final fechado = Dinheiro.lerCentavos(_valorFechado.text) ?? 0;
      return fechado + _materialCentavos;
    }
    final valorHora = Dinheiro.lerCentavos(_valorHora.text) ?? 0;
    return Dinheiro.valorDasHoras(valorHora, _decimosDeslocamento + _decimosTrabalhadas) +
        _materialCentavos;
  }

  void _mudou() {
    setState(() {});
    _atualizarResumo();
  }

  Future<void> _atualizarResumo() async {
    final total = _total;
    if (total <= 0 || total > Dinheiro.limiteOrcamentoMaximoCentavos) {
      _ultimoPedido = -1;
      if (_resumo != null || _resumoFalhou) {
        setState(() {
          _resumo = null;
          _resumoFalhou = false;
        });
      }
      return;
    }
    if (total == _ultimoPedido) return;
    _ultimoPedido = total;
    try {
      final resumo = await widget.servico.resumir(total);
      // Resposta atrasada de um total antigo não pode sobrescrever o atual.
      if (mounted && _ultimoPedido == total) {
        setState(() {
          _resumo = resumo;
          _resumoFalhou = false;
        });
      }
    } on Object {
      // O resumo é só uma prévia: sem ele a tela segue (mantém o anterior) e a próxima mudança tenta de novo.
      if (mounted && _ultimoPedido == total) {
        _ultimoPedido = -1;
        setState(() => _resumoFalhou = true);
      }
    }
  }

  String? _erroDeslocamento() {
    final texto = _deslocamento.text.trim();
    if (texto.isEmpty) return null;
    final decimos = Dinheiro.lerDecimosDeHora(texto);
    if (decimos == null) {
      return 'Horas de deslocamento inválidas. Use só números, como 1 ou 1,5.';
    }
    if (decimos > Dinheiro.limiteDecimosDeslocamentoMaximo) {
      return 'O limite de deslocamento é de ${Dinheiro.limiteDecimosDeslocamentoMaximo ~/ 10} horas.';
    }
    return null;
  }

  String? _erroHoras() {
    final decimos = Dinheiro.lerDecimosDeHora(_horas.text);
    if (decimos == null || decimos <= 0) {
      return 'Horas trabalhadas não informadas. Digite as horas, como 3 ou 2,5.';
    }
    if (decimos > Dinheiro.limiteDecimosHorasMaximo) {
      return 'O limite máximo é de ${Dinheiro.limiteDecimosHorasMaximo ~/ 10} horas.';
    }
    return null;
  }

  String? _erroValorHora() {
    final valor = Dinheiro.lerCentavos(_valorHora.text);
    if (valor == null || valor <= 0) {
      return 'Valor da hora não informado. Digite o valor por hora de trabalho (ex.: 80,00).';
    }
    if (valor > Dinheiro.limiteValorHoraMaximoCentavos) {
      return 'Valor da hora máximo é ${Dinheiro.formatar(Dinheiro.limiteValorHoraMaximoCentavos)}.';
    }
    return null;
  }

  String? _erroValorFechado() {
    final valor = Dinheiro.lerCentavos(_valorFechado.text);
    if (valor == null || valor <= 0) {
      return 'Informe o valor do serviço ou da diária (ex.: 250,00).';
    }
    if (valor > Dinheiro.limiteOrcamentoMaximoCentavos) {
      return 'O valor máximo permitido é ${Dinheiro.formatar(Dinheiro.limiteOrcamentoMaximoCentavos)}.';
    }
    return null;
  }

  String? _erroTotal() {
    if (_total > Dinheiro.limiteOrcamentoMaximoCentavos) {
      return 'O total (${Dinheiro.formatar(_total)}) excede o teto permitido de ${Dinheiro.formatar(Dinheiro.limiteOrcamentoMaximoCentavos)}.';
    }
    return null;
  }

  String? _erroDiasExecucao() {
    final dias = int.tryParse(_diasExecucao.text.trim());
    if (dias == null || dias < 1) {
      return 'Informe em quantos dias pretende concluir (mínimo 1 dia).';
    }
    if (dias > 365) return 'O prazo máximo é de 365 dias.';
    return null;
  }

  String? _erroGarantia() => _garantia == null ? 'Escolha o prazo da garantia.' : null;

  int? get _validadeEscolhida {
    final dias = int.tryParse(_diasValidade.text.trim());
    return dias == null || dias < 1 ? null : dias;
  }

  String? _erroValidade() => _validadeEscolhida == null
      ? 'Informe por quantos dias o orçamento vale (mínimo 1 dia).'
      : null;

  /// Termos 5.2: o servidor exige de 2 a 1000 caracteres (o campo já limita o máximo).
  String? _erroForaDoEscopo() {
    final tamanho = _foraDoEscopo.text.trim().runes.length;
    if (tamanho == 0) {
      return 'Diga o que não está incluído. Se nada ficar de fora, escreva isso.';
    }
    return tamanho < 2 ? 'Escreva pelo menos 2 caracteres sobre o que não está incluído.' : null;
  }

  Future<void> _adicionarItem() async {
    final item = await showModalBottomSheet<ItemMaterial>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cores.fundo,
      builder: (_) => const _NovoItemMaterial(),
    );
    if (item == null) return;
    _itens.add(item);
    _mudou();
  }

  Future<void> _editarItem(int indice) async {
    final atual = _itens[indice];
    final atualizado = await showModalBottomSheet<ItemMaterial>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cores.fundo,
      builder: (_) => _NovoItemMaterial(inicial: atual),
    );
    if (atualizado == null) return;
    _itens[indice] = atualizado;
    _mudou();
  }

  void _removerItem(int indice) {
    _itens.removeAt(indice);
    _mudou();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() => _mostrarErros = true);
    final fechado = _modo == ModoOrcamento.valorFechado;
    // Na ordem em que os campos aparecem na tela: o foco vai ao primeiro com erro.
    final campos = [
      if (fechado)
        (_keyValorFechado, _focoValorFechado, _erroValorFechado)
      else ...[
        (_keyDeslocamento, _focoDeslocamento, _erroDeslocamento),
        (_keyHoras, _focoHoras, _erroHoras),
        (_keyValorHora, _focoValorHora, _erroValorHora),
      ],
      (_keyGarantia, _focoGarantia, _erroGarantia),
      (_keyDias, _focoDias, _erroDiasExecucao),
      (_keyValidade, _focoValidade, _erroValidade),
      (_keyForaDoEscopo, _focoForaDoEscopo, _erroForaDoEscopo),
    ];
    if (_erroTotal() != null || campos.any((campo) => campo.$3() != null)) {
      focarPrimeiroErro([
        for (final (chave, foco, erro) in campos)
          EntradaCampoErro(key: chave, focusNode: foco, temErro: () => erro() != null),
      ]);
      return;
    }
    final pronto = OrcamentoPronto(
      decimosDeslocamento: fechado ? 0 : _decimosDeslocamento,
      decimosDeHora: fechado ? 0 : Dinheiro.lerDecimosDeHora(_horas.text)!,
      valorHoraCentavos: fechado ? 0 : Dinheiro.lerCentavos(_valorHora.text)!,
      garantiaDias: _garantia!,
      prazoExecucaoDias: int.parse(_diasExecucao.text.trim()),
      validadeDias: _validadeEscolhida!,
      itens: List.unmodifiable(_itens),
      materialPorMim: _materialPorMim,
      pedirSinalMaterial: _materialPorMim && _pedirSinal,
      totalCentavos: _total,
      valorFechadoCentavos: fechado ? Dinheiro.lerCentavos(_valorFechado.text)! : null,
      foraDoEscopo: _foraDoEscopo.text.trim(),
      observacoes: _observacoes.text.trim().isEmpty ? null : _observacoes.text.trim(),
    );
    if (widget.aoEnviar == null) return;
    setState(() => _enviando = true);
    try {
      await widget.aoEnviar!(pronto);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final faixa = widget.faixaRegiaoCentavos;
    return EstruturaAuth(
      scrollController: _scroll,
      tituloBarra: widget.tituloPedido,
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erroTotal() != null) ...[
            AvisoFaixa(
              texto: _erroTotal()!,
              tipo: TipoStatus.perigo,
              icone: Icons.error_outline,
            ),
            const SizedBox(height: EspacosTrato.x3),
          ],
          BotaoPrimario(
            texto: widget.edicao ? 'Enviar nova versão' : 'Enviar orçamento',
            carregando: _enviando,
            aoTocar: (_enviando || _erroTotal() != null) ? null : _enviar,
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            _validadeEscolhida == null
                ? 'Você pode editar até o cliente aceitar'
                : 'Válido por $_validadeEscolhida ${_validadeEscolhida == 1 ? 'dia' : 'dias'}'
                    ' · você pode editar até o cliente aceitar',
            style: TipografiaTrato.legenda,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      children: [
        Text(
          widget.edicao ? 'Editar orçamento' : 'Seu orçamento',
          style: TipografiaTrato.tituloGrande,
        ),
        const SizedBox(height: EspacosTrato.x4),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            ChoiceChip(
              label: const Text('Valor fechado / diária'),
              selected: _modo == ModoOrcamento.valorFechado,
              onSelected: (_) {
                setState(() => _modo = ModoOrcamento.valorFechado);
                _atualizarResumo();
              },
            ),
            if (!widget.remoto)
              ChoiceChip(
                label: const Text('Por hora + deslocamento'),
                selected: _modo == ModoOrcamento.porHora,
                onSelected: (_) {
                  setState(() => _modo = ModoOrcamento.porHora);
                  _atualizarResumo();
                },
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (_modo == ModoOrcamento.valorFechado) ...[
          KeyedSubtree(
            key: _keyValorFechado,
            child: CampoTrato(
              rotulo: 'Valor do serviço (ou diária)',
              controlador: _valorFechado,
              foco: _focoValorFechado,
              prefixo: 'R\$ ',
              dica: '250,00',
              teclado: const TextInputType.numberWithOptions(decimal: true),
              formatadores: _formatadoresValorHora,
              aoMudar: (_) => _mudou(),
              erro: _mostrarErros ? _erroValorFechado() : null,
              linhasDoErro: 10,
            ),
          ),
          const SizedBox(height: EspacosTrato.x4),
          KeyedSubtree(
            key: _keyGarantia,
            child: _CampoGarantia(
              valor: _garantia,
              opcoes: widget._opcoesGarantia,
              foco: _focoGarantia,
              erro: _mostrarErros ? _erroGarantia() : null,
              aoMudar: (dias) => setState(() => _garantia = dias),
            ),
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: _keyDeslocamento,
                  child: CampoTrato(
                    rotulo: 'Horas de deslocamento',
                    controlador: _deslocamento,
                    foco: _focoDeslocamento,
                    sufixo: 'h',
                    teclado: const TextInputType.numberWithOptions(decimal: true),
                    formatadores: _formatadoresDeslocamento,
                    aoMudar: (_) => _mudou(),
                    erro: _mostrarErros ? _erroDeslocamento() : null,
                    linhasDoErro: 10,
                  ),
                ),
              ),
              const SizedBox(width: EspacosTrato.x4),
              Expanded(
                child: KeyedSubtree(
                  key: _keyHoras,
                  child: CampoTrato(
                    rotulo: 'Horas trabalhadas',
                    controlador: _horas,
                    foco: _focoHoras,
                    sufixo: 'h',
                    teclado: const TextInputType.numberWithOptions(decimal: true),
                    formatadores: _formatadoresHoras,
                    aoMudar: (_) => _mudou(),
                    erro: _mostrarErros ? _erroHoras() : null,
                    linhasDoErro: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: _keyValorHora,
                  child: CampoTrato(
                    rotulo: 'Valor da hora',
                    controlador: _valorHora,
                    foco: _focoValorHora,
                    prefixo: 'R\$ ',
                    teclado: const TextInputType.numberWithOptions(decimal: true),
                    formatadores: _formatadoresValorHora,
                    aoMudar: (_) => _mudou(),
                    erro: _mostrarErros ? _erroValorHora() : null,
                    linhasDoErro: 10,
                  ),
                ),
              ),
              const SizedBox(width: EspacosTrato.x4),
              Expanded(
                child: KeyedSubtree(
                  key: _keyGarantia,
                  child: _CampoGarantia(
                    valor: _garantia,
                    opcoes: widget._opcoesGarantia,
                    foco: _focoGarantia,
                    erro: _mostrarErros ? _erroGarantia() : null,
                    aoMudar: (dias) => setState(() => _garantia = dias),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyDias,
          child: CampoTrato(
            rotulo: 'Prazo estimado para concluir',
            controlador: _diasExecucao,
            foco: _focoDias,
            sufixo: 'dias',
            dica: 'Ex.: 3',
            ajuda: 'Quantos dias após iniciar o serviço você leva para concluir. '
                'Você e o cliente podem negociar esse prazo na conversa.',
            teclado: TextInputType.number,
            formatadores: _formatadoresDias,
            aoMudar: (_) => _mudou(),
            erro: _mostrarErros ? _erroDiasExecucao() : null,
            linhasDoErro: 10,
          ),
        ),
        const SizedBox(height: EspacosTrato.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            key: const Key('prazo-mesmo-dia'),
            label: const Text('Mesmo dia'),
            selected: _diasExecucao.text.trim() == '1',
            onSelected: (_) {
              _diasExecucao.text = '1';
              _mudou();
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyValidade,
          child: CampoTrato(
            rotulo: 'Validade do orçamento',
            controlador: _diasValidade,
            foco: _focoValidade,
            sufixo: 'dias',
            dica: 'Ex.: 7',
            ajuda: 'Por quantos dias, a partir do envio, o orçamento vale.',
            teclado: TextInputType.number,
            formatadores: _formatadoresDias,
            aoMudar: (_) => setState(() {}),
            erro: _mostrarErros ? _erroValidade() : null,
            linhasDoErro: 10,
          ),
        ),
        if (_modo == ModoOrcamento.porHora) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Total de horas: ${Dinheiro.formatarHoras(_decimosDeslocamento + _decimosTrabalhadas)} '
            '(o cliente vê esse total). O deslocamento é cobrado pelo mesmo valor da hora.',
            key: const ValueKey('total-horas'),
            style: TipografiaTrato.legenda,
          ),
        ],
        if (faixa != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Serviços parecidos na região: ${Dinheiro.formatar(faixa.$1)} a ${Dinheiro.formatar(faixa.$2)}.',
            style: TipografiaTrato.legenda,
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        if (!widget.remoto)
          _CartaoMaterial(
            itens: _itens,
            materialPorMim: _materialPorMim,
            pedirSinal: _pedirSinal,
            aoAdicionar: _adicionarItem,
            aoEditar: _editarItem,
            aoRemover: _removerItem,
            aoEscolherQuemFornece: (eu) {
              setState(() {
                _materialPorMim = eu;
                _pedirSinal = _pedirSinal && eu;
              });
              _atualizarResumo();
            },
            aoMarcarSinal: (marcado) => setState(() => _pedirSinal = marcado),
          ),
        const SizedBox(height: EspacosTrato.x5),
        KeyedSubtree(
          key: _keyForaDoEscopo,
          child: CampoTrato(
            rotulo: 'O que não está incluído',
            controlador: _foraDoEscopo,
            foco: _focoForaDoEscopo,
            dica: 'Ex.: quebra de alvenaria, pintura ou peças extras',
            formatadores: _formatadoresForaDoEscopo,
            aoMudar: (_) => setState(() {}),
            erro: _mostrarErros ? _erroForaDoEscopo() : null,
            linhasDoErro: 10,
          ),
        ),
        if (_sugestoesForaUsadas.length < sugestoesNaoInclui.length) ...[
          const SizedBox(height: EspacosTrato.x2),
          Wrap(
            key: const Key('sugestoes-nao-incluso'),
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (final s in sugestoesNaoInclui)
                if (!_sugestoesForaUsadas.contains(s))
                  Builder(
                    builder: (_) {
                      final rotulo = _rotuloSugestaoFora(s);
                      return ActionChip(
                        key: ValueKey('sugestao-nao-incluso-$rotulo'),
                        label: Text(rotulo),
                        onPressed: () => _acrescentarForaDoEscopo(s, rotulo),
                      );
                    },
                  ),
            ],
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Observações (opcional)',
          controlador: _observacoes,
          dica: 'Condições de execução, horários ou recomendações',
        ),
        const SizedBox(height: EspacosTrato.x5),
        _ResumoEscuro(totalCentavos: _total, resumo: _resumo),
        if (_resumoFalhou)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2),
            child: Text(
              'Não deu para calcular o resumo agora.',
              key: const Key('resumo-indisponivel'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
          ),
      ],
    );
  }
}

class _CampoGarantia extends StatelessWidget {
  const _CampoGarantia({
    required this.valor,
    required this.opcoes,
    required this.foco,
    required this.erro,
    required this.aoMudar,
  });

  final int? valor;
  final List<int> opcoes;
  final FocusNode foco;
  final String? erro;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Garantia', style: TipografiaTrato.corpoForte, maxLines: 1),
        ),
        const SizedBox(height: EspacosTrato.x2),
        DropdownButtonFormField<int>(
          initialValue: opcoes.contains(valor) ? valor : null,
          focusNode: foco,
          isExpanded: true,
          hint: const Text('Escolha', maxLines: 1),
          decoration: InputDecoration(errorText: erro, errorMaxLines: 3),
          style: TipografiaTrato.corpo.copyWith(color: context.cores.texto),
          icon: const Icon(Icons.keyboard_arrow_down),
          items: [
            for (final dias in opcoes)
              DropdownMenuItem(value: dias, child: Text('$dias dias', maxLines: 1)),
          ],
          onChanged: (dias) {
            if (dias != null) aoMudar(dias);
          },
        ),
      ],
    );
  }
}

class _CartaoMaterial extends StatelessWidget {
  const _CartaoMaterial({
    required this.itens,
    required this.materialPorMim,
    required this.pedirSinal,
    required this.aoAdicionar,
    required this.aoEditar,
    required this.aoRemover,
    required this.aoEscolherQuemFornece,
    required this.aoMarcarSinal,
  });

  final List<ItemMaterial> itens;
  final bool materialPorMim;
  final bool pedirSinal;
  final VoidCallback aoAdicionar;
  final ValueChanged<int> aoEditar;
  final ValueChanged<int> aoRemover;
  final ValueChanged<bool> aoEscolherQuemFornece;
  final ValueChanged<bool> aoMarcarSinal;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Material', style: TipografiaTrato.titulo),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: BotaoLink(texto: 'Adicionar item', aoTocar: aoAdicionar),
                ),
              ),
            ],
          ),
          if (materialPorMim)
            for (var i = 0; i < itens.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => aoEditar(i),
                        borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
                          child: Row(
                            children: [
                              Expanded(child: Text(itens[i].nome, style: TipografiaTrato.corpo)),
                              const SizedBox(width: EspacosTrato.x2),
                              Text(
                                Dinheiro.formatar(itens[i].centavos),
                                style: TipografiaTrato.corpoForte,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover item',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => aoRemover(i),
                      icon: Icon(Icons.close, size: 18, color: context.cores.textoSecundario),
                    ),
                  ],
                ),
              )
          else if (itens.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'O cliente fornece o material (${itens.length} ${itens.length == 1 ? 'item listado não entra' : 'itens listados não entram'} no total).',
              style: TipografiaTrato.legenda,
            ),
          ],
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              Expanded(
                child: BotaoSecundario(
                  texto: 'Eu forneço',
                  selecionado: materialPorMim,
                  aoTocar: () => aoEscolherQuemFornece(true),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: BotaoSecundario(
                  texto: 'Cliente fornece',
                  selecionado: !materialPorMim,
                  aoTocar: () => aoEscolherQuemFornece(false),
                ),
              ),
            ],
          ),
          if (materialPorMim) ...[
            const SizedBox(height: EspacosTrato.x3),
            InkWell(
              onTap: () => aoMarcarSinal(!pedirSinal),
              borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
              child: MergeSemantics(
                  child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(value: pedirSinal, onChanged: (v) => aoMarcarSinal(v ?? false)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: EspacosTrato.x3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pedir sinal para o material', style: TipografiaTrato.corpoForte),
                          Text(
                            'Liberado quando você enviar a foto da nota.',
                            style: TipografiaTrato.legenda,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResumoEscuro extends StatelessWidget {
  const _ResumoEscuro({required this.totalCentavos, required this.resumo});

  final int totalCentavos;
  final ResumoOrcamento? resumo;

  @override
  Widget build(BuildContext context) {
    final claroForte = TipografiaTrato.corpoForte.copyWith(color: context.cores.sobrePetroleo);
    final r = resumo;
    return CartaoTrato(
      escuro: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Você recebe', style: claroForte),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    r == null ? '—' : Dinheiro.formatar(r.totalCentavos),
                    style: TipografiaTrato.tituloGrande.copyWith(
                      color: context.cores.sobrePetroleo,
                      fontSize: 34,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'O Trato é grátis: não cobramos taxa sobre o seu serviço.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.sobrePetroleo),
          ),
        ],
      ),
    );
  }
}

class _NovoItemMaterial extends StatefulWidget {
  const _NovoItemMaterial({this.inicial});

  final ItemMaterial? inicial;

  @override
  State<_NovoItemMaterial> createState() => _NovoItemMaterialState();
}

class _NovoItemMaterialState extends State<_NovoItemMaterial> {
  late final _nome = TextEditingController(text: widget.inicial?.nome ?? '');
  late final _valor = TextEditingController(
    text: widget.inicial == null ? '' : Dinheiro.paraCampo(widget.inicial!.centavos),
  );
  bool _tentou = false;

  @override
  void dispose() {
    _nome.dispose();
    _valor.dispose();
    super.dispose();
  }

  void _confirmar() {
    setState(() => _tentou = true);
    final centavos = Dinheiro.lerCentavos(_valor.text);
    if (_nome.text.trim().isEmpty ||
        centavos == null ||
        centavos <= 0 ||
        centavos > Dinheiro.limiteOrcamentoMaximoCentavos) {
      return;
    }
    Navigator.of(context).pop(ItemMaterial(nome: _nome.text.trim(), centavos: centavos));
  }

  @override
  Widget build(BuildContext context) {
    final centavos = Dinheiro.lerCentavos(_valor.text);
    final erroValor = () {
      if (!_tentou) return null;
      if (centavos == null || centavos <= 0) {
        return 'Valor do material não informado. Digite um valor em reais maior que zero.';
      }
      if (centavos > Dinheiro.limiteOrcamentoMaximoCentavos) {
        return 'Valor máximo permitido é ${Dinheiro.formatar(Dinheiro.limiteOrcamentoMaximoCentavos)}.';
      }
      return null;
    }();
    return Padding(
      padding: EdgeInsets.only(
        left: EspacosTrato.x5,
        right: EspacosTrato.x5,
        top: EspacosTrato.x5,
        bottom: MediaQuery.viewInsetsOf(context).bottom + EspacosTrato.x5,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.inicial == null ? 'Adicionar item' : 'Editar item',
              style: TipografiaTrato.titulo,
            ),
            const SizedBox(height: EspacosTrato.x4),
            CampoTrato(
              rotulo: 'Item',
              controlador: _nome,
              dica: 'Ex.: 2 tomadas 20 A',
              erro: _tentou && _nome.text.trim().isEmpty
                  ? 'Descrição do material vazia. Digite o nome do item (ex.: 2 tomadas 20 A).'
                  : null,
            ),
            const SizedBox(height: EspacosTrato.x4),
            CampoTrato(
              rotulo: 'Valor',
              controlador: _valor,
              prefixo: 'R\$ ',
              teclado: const TextInputType.numberWithOptions(decimal: true),
              formatadores: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(9),
              ],
              erro: erroValor,
            ),
            const SizedBox(height: EspacosTrato.x5),
            BotaoPrimario(
              texto: widget.inicial == null ? 'Adicionar' : 'Salvar item',
              aoTocar: _confirmar,
            ),
          ],
        ),
      ),
    );
  }
}
