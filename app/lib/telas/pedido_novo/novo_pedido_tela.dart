import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dispositivo/localizacao_do_pedido.dart';
import '../../componentes/componentes.dart';
import '../../dados/servico_cep.dart';
import '../../tema/tema.dart';
import '../comuns/foco_rolagem.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import '../conta/modelos.dart' show EnderecoSalvo;
import '../profissional/dinheiro.dart' show Dinheiro;
import '../profissional_apoio/apoio.dart' show CapturarFoto;
import 'modelos.dart';
import 'pecas_pedido.dart';

/// Formulário de solicitação de serviço (descrição, prazo, faixa e endereço).
const _maxFotos = 4;

class NovoPedidoTela extends StatefulWidget {
  const NovoPedidoTela({
    super.key,
    required this.formulario,
    this.aoEnviar,
    this.aoTrocarCategoria,
    this.aoMudarEndereco,
    this.aoAdicionarFoto,
    this.aoCapturarFoto,
    this.agora,
    this.servicoCep,
    this.enderecosSalvos = const [],
    this.profissionalConvidadoId,
    this.profissionalConvidadoNome,
  });

  final FormularioPedido formulario;

  /// Chamado com o que foi preenchido, depois de passar nas checagens da tela.
  final dynamic Function(RascunhoPedido)? aoEnviar;
  final VoidCallback? aoTrocarCategoria;
  final VoidCallback? aoMudarEndereco;
  final VoidCallback? aoAdicionarFoto;

  /// Abre câmera/galeria (com permissão e envio) e devolve a referência da foto. Quando vem,
  /// vale no lugar de [aoAdicionarFoto] e as fotos entram no [RascunhoPedido].
  final CapturarFoto? aoCapturarFoto;

  /// Relógio da tela (prazo padrão e calendário). Nulo = hora do aparelho; testes fixam a data.
  final DateTime Function()? agora;

  /// Consulta de CEP para preenchimento automático de rua, bairro e cidade.
  final ServicoCep? servicoCep;

  /// Endereços salvos na conta para preenchimento rápido com 1 toque.
  final List<EnderecoSalvo> enderecosSalvos;

  /// Quando o cliente toca em "Pedir orçamento ao [Nome]" no perfil do profissional.
  final String? profissionalConvidadoId;
  final String? profissionalConvidadoNome;

  @override
  State<NovoPedidoTela> createState() => _NovoPedidoTelaState();
}

enum _ModoPrazo { flexivel, dataLimite, urgente }

class _NovoPedidoTelaState extends State<NovoPedidoTela> {
  late final Set<String> _servicos = {...widget.formulario.servicosIniciais};

  /// A categoria tem perguntas configuradas no painel: elas substituem as genéricas.
  late final bool _temPerguntas = widget.formulario.perguntas.isNotEmpty;

  /// Respostas de escolha, múltipla, sim/não e número (texto fica nos controladores).
  late final Map<String, Object> _respostas = {
    for (final q in widget.formulario.perguntas)
      if (q.tipo == 'numero') q.id: 1,
  };
  late final Map<String, TextEditingController> _textos = {
    for (final q in widget.formulario.perguntas)
      if (q.tipo == 'texto') q.id: TextEditingController(),
  };

  bool _respondida(PerguntaPedido q) {
    if (q.tipo == 'texto') return (_textos[q.id]?.text.trim() ?? '').isNotEmpty;
    final r = _respostas[q.id];
    if (r == null) return false;
    if (r is List) return r.isNotEmpty;
    return true;
  }

  String? _erroPergunta(PerguntaPedido q) =>
      _tentou && q.obrigatoria && !_respondida(q) ? 'Responda esta pergunta.' : null;

  bool get _perguntasOk =>
      widget.formulario.perguntas.every((q) => !q.obrigatoria || _respondida(q));

  Map<String, Object> get _respostasParaEnviar => {
        for (final q in widget.formulario.perguntas)
          if (_respondida(q))
            q.id: q.tipo == 'texto' ? _textos[q.id]!.text.trim() : _respostas[q.id]!,
      };
  late int _quantidade = widget.formulario.quantidadeInicial;
  late String _voltagem = widget.formulario.voltagemInicial;

  _ModoPrazo _modoPrazo = _ModoPrazo.flexivel;
  late DateTime _dataPrazo = _agora().add(const Duration(days: 7));
  late FaixaPreco? _faixa = widget.formulario.faixas.firstOrNull;
  late final _descricao = TextEditingController(text: widget.formulario.descricaoInicial);
  final _controladorValorProprio = TextEditingController();
  late bool _informarValorProprio = widget.formulario.faixas.isEmpty;
  String? _erroValor;
  var _tentou = false;
  var _enviando = false;
  final _fotosNovas = <String>[];
  CidadeOpcao? _cidade;

