import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho;
import '../profissional_apoio/apoio.dart';
import 'modelos.dart';

/// Callback que envia a conta ao backend e devolve a versão salva/mascarada.
typedef SalvarContaRecebimento = Future<ContaRecebimento> Function({
  required String tipoPix,
  required String chavePix,
  String? bancoCodigo,
  String? bancoNome,
  String? agencia,
  String? conta,
  String? tipoConta,
});

/// Tela para o profissional cadastrar ou atualizar sua chave Pix e conta bancária de repasse.
class ContaRecebimentoTela extends StatefulWidget {
  const ContaRecebimentoTela({
    super.key,
    required this.inicial,
    required this.aoSalvar,
    this.carregarProximaLiberacao,
  });

  final ContaRecebimento inicial;
  final SalvarContaRecebimento aoSalvar;

  /// Data do próximo repasse (`proxima_liberacao_em`), se o backend informar. Falha = sem data.
  final Future<DateTime?> Function()? carregarProximaLiberacao;

  @override
  State<ContaRecebimentoTela> createState() => _ContaRecebimentoTelaState();
}

class _ContaRecebimentoTelaState extends State<ContaRecebimentoTela> {
  DateTime? _proximaLiberacao;

  @override
  void initState() {
    super.initState();
    _carregarProximaLiberacao();
  }

  Future<void> _carregarProximaLiberacao() async {
    final carregar = widget.carregarProximaLiberacao;
    if (carregar == null) return;
    try {
      final data = await carregar();
      if (mounted && data != null) setState(() => _proximaLiberacao = data);
    } on Object {
      // Sem a data o texto geral continua valendo; falha aqui não atrapalha a tela.
    }
  }

  static const _tiposPix = <String, String>{
    'cpf': 'CPF (titular)',
    'cnpj': 'CNPJ',
    'email': 'E-mail',
    'telefone': 'Celular com DDD',
    'aleatoria': 'Chave aleatória',
  };

  late String _tipoPix = _tiposPix.containsKey(widget.inicial.tipoPix)
      ? widget.inicial.tipoPix!
      : 'cpf';
  late final _chave = TextEditingController(text: widget.inicial.chavePix ?? '');
  late bool _incluirBanco = (widget.inicial.conta ?? '').isNotEmpty;
  late final _bancoNome = TextEditingController(text: widget.inicial.bancoNome ?? '');
  late final _bancoCodigo = TextEditingController(text: widget.inicial.bancoCodigo ?? '');
  late final _agencia = TextEditingController(text: widget.inicial.agencia ?? '');
  late final _conta = TextEditingController(text: widget.inicial.conta ?? '');
  late String _tipoConta =
      widget.inicial.tipoConta == 'poupanca' ? 'poupanca' : 'corrente';

  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _chave.dispose();
    _bancoNome.dispose();
    _bancoCodigo.dispose();
    _agencia.dispose();
    _conta.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    final chave = _chave.text.trim();
    if (chave.isEmpty) {
      setState(() => _erro = 'Informe a chave Pix para receber os repasses.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final salva = await widget.aoSalvar(
        tipoPix: _tipoPix,
        chavePix: chave,
        bancoCodigo: _incluirBanco ? _bancoCodigo.text.trim() : null,
        bancoNome: _incluirBanco ? _bancoNome.text.trim() : null,
        agencia: _incluirBanco ? _agencia.text.trim() : null,
        conta: _incluirBanco ? _conta.text.trim() : null,
        tipoConta: _incluirBanco ? _tipoConta : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(salva);
    } on ErroTrato catch (erro) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = erro.mensagem;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar a conta agora. Tente de novo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conta de recebimento')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
              child: ConteudoResponsivo(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receba os repasses via Pix',
                      style: TipografiaTrato.tituloGrande,
                    ),
                    const SizedBox(height: EspacosTrato.x2),
                    Text(
                      _proximaLiberacao == null
                          ? 'Quando o prazo de liberação de um serviço concluído terminar, '
                              'o repasse é enviado para a conta do mesmo titular abaixo.'
                          : 'Próximo repasse previsto: ${diaMesDoAparelho(_proximaLiberacao!)}, '
                              'para a conta do mesmo titular abaixo.',
                      key: const Key('texto-repasse'),
                      style: TipografiaTrato.corpo
                          .copyWith(color: context.cores.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x2),
                    Text(
                      'Para proteger seu pagamento contra fraude, a conta precisa estar no seu nome.',
                      style: TipografiaTrato.corpoPequeno
                          .copyWith(color: context.cores.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x5),
                    Text('Tipo de chave Pix', style: TipografiaTrato.corpoForte),
                    const SizedBox(height: EspacosTrato.x2),
                    DropdownButtonFormField<String>(
                      initialValue: _tipoPix,
                      isExpanded: true,
                      items: [
                        for (final e in _tiposPix.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (valor) {
                        if (valor != null) setState(() => _tipoPix = valor);
                      },
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    CampoTrato(
                      rotulo: 'Chave Pix',
                      controlador: _chave,
                      dica: _tipoPix == 'cpf'
                          ? 'Somente o CPF do titular da conta Trato'
                          : 'Digite a chave cadastrada no seu banco',
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Incluir dados bancários (opcional)',
                        style: TipografiaTrato.corpoForte,
                      ),
                      subtitle: Text(
                        'Útil como respaldo para transferências TED',
                        style: TipografiaTrato.legenda,
                      ),
                      value: _incluirBanco,
                      onChanged: (v) => setState(() => _incluirBanco = v),
                    ),
                    if (_incluirBanco) ...[
                      const SizedBox(height: EspacosTrato.x3),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CampoTrato(
                              rotulo: 'Banco',
                              controlador: _bancoNome,
                              dica: 'Ex.: Itaú, Nubank',
                            ),
                          ),
                          const SizedBox(width: EspacosTrato.x3),
                          Expanded(
                            child: CampoTrato(
                              rotulo: 'Código',
                              controlador: _bancoCodigo,
                              teclado: TextInputType.number,
                              dica: 'Ex.: 341',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: EspacosTrato.x4),
                      Row(
                        children: [
                          Expanded(
                            child: CampoTrato(
                              rotulo: 'Agência',
                              controlador: _agencia,
                              teclado: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: EspacosTrato.x3),
                          Expanded(
                            flex: 2,
                            child: CampoTrato(
                              rotulo: 'Conta com dígito',
                              controlador: _conta,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: EspacosTrato.x4),
                      Text('Tipo da conta', style: TipografiaTrato.corpoForte),
                      const SizedBox(height: EspacosTrato.x2),
                      DropdownButtonFormField<String>(
                        initialValue: _tipoConta,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'corrente', child: Text('Conta corrente')),
                          DropdownMenuItem(value: 'poupanca', child: Text('Conta poupança')),
                        ],
                        onChanged: (valor) {
                          if (valor != null) setState(() => _tipoConta = valor);
                        },
                      ),
                    ],
                    if (_erro != null) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      AvisoFaixa(
                        texto: _erro!,
                        tipo: TipoStatus.perigo,
                        icone: Icons.error_outline,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: context.cores.superficie,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                child: ConteudoResponsivo(
                  child: BotaoPrimario(
                    texto: 'Salvar conta de recebimento',
                    carregando: _salvando,
                    aoTocar: _salvando ? null : _salvar,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