  final _scroll = ScrollController();
  late final Map<String, GlobalKey> _keyPerguntas = {
    for (final q in widget.formulario.perguntas) q.id: GlobalKey(),
  };
  final _keyServicos = GlobalKey();
  final _keyDescricao = GlobalKey();
  final _keyValorProprio = GlobalKey();
  final _keyCidade = GlobalKey();
  final _keyCep = GlobalKey();
  final _keyRua = GlobalKey();
  final _keyNumero = GlobalKey();
  final _keyBairro = GlobalKey();

  final _focoDescricao = FocusNode();
  final _focoValorProprio = FocusNode();
  final _focoCep = FocusNode();
  final _focoRua = FocusNode();
  final _focoNumero = FocusNode();
  final _focoBairro = FocusNode();

  /// Presencial (padrão) ou remoto. Remoto só existe quando a categoria aceita.
  var _modalidade = Modalidade.presencial;
  final _rua = TextEditingController();
  final _numero = TextEditingController();
  final _complemento = TextEditingController();
  final _bairro = TextEditingController();
  final _cep = TextEditingController();
  final _referencia = TextEditingController();

  bool get _presencial => !widget.formulario.aceitaRemoto || _modalidade == Modalidade.presencial;

  /// Rua, número, bairro e CEP são obrigatórios no presencial: sem eles o profissional contratado
  /// não sabe aonde ir.
  String? _erroEndereco(TextEditingController c, String nome) =>
      _tentou && _presencial && c.text.trim().isEmpty ? 'Informe $nome.' : null;

  String? get _erroCep {
    if (!(_tentou && _presencial)) return null;
    final digitos = _cep.text.replaceAll(RegExp(r'\D'), '');
    return digitos.length == 8 ? null : 'CEP inválido. Use 8 dígitos.';
  }

  bool get _enderecoCompleto =>
      _rua.text.trim().isNotEmpty &&
      _numero.text.trim().isNotEmpty &&
      _bairro.text.trim().isNotEmpty &&
      _cep.text.replaceAll(RegExp(r'\D'), '').length == 8;

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.formulario.cidades.isNotEmpty) {
      _cidade = widget.formulario.cidades.first;
    }
    if (widget.enderecosSalvos.isNotEmpty) {
      final principal = widget.enderecosSalvos.where((e) => e.principal).firstOrNull ??
          widget.enderecosSalvos.first;
      _aplicarEnderecoSalvo(principal, atualizarEstado: false);
    }
  }

  void _aplicarEnderecoSalvo(EnderecoSalvo end, {bool atualizarEstado = true}) {
    void preencher() {
      final digitos = end.cep.replaceAll(RegExp(r'\D'), '');
      _cep.text =
          digitos.length == 8 ? '${digitos.substring(0, 5)}-${digitos.substring(5)}' : end.cep;
      _rua.text = end.logradouro;
      _numero.text = end.numero;
      _complemento.text = end.complemento ?? '';
      _bairro.text = end.bairro;
      _selecionarCidadePorNome(end.cidade);
    }

    if (atualizarEstado) {
      setState(preencher);
    } else {
      preencher();
    }
  }

  void _selecionarCidadePorNome(String nomeCidade) {
    final alvo = normalizarTextoBusca(nomeCidade);
    if (alvo.isEmpty) return;
    for (final c in widget.formulario.cidades) {
      if (normalizarTextoBusca(c.nome) == alvo) {
        _cidade = c;
        return;
      }
    }
  }

  void _aplicarCep(EnderecoPorCep end) {
    setState(() {
      if (end.logradouro.trim().isNotEmpty) _rua.text = end.logradouro;
      if (end.bairro.trim().isNotEmpty) _bairro.text = end.bairro;
      _selecionarCidadePorNome(end.cidade);
    });
  }

  void _selecionarModoPrazo(_ModoPrazo modo) {
    setState(() {
      _modoPrazo = modo;
      final hoje = _agora();
      _dataPrazo = switch (modo) {
        _ModoPrazo.flexivel => hoje.add(const Duration(days: 7)),
        _ModoPrazo.dataLimite => hoje.add(const Duration(days: 2)),
        _ModoPrazo.urgente => hoje,
      };
    });
  }

  static String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String? get _erroPrazo => null;

  Future<void> _escolherDataPrazo() async {
    final hoje = _agora();
    final inicio = DateTime(hoje.year, hoje.month, hoje.day);
    final data = await showDatePicker(
      context: context,
      initialDate: _dataPrazo,
      firstDate: inicio,
      lastDate: inicio.add(const Duration(days: 365)),
      helpText: _modoPrazo == _ModoPrazo.dataLimite
          ? 'Escolha a data limite'
          : 'Sugira uma data aproximada',
    );
    if (data != null && mounted) setState(() => _dataPrazo = data);
  }

  // Remoto: sem cartão de cidade/endereço; a cidade padrão vai no envio (`_cidade ?? primeira`).
  bool get _exigeCidade => widget.formulario.cidades.isNotEmpty && _presencial;

  String? get _erroCidade =>
      _tentou && _exigeCidade && _cidade == null ? 'Escolha a cidade onde será o serviço.' : null;

  Future<void> _escolherCidade() async {
    final escolhida = await showModalBottomSheet<CidadeOpcao>(
      context: context,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EspacosTrato.x4,
                EspacosTrato.x4,
                EspacosTrato.x4,
                EspacosTrato.x2,
              ),
              child: Text('Onde será o serviço?', style: TipografiaTrato.titulo),
            ),
            for (final c in widget.formulario.cidades)
              ListTile(
                leading: Icon(
                  c.id == _cidade?.id ? Icons.check_circle : Icons.location_city_outlined,
                  color: CoresTrato.petroleo,
                ),
                title: Text(c.rotulo),
                onTap: () => Navigator.of(folha).pop(c),
              ),
            const SizedBox(height: EspacosTrato.x2),
          ],
        ),
      ),
    );
    if (escolhida != null && mounted) setState(() => _cidade = escolhida);
  }

  static int? _lerCentavos(String texto) {
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;
    if (limpo.contains(',')) {
      final semMilhar = limpo.replaceAll('.', '').replaceAll(',', '.');
      return Dinheiro.lerCentavos(semMilhar);
    }
    if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(limpo)) {
      final semPonto = limpo.replaceAll('.', '');
      return Dinheiro.lerCentavos(semPonto);
    }
    return Dinheiro.lerCentavos(limpo);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _descricao.dispose();
    _controladorValorProprio.dispose();
    for (final c in _textos.values) {
      c.dispose();
    }
    for (final c in [_rua, _numero, _complemento, _bairro, _cep, _referencia]) {
      c.dispose();
    }
    for (final f in [
      _focoDescricao,
      _focoValorProprio,
      _focoCep,
      _focoRua,
      _focoNumero,
      _focoBairro,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _podeAdicionarFoto => widget.aoCapturarFoto != null || widget.aoAdicionarFoto != null;

  Future<void> _adicionarFoto() async {
    final captura = widget.aoCapturarFoto;
    if (captura == null) return widget.aoAdicionarFoto?.call();
    final ref = await captura();
    if (ref != null && mounted) setState(() => _fotosNovas.add(ref));
  }

  String? get _erroServicos =>
      _tentou && _servicos.isEmpty ? 'Escolha pelo menos um serviço.' : null;

  String? get _erroDescricao =>
      _tentou && _descricao.text.trim().isEmpty ? 'Descreva o que precisa ser feito.' : null;

  Future<void> _enviar() async {
    if (_enviando) return;
    String? errValor;
    if (_informarValorProprio) {
      final c = _lerCentavos(_controladorValorProprio.text);
      if (c == null || c <= 0) {
        errValor = 'Informe um valor maior que zero.';
      } else {
        _faixa = FaixaPreco(minimoCentavos: c, maximoCentavos: c);
      }
    }
    setState(() {
      _tentou = true;
      _erroValor = errValor;
    });

    final faltamPerguntas = _temPerguntas && !_perguntasOk;
    final faltamServicos = !_temPerguntas && _servicos.isEmpty;
    final faltaDesc = _descricao.text.trim().isEmpty;
    final faltaValor = _informarValorProprio && errValor != null;
    final faltaCidade = _exigeCidade && _cidade == null;
    final faltaEndereco = _presencial && !_enderecoCompleto;

    if (faltamPerguntas ||
        faltamServicos ||
        faltaDesc ||
        faltaValor ||
        faltaCidade ||
        _erroPrazo != null ||
        faltaEndereco) {
      focarPrimeiroErro([
        if (_temPerguntas)
          for (final q in widget.formulario.perguntas)
            if (q.obrigatoria)
              EntradaCampoErro(
                key: _keyPerguntas[q.id]!,
                temErro: () => !_respondida(q),
              ),
        if (!_temPerguntas) EntradaCampoErro(key: _keyServicos, temErro: () => _servicos.isEmpty),
        EntradaCampoErro(
          key: _keyDescricao,
          focusNode: _focoDescricao,
          temErro: () => _descricao.text.trim().isEmpty,
        ),
        if (_informarValorProprio)
          EntradaCampoErro(
            key: _keyValorProprio,
            focusNode: _focoValorProprio,
            temErro: () => _erroValor != null,
          ),
        if (_exigeCidade) EntradaCampoErro(key: _keyCidade, temErro: () => _cidade == null),
        if (_presencial) ...[
          EntradaCampoErro(
            key: _keyCep,
            focusNode: _focoCep,
            temErro: () => _cep.text.replaceAll(RegExp(r'\D'), '').length != 8,
          ),
          EntradaCampoErro(
            key: _keyRua,
            focusNode: _focoRua,
            temErro: () => _rua.text.trim().isEmpty,
          ),
          EntradaCampoErro(
            key: _keyNumero,
            focusNode: _focoNumero,
            temErro: () => _numero.text.trim().isEmpty,
          ),
          EntradaCampoErro(
            key: _keyBairro,
            focusNode: _focoBairro,
            temErro: () => _bairro.text.trim().isEmpty,
          ),
        ],
      ]);
      return;
    }

    final rascunho = RascunhoPedido(
      // Com perguntas da categoria, o título do pedido é o nome da categoria.
      servicos: _temPerguntas
          ? [widget.formulario.categoria]
          : [
              for (final s in widget.formulario.servicos)
                if (_servicos.contains(s)) s
            ],
      respostas: _temPerguntas ? _respostasParaEnviar : const {},
      quantidade: _quantidade,
      voltagem: _voltagem,
      descricao: _descricao.text.trim(),
      prazo: switch (_modoPrazo) {
        _ModoPrazo.flexivel => 'Flexível · ${_formatarData(_dataPrazo)}',
        _ModoPrazo.dataLimite => 'Data limite · ${_formatarData(_dataPrazo)}',
        _ModoPrazo.urgente => 'Urgente · ${_formatarData(_dataPrazo)}',
      },
      prazoDesejado: _dataPrazo,
      urgente: _modoPrazo == _ModoPrazo.urgente,
      faixa: _faixa ?? const FaixaPreco(minimoCentavos: 0, maximoCentavos: 0),
      fotos: List.of(_fotosNovas),
      categoriaId: widget.formulario.categoriaId,
      // Sem cidade carregada o pedido não abre (o repositório avisa); nada de cidade inventada.
      cidadeId: _cidade?.id ?? widget.formulario.cidades.firstOrNull?.id,
      modalidade: _presencial ? Modalidade.presencial : Modalidade.remoto,
      profissionalConvidadoId: widget.profissionalConvidadoId,
      profissionalConvidadoNome: widget.profissionalConvidadoNome,
      endereco: _presencial
          ? EnderecoRascunho(
              logradouro: _rua.text,
              numero: _numero.text,
              bairro: _bairro.text,
              cep: _cep.text,
              complemento: _complemento.text,
              referencia: _referencia.text,
            )
          : null,
    );
    setState(() => _enviando = true);
    try {
      await widget.aoEnviar?.call(rascunho);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  static String _rotuloFaixa(FaixaPreco f) => f.minimoCentavos == f.maximoCentavos
      ? formatarReais(f.minimoCentavos)
      : '${formatarReais(f.minimoCentavos).replaceAll(',00', '')} a '
          '${formatarReais(f.maximoCentavos).replaceAll(',00', '')}';

  @override
  Widget build(BuildContext context) {
    final f = widget.formulario;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return EstruturaPedido(
      scrollController: _scroll,
      tituloBarra: 'Novo pedido',
      rodape: BotaoPrimario(
        texto: 'Enviar pedido',
        carregando: _enviando,
        aoTocar: _enviando ? null : _enviar,
      ),
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Text('Conte o que precisa', style: TipografiaTrato.tituloGrande),
        if ((widget.profissionalConvidadoNome ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x3),
          Container(
            key: const Key('banner-profissional-convidado'),
            padding: const EdgeInsets.all(EspacosTrato.x3),
            decoration: BoxDecoration(
              color: CoresTrato.azulSuave,
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_pin_outlined, size: 20, color: CoresTrato.azulTexto),
                const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: Text(
                    'Pedido direto para ${widget.profissionalConvidadoNome!.trim()}. Ele será avisado primeiro.',
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: CoresTrato.azulTexto,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: EspacosTrato.x2),
        Row(
          children: [
            Icon(f.icone, size: 22, color: CoresTrato.petroleo),
            const SizedBox(width: EspacosTrato.x2),
            Expanded(child: Text(f.categoria, style: secundario)),
            if (widget.aoTrocarCategoria != null)
              BotaoLink(texto: 'Trocar', aoTocar: widget.aoTrocarCategoria),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (_temPerguntas)
          for (final q in f.perguntas) ...[
            KeyedSubtree(
              key: _keyPerguntas[q.id],
              child: _PerguntaCategoria(
                key: ValueKey('pergunta-${q.id}'),
                pergunta: q,
                resposta: _respostas[q.id],
                controlador: _textos[q.id],
                erro: _erroPergunta(q),
                aoMudar: (v) => setState(() {
                  if (v == null) {
                    _respostas.remove(q.id);
                  } else {
                    _respostas[q.id] = v;
                  }
                }),
                aoDigitar: () => setState(() {}),
              ),
            ),
            const SizedBox(height: EspacosTrato.x5),
          ]
        else ...[
          KeyedSubtree(
            key: _keyServicos,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RotuloSecao('O que precisa ser feito?'),
                const SizedBox(height: EspacosTrato.x3),
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x2,
                  children: [
                    for (final s in f.servicos)
                      ChipOpcao(
                        texto: s,
                        marcado: _servicos.contains(s),
                        aoTocar: () => setState(
                            () => _servicos.contains(s) ? _servicos.remove(s) : _servicos.add(s)),
                      ),
                  ],
                ),
                if (_erroServicos != null) _MensagemErro(_erroServicos!),
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x5),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.perguntaQuantidade, style: TipografiaTrato.corpoForte),
                    Text(f.dicaQuantidade, style: secundario),
                  ],
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              _Contador(valor: _quantidade, aoMudar: (v) => setState(() => _quantidade = v)),
            ],
          ),
        ],
        if (f.voltagens.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x5),
          RotuloSecao(f.perguntaVoltagem),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              for (var i = 0; i < f.voltagens.length; i++) ...[
                if (i > 0) const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: _OpcaoRadio(
                    texto: f.voltagens[i],
                    marcada: f.voltagens[i] == _voltagem,
                    aoTocar: () => setState(() => _voltagem = f.voltagens[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        KeyedSubtree(
          key: _keyDescricao,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RotuloSecao('Descreva o problema'),
              const SizedBox(height: EspacosTrato.x3),
              TextField(
                controller: _descricao,
                focusNode: _focoDescricao,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                style: TipografiaTrato.corpo,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(errorText: _erroDescricao),
              ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x5),
        const RotuloSecao('Fotos'),
        const SizedBox(height: EspacosTrato.x3),
        LayoutBuilder(
          builder: (context, c) {
            final tamanho = ((c.maxWidth - 3 * EspacosTrato.x3) / 4).clamp(64.0, 120.0);
            return Wrap(
              spacing: EspacosTrato.x3,
              runSpacing: EspacosTrato.x3,
              children: [
                for (final foto in f.fotos)
                  SizedBox.square(dimension: tamanho, child: _FotoReservada(foto)),
                for (var i = 0; i < _fotosNovas.length; i++)
                  SizedBox.square(
                    dimension: tamanho,
                    child: _FotoReservada(
                      '[Foto ${f.fotos.length + i + 1}]',
                      referencia: _fotosNovas[i],
                      aoRemover: () => setState(() => _fotosNovas.removeAt(i)),
                    ),
                  ),
                if (f.fotos.length + _fotosNovas.length < _maxFotos && _podeAdicionarFoto)
                  SizedBox.square(
                    dimension: tamanho,
                    child: _AdicionarFoto(aoTocar: _adicionarFoto),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: EspacosTrato.x5),
        const RotuloSecao('Quando precisa?'),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          children: [
            Expanded(
              child: _OpcaoRadio(
                texto: 'Flexível (sem data fixa)',
                marcada: _modoPrazo == _ModoPrazo.flexivel,
                aoTocar: () => _selecionarModoPrazo(_ModoPrazo.flexivel),
              ),
            ),
            const SizedBox(width: EspacosTrato.x2),
            Expanded(
              child: _OpcaoRadio(
                texto: 'Tenho data limite',
                marcada: _modoPrazo == _ModoPrazo.dataLimite,
                aoTocar: () => _selecionarModoPrazo(_ModoPrazo.dataLimite),
              ),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        _OpcaoRadio(
          texto: 'É urgente (para hoje)',
          marcada: _modoPrazo == _ModoPrazo.urgente,
          aoTocar: () => _selecionarModoPrazo(_ModoPrazo.urgente),
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (_modoPrazo == _ModoPrazo.urgente)
          Text(
            'Pedidos urgentes vão direto para atendimento rápido e não usam reserva de 48h.',
            style: secundario,
          )
        else ...[
          Text(
            _modoPrazo == _ModoPrazo.dataLimite
                ? 'Escolha a data máxima para o serviço:'
                : 'Se quiser, sugira uma data aproximada:',
            style: secundario,
          ),
          const SizedBox(height: EspacosTrato.x2),
          BotaoSecundario(
            texto: _formatarData(_dataPrazo),
            aoTocar: _escolherDataPrazo,
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        const RotuloSecao('Quanto pensa gastar?'),
        const SizedBox(height: EspacosTrato.x3),
        if (f.faixas.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: _OpcaoRadio(
                  texto: 'Faixa estimada',
                  marcada: !_informarValorProprio,
                  aoTocar: () {
                    setState(() {
                      _informarValorProprio = false;
                      _erroValor = null;
                      if (_faixa == null || _faixa!.minimoCentavos == _faixa!.maximoCentavos) {
                        _faixa = f.faixas.first;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: _OpcaoRadio(
                  texto: 'Informar meu valor',
                  marcada: _informarValorProprio,
                  aoTocar: () {
                    setState(() {
                      _informarValorProprio = true;
                      if (_controladorValorProprio.text.trim().isNotEmpty) {
                        final c = _lerCentavos(_controladorValorProprio.text);
                        if (c != null && c > 0) {
                          _faixa = FaixaPreco(minimoCentavos: c, maximoCentavos: c);
                        }
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (f.faixas.isNotEmpty && !_informarValorProprio) ...[
          _CampoLista<FaixaPreco>(
            rotulo: 'Escolha uma faixa',
            valor: _faixa ?? f.faixas.first,
            opcoes: f.faixas,
            texto: _rotuloFaixa,
            aoMudar: (v) => setState(() => _faixa = v),
          ),
        ] else ...[
          KeyedSubtree(
            key: _keyValorProprio,
            child: CampoTrato(
              rotulo: 'Valor que pretende gastar',
              controlador: _controladorValorProprio,
              foco: _focoValorProprio,
              dica: 'Ex.: 300,00',
              prefixo: 'R\$ ',
              teclado: const TextInputType.numberWithOptions(decimal: true),
              formatadores: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              erro: _tentou ? _erroValor : null,
              ajuda: 'Os profissionais receberão o seu valor como estimativa inicial.',
              aoMudar: (v) {
                final c = _lerCentavos(v);
                setState(() {
                  if (c != null && c > 0) {
                    _erroValor = null;
                    _faixa = FaixaPreco(minimoCentavos: c, maximoCentavos: c);
                  } else {
                    _erroValor = 'Informe um valor maior que zero.';
                  }
                });
              },
            ),
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        if (f.aceitaRemoto) ...[
          const RotuloSecao('Como será o serviço?'),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              for (final (i, m) in Modalidade.values.indexed) ...[
                if (i > 0) const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: _OpcaoRadio(
                    texto: m.rotulo,
                    marcada: _modalidade == m,
                    aoTocar: () => setState(() => _modalidade = m),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            _presencial
                ? 'O profissional vai até o local. Você informa o endereço abaixo.'
                : 'Atendimento à distância: você não precisa informar endereço e combina tudo '
                    'pelo chat.',
            style: secundario,
          ),
          const SizedBox(height: EspacosTrato.x5),
        ],
        if (!_presencial)
          const SizedBox.shrink()
        else if (_exigeCidade)
          KeyedSubtree(
            key: _keyCidade,
            child: InkWell(
              borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
              onTap: _escolherCidade,
              child: CartaoTrato(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined, color: CoresTrato.petroleo),
                    const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _cidade?.rotulo ?? 'Selecionar cidade',
                            style: TipografiaTrato.corpoForte,
                          ),
                          Text(f.avisoEndereco, style: secundario),
                          if (_erroCidade != null) _MensagemErro(_erroCidade!),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down, color: CoresTrato.petroleo),
                  ],
                ),
              ),
            ),
          )
        else
          CartaoTrato(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, color: CoresTrato.petroleo),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(f.endereco, style: TipografiaTrato.corpoForte)),
                          if (widget.aoMudarEndereco != null)
                            BotaoLink(texto: 'Mudar', aoTocar: widget.aoMudarEndereco),
                        ],
                      ),
                      Text(f.avisoEndereco, style: secundario),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_presencial) ...[
          const SizedBox(height: EspacosTrato.x5),
          const RotuloSecao('Endereço do serviço'),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Só o profissional que você contratar vê o endereço completo.',
            style: secundario,
          ),
          ValueListenableBuilder<int>(
            valueListenable: LocalizacaoDoPedido.negacoes,
            builder: (_, __, ___) => LocalizacaoDoPedido.naoPerguntarMais
                ? Padding(
                    padding: const EdgeInsets.only(top: EspacosTrato.x1),
                    child: Text(
                      'Sem localização: o profissional vê só o bairro.',
                      key: const ValueKey('sem-localizacao'),
                      style: secundario,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (widget.enderecosSalvos.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x3),
            Wrap(
              spacing: EspacosTrato.x2,
              runSpacing: EspacosTrato.x2,
              children: [
                for (final saved in widget.enderecosSalvos)
                  ActionChip(
                    avatar: const Icon(Icons.home_outlined, size: 18, color: CoresTrato.petroleo),
                    label: Text(saved.apelido.isNotEmpty ? saved.apelido : 'Endereço salvo'),
                    backgroundColor: CoresTrato.superficie,
                    side: const BorderSide(color: CoresTrato.borda),
                    onPressed: () => _aplicarEnderecoSalvo(saved),
                  ),
              ],
            ),
          ],
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyCep,
            child: CampoCepAutoPreenchimento(
              key: const ValueKey('campo-cep'),
              controlador: _cep,
              servico: widget.servicoCep,
              foco: _focoCep,
              proximoFoco: _focoNumero,
              erro: _erroCep,
              aoAlterar: () => setState(() {}),
              aoEncontrar: _aplicarCep,
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyRua,
            child: CampoTrato(
              key: const ValueKey('campo-rua'),
              rotulo: 'Rua',
              controlador: _rua,
              foco: _focoRua,
              aoMudar: (_) => setState(() {}),
              erro: _erroEndereco(_rua, 'a rua'),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: _keyNumero,
                  child: CampoTrato(
                    key: const ValueKey('campo-numero'),
                    rotulo: 'Número',
                    controlador: _numero,
                    foco: _focoNumero,
                    aoMudar: (_) => setState(() {}),
                    erro: _erroEndereco(_numero, 'o número'),
                  ),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: CampoTrato(
                  key: const ValueKey('campo-complemento'),
                  rotulo: 'Complemento',
                  controlador: _complemento,
                  dica: 'Apto, bloco (opcional)',
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyBairro,
            child: CampoTrato(
              key: const ValueKey('campo-bairro'),
              rotulo: 'Bairro',
              controlador: _bairro,
              foco: _focoBairro,
              aoMudar: (_) => setState(() {}),
              erro: _erroEndereco(_bairro, 'o bairro'),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(
            key: const ValueKey('campo-referencia'),
            rotulo: 'Ponto de referência',
            controlador: _referencia,
            dica: 'Perto da praça, portão azul... (opcional)',
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        AvisoInfo(texto: TextSpan(text: f.avisoPrazo)),
      ],
    );
  }
}

class _MensagemErro extends StatelessWidget {
  const _MensagemErro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x2),
        child:
            Text(texto, style: TipografiaTrato.legenda.copyWith(color: CoresTrato.vermelhoTexto)),
      );
}

/// "− 2 +", mínimo 1.
class _Contador extends StatelessWidget {
  const _Contador({required this.valor, required this.aoMudar});

  final int valor;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CoresTrato.superficie,
        border: Border.all(color: CoresTrato.borda),
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Diminuir',
            icon: const Icon(Icons.remove),
            onPressed: valor > 1 ? () => aoMudar(valor - 1) : null,
          ),
          SizedBox(
            width: EspacosTrato.x6,
            child: Text('$valor', textAlign: TextAlign.center, style: TipografiaTrato.corpoForte),
          ),
          IconButton(
            tooltip: 'Aumentar',
            icon: const Icon(Icons.add),
            onPressed: () => aoMudar(valor + 1),
          ),
        ],
      ),
    );
  }
}

class _OpcaoRadio extends StatelessWidget {
  const _OpcaoRadio({required this.texto, required this.marcada, required this.aoTocar});

  final String texto;
  final bool marcada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raio);
    return Semantics(
      button: true,
      selected: marcada,
      child: Material(
        color: marcada ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: marcada ? CoresTrato.petroleo : CoresTrato.borda,
            width: marcada ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x3,
              vertical: EspacosTrato.x4,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: EspacosTrato.x4,
                    color: CoresTrato.petroleo,
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  Text(
                    texto,
                    maxLines: 1,
                    style: TipografiaTrato.corpoForte.copyWith(
                      fontWeight: marcada ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FotoReservada extends StatelessWidget {
  const _FotoReservada(this.rotulo, {this.referencia, this.aoRemover});

  final String rotulo;
  final String? referencia;
  final VoidCallback? aoRemover;

  @override
  Widget build(BuildContext context) {
    final imagemReal = construirImagemReal(referencia);
    final cartao = ToquePreviewImagem(
      referencia: referencia ?? rotulo,
      legenda: rotulo,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          clipBehavior: imagemReal != null ? Clip.antiAlias : Clip.none,
          padding: imagemReal != null ? EdgeInsets.zero : const EdgeInsets.all(EspacosTrato.x2),
          alignment: Alignment.bottomLeft,
          decoration: BoxDecoration(
            color: CoresTrato.azulClaro,
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
          ),
          child: imagemReal != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    imagemReal,
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: CoresTrato.overlayFoto,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          rotulo,
                          style: TipografiaTrato.legenda.copyWith(
                            color: CoresTrato.textoSobreFoto,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    rotulo,
                    style: TipografiaTrato.corpoPequeno.copyWith(
                      color: CoresTrato.petroleo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ),
    );
    if (aoRemover == null) return cartao;
    return Stack(
      children: [
        Positioned.fill(child: cartao),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: CoresTrato.overlayFoto,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: aoRemover,
              child: const Tooltip(
                message: 'Remover foto',
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: CoresTrato.textoSobreFoto),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdicionarFoto extends StatelessWidget {
  const _AdicionarFoto({required this.aoTocar});

  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _BordaTracejada(),
        child: Semantics(
          button: true,
          label: 'Adicionar foto',
          child: InkWell(
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
            onTap: aoTocar,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_camera_outlined, color: CoresTrato.petroleo),
                    const SizedBox(height: EspacosTrato.x2),
                    Text('Adicionar', style: TipografiaTrato.corpoForte),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BordaTracejada extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final caminho = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(EspacosTrato.raio)),
      );
    final pintura = Paint()
      ..color = CoresTrato.borda
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metrica in caminho.computeMetrics()) {
      for (var d = 0.0; d < metrica.length; d += 8) {
        canvas.drawPath(metrica.extractPath(d, d + 4), pintura);
      }
    }
  }

  @override
  bool shouldRepaint(_BordaTracejada antigo) => false;
}

class _CampoLista<T> extends StatelessWidget {
  const _CampoLista({
    required this.rotulo,
    required this.valor,
    required this.opcoes,
    required this.texto,
    required this.aoMudar,
  });

  final String rotulo;
  final T valor;
  final List<T> opcoes;
  final String Function(T) texto;
  final ValueChanged<T> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rotulo, maxLines: 1, style: TipografiaTrato.corpoForte),
        ),
        const SizedBox(height: EspacosTrato.x2),
        DropdownButtonFormField<T>(
          initialValue: valor,
          isExpanded: true,
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.petroleo),
          items: [
            for (final o in opcoes)
              DropdownMenuItem<T>(
                value: o,
                child: Text(texto(o), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) aoMudar(v);
          },
        ),
      ],
    );
  }
}

/// Uma pergunta da categoria, desenhada pelo tipo que o admin escolheu.
class _PerguntaCategoria extends StatelessWidget {
  const _PerguntaCategoria({
    super.key,
    required this.pergunta,
    required this.resposta,
    required this.controlador,
    required this.erro,
    required this.aoMudar,
    required this.aoDigitar,
  });

  final PerguntaPedido pergunta;
  final Object? resposta;
  final TextEditingController? controlador;
  final String? erro;

  /// Nova resposta (nula = sem resposta).
  final ValueChanged<Object?> aoMudar;
  final VoidCallback aoDigitar;

  @override
  Widget build(BuildContext context) {
    final q = pergunta;
    final titulo = q.obrigatoria ? q.texto : '${q.texto} (opcional)';
    final Widget campo = switch (q.tipo) {
      'escolha_unica' => Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final o in q.opcoes)
              ChipOpcao(
                texto: o,
                marcado: resposta == o,
                aoTocar: () => aoMudar(resposta == o ? null : o),
              ),
          ],
        ),
      'multipla' => Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final o in q.opcoes)
              ChipOpcao(
                texto: o,
                marcado: resposta is List && (resposta! as List).contains(o),
                aoTocar: () {
                  final atual = [...(resposta is List ? resposta! as List : const [])];
                  atual.contains(o) ? atual.remove(o) : atual.add(o);
                  aoMudar(atual.isEmpty
                      ? null
                      : [
                          for (final x in q.opcoes)
                            if (atual.contains(x)) x
                        ]);
                },
              ),
          ],
        ),
      'sim_nao' => Wrap(
          spacing: EspacosTrato.x2,
          children: [
            ChipOpcao(
                texto: 'Sim',
                marcado: resposta == true,
                aoTocar: () => aoMudar(resposta == true ? null : true)),
            ChipOpcao(
                texto: 'Não',
                marcado: resposta == false,
                aoTocar: () => aoMudar(resposta == false ? null : false)),
          ],
        ),
      'numero' => Align(
          alignment: Alignment.centerLeft,
          child: _Contador(
            valor: resposta is int ? resposta! as int : 1,
            aoMudar: aoMudar,
          ),
        ),
      _ => TextField(
          controller: controlador,
          onChanged: (_) => aoDigitar(),
          maxLength: 200,
          decoration: const InputDecoration(counterText: ''),
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RotuloSecao(titulo),
        const SizedBox(height: EspacosTrato.x3),
        campo,
        if (erro != null) _MensagemErro(erro!),
      ],
    );
  }
}
