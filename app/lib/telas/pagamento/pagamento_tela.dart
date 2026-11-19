import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../profissional/dinheiro.dart';
import '../comuns/moeda_trato.dart';
import 'modelos.dart';

/// Tela 14 — Pagamento. Sem regra de dinheiro: mostra o valor que vem em [dados] e,
/// ao tocar no botão, chama [aoPagarDetalhado] (ou [aoPagar]) com o método e parcelas escolhidos.
class PagamentoTela extends StatefulWidget {
  const PagamentoTela({
    super.key,
    required this.dados,
    this.aoPagar,
    this.aoPagarDetalhado,
    this.aoAplicarCupom,
    this.aoAlternarMoedas,
    this.aoVoltar,
  });

  final DadosPagamento dados;
  final dynamic Function(MetodoPagamento)? aoPagar;
  final dynamic Function(MetodoPagamento metodo, int parcelas, String? cupom)? aoPagarDetalhado;
  final Future<DadosPagamento> Function(String codigo)? aoAplicarCupom;

  /// Liga/desliga o uso de moedas e devolve o resumo recalculado pelo backend.
  final Future<DadosPagamento> Function(bool usar, String? cupom)? aoAlternarMoedas;

  /// Padrão: `Navigator.maybePop`.
  final VoidCallback? aoVoltar;

  @override
  State<PagamentoTela> createState() => _PagamentoTelaState();
}

class _PagamentoTelaState extends State<PagamentoTela> {
  late DadosPagamento _dados = widget.dados;
  late MetodoPagamento _metodo = widget.dados.opcoes.first.metodo;
  int _parcelas = 1;
  final _cupomCtrl = TextEditingController();
  var _pagando = false;
  var _aplicandoCupom = false;
  var _usarMoedas = false;
  var _trocandoMoedas = false;
  String? _erroCupom;

  @override
  void didUpdateWidget(covariant PagamentoTela oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dados != oldWidget.dados) {
      _dados = widget.dados;
      if (_parcelas > 1 && !_dados.parcelamento.any((p) => p.parcelas == _parcelas)) {
        _parcelas = 1;
      }
      if ((_dados.cupomCodigo ?? '').isNotEmpty && _cupomCtrl.text.isEmpty) {
        _cupomCtrl.text = _dados.cupomCodigo!;
      }
    }
  }

  @override
  void dispose() {
    _cupomCtrl.dispose();
    super.dispose();
  }

  OpcaoParcelamento? get _parcelaEscolhida {
    if (_metodo != MetodoPagamento.cartao || _parcelas <= 1) return null;
    for (final p in _dados.parcelamento) {
      if (p.parcelas == _parcelas) return p;
    }
    return null;
  }

  int get _valorExibidoCentavos => _parcelaEscolhida?.totalCentavos ?? _dados.valorAgoraCentavos;

  Future<void> _aplicarCupom() async {
    final cb = widget.aoAplicarCupom;
    if (cb == null || _aplicandoCupom) return;
    final codigo = _cupomCtrl.text.trim();
    if (codigo.isEmpty) {
      setState(() => _erroCupom = 'Digite o código do cupom.');
      return;
    }
    setState(() {
      _aplicandoCupom = true;
      _erroCupom = null;
    });
    try {
      final atualizado = await cb(codigo);
      if (!mounted) return;
      setState(() {
        _dados = atualizado;
        _erroCupom = null;
        if (_parcelas > 1 && !_dados.parcelamento.any((p) => p.parcelas == _parcelas)) {
          _parcelas = 1;
        }
      });
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erroCupom = e.mensagem);
    } on Object {
      if (mounted) setState(() => _erroCupom = 'Não foi possível validar o cupom.');
    } finally {
      if (mounted) setState(() => _aplicandoCupom = false);
    }
  }

  Future<void> _alternarMoedas(bool usar) async {
    final cb = widget.aoAlternarMoedas;
    if (cb == null || _trocandoMoedas) return;
    setState(() => _trocandoMoedas = true);
    try {
      final atualizado = await cb(usar, _dados.cupomCodigo);
      if (!mounted) return;
      setState(() {
        _dados = atualizado;
        _usarMoedas = usar;
        if (_parcelas > 1 && !_dados.parcelamento.any((p) => p.parcelas == _parcelas)) {
          _parcelas = 1;
        }
      });
    } on Object {
      if (mounted) setState(() => _erroCupom = 'Não foi possível usar as moedas agora.');
    } finally {
      if (mounted) setState(() => _trocandoMoedas = false);
    }
  }

  Future<void> _removerCupom() async {
    final cb = widget.aoAplicarCupom;
    if (_aplicandoCupom) return;
    _cupomCtrl.clear();
    if (cb == null) {
      setState(() {
        _dados = widget.dados;
        _erroCupom = null;
      });
      return;
    }
    setState(() {
      _aplicandoCupom = true;
      _erroCupom = null;
    });
    try {
      final limpo = await cb('');
      if (!mounted) return;
      setState(() {
        _dados = limpo;
        if (_parcelas > 1 && !_dados.parcelamento.any((p) => p.parcelas == _parcelas)) {
          _parcelas = 1;
        }
      });
    } on Object {
      if (mounted) setState(() => _dados = widget.dados);
    } finally {
      if (mounted) setState(() => _aplicandoCupom = false);
    }
  }

  Future<void> _pagar() async {
    if (_pagando) return;
    setState(() => _pagando = true);
    try {
      final parcelasEnvio = _metodo == MetodoPagamento.cartao ? _parcelas : 1;
      if (widget.aoPagarDetalhado != null) {
        await widget.aoPagarDetalhado!.call(_metodo, parcelasEnvio, _dados.cupomCodigo);
      } else {
        await widget.aoPagar?.call(_metodo);
      }
    } finally {
      if (mounted) setState(() => _pagando = false);
    }
  }

  static const _passos = [
    'Você paga e o app confirma o recebimento em instantes.',
    'O valor fica protegido até você confirmar que o serviço foi realizado.',
    'Você confirma o serviço ao final. Se algo der errado, abra uma disputa: '
        'o caso passa por suporte e análise.',
  ];

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final valor = Dinheiro.formatar(_valorExibidoCentavos);
    final parcelaSel = _parcelaEscolhida;
    final comoPagar = _metodo == MetodoPagamento.pix
        ? 'com Pix'
        : (parcelaSel != null ? 'em ${parcelaSel.parcelas}x no cartão' : 'com cartão');
    final mostrarCupom = widget.aoAplicarCupom != null ||
        dados.descontoCentavos > 0 ||
        (dados.cupomCodigo ?? '').isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ConteudoResponsivo(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Voltar',
                        onPressed: widget.aoVoltar ?? () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      ),
                    ),
                    Text('Pagamento', style: TipografiaTrato.tituloGrande),
                    const SizedBox(height: EspacosTrato.x2),
                    Text(
                      dados.subtitulo,
                      style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x3),
                    Text(valor, style: TipografiaTrato.marcaPequena.copyWith(fontSize: 36)),
                    if (dados.rotuloValor != null) ...[
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        dados.rotuloValor!,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: CoresTrato.textoSecundario,
                        ),
                      ),
                    ],
                    if (dados.descontoCentavos - dados.moedasDescontoCentavos > 0) ...[
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        'Cupom ${dados.cupomCodigo ?? ''} aplicado · desconto de ${Dinheiro.formatar(dados.descontoCentavos - dados.moedasDescontoCentavos)}',
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: CoresTrato.verdeTexto,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (widget.aoAlternarMoedas != null && (dados.moedasSaldo > 0 || _usarMoedas)) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      _CartaoMoedas(
                        saldo: dados.moedasSaldo,
                        usadas: dados.moedasUsadas,
                        descontoCentavos: dados.moedasDescontoCentavos,
                        ligado: _usarMoedas,
                        ocupado: _trocandoMoedas,
                        aoAlternar: _alternarMoedas,
                      ),
                    ],
                    const SizedBox(height: EspacosTrato.x6),
                    Text('Como você quer pagar?', style: TipografiaTrato.corpoForte),
                    const SizedBox(height: EspacosTrato.x3),
                    for (final opcao in dados.opcoes) ...[
                      _OpcaoMetodo(
                        opcao: opcao,
                        selecionada: opcao.metodo == _metodo,
                        aoTocar: () => setState(() {
                          _metodo = opcao.metodo;
                          if (_metodo != MetodoPagamento.cartao) _parcelas = 1;
                        }),
                      ),
                      const SizedBox(height: EspacosTrato.x3),
                    ],
                    if (_metodo == MetodoPagamento.cartao && dados.parcelamento.isNotEmpty) ...[
                      Text('Cartão parcelado', style: TipografiaTrato.corpoForte),
                      const SizedBox(height: EspacosTrato.x2),
                      _OpcaoParcela(
                        key: const Key('parcela-1'),
                        titulo: '1x de ${Dinheiro.formatar(dados.valorAgoraCentavos)} (à vista)',
                        detalhe: 'Sem custo adicional de parcelamento',
                        selecionada: _parcelas == 1,
                        aoTocar: () => setState(() => _parcelas = 1),
                      ),
                      for (final p in dados.parcelamento) ...[
                        const SizedBox(height: EspacosTrato.x2),
                        _OpcaoParcela(
                          key: Key('parcela-${p.parcelas}'),
                          titulo: '${p.parcelas}x de ${Dinheiro.formatar(p.valorParcelaCentavos)}',
                          detalhe: 'Total ${Dinheiro.formatar(p.totalCentavos)} '
                              '(inclui ${Dinheiro.formatar(p.custoCentavos)} de custo do parcelamento)',
                          selecionada: _parcelas == p.parcelas,
                          aoTocar: () => setState(() => _parcelas = p.parcelas),
                        ),
                      ],
                      const SizedBox(height: EspacosTrato.x3),
                    ],
                    if (mostrarCupom) ...[
                      CartaoTrato(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cupom de desconto', style: TipografiaTrato.corpoForte),
                            const SizedBox(height: EspacosTrato.x2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const Key('campo-cupom'),
                                    controller: _cupomCtrl,
                                    textCapitalization: TextCapitalization.characters,
                                    decoration: InputDecoration(
                                      hintText: 'Digite o código (ex.: TRATO10)',
                                      errorText: _erroCupom,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: EspacosTrato.x2),
                                if (dados.descontoCentavos > 0)
                                  TextButton(
                                    key: const Key('botao-remover-cupom'),
                                    onPressed: _aplicandoCupom ? null : _removerCupom,
                                    child: const Text('Remover'),
                                  )
                                else
                                  TextButton(
                                    key: const Key('botao-aplicar-cupom'),
                                    onPressed: _aplicandoCupom ? null : _aplicarCupom,
                                    child: _aplicandoCupom
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('Aplicar'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: EspacosTrato.x3),
                    ],
                    const SizedBox(height: EspacosTrato.x3),
                    CartaoTrato(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Como funciona o pagamento', style: TipografiaTrato.tituloOpcao),
                          const SizedBox(height: EspacosTrato.x4),
                          for (var i = 0; i < _passos.length; i++) ...[
                            if (i > 0) const SizedBox(height: EspacosTrato.x3),
                            _Passo(numero: i + 1, texto: _passos[i]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: EspacosTrato.x4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 20,
                          color: CoresTrato.textoSecundario,
                        ),
                        const SizedBox(width: EspacosTrato.x3),
                        Expanded(
                          child: Text(
                            'Pix e cartão só no nome do seu CPF. '
                            'O Trato não guarda o número do seu cartão.',
                            style: TipografiaTrato.corpoPequeno.copyWith(
                              color: CoresTrato.textoSecundario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: CoresTrato.superficie,
                border: Border(top: BorderSide(color: CoresTrato.borda)),
              ),
              child: ConteudoResponsivo(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                  child: BotaoPrimario(
                    texto: 'Pagar $valor $comoPagar',
                    carregando: _pagando,
                    aoTocar: _pagando ? null : _pagar,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcaoMetodo extends StatelessWidget {
  const _OpcaoMetodo({required this.opcao, required this.selecionada, required this.aoTocar});

  final OpcaoPagamento opcao;
  final bool selecionada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raioGrande);
    return Semantics(
      button: true,
      selected: selecionada,
      child: Material(
        color: selecionada ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: selecionada ? CoresTrato.petroleo : CoresTrato.borda,
            width: selecionada ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              children: [
                Icon(
                  selecionada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 28,
                  color: selecionada ? CoresTrato.petroleo : CoresTrato.textoSecundario,
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opcao.titulo, style: TipografiaTrato.tituloCartao),
                      const SizedBox(height: 2),
                      Text(
                        opcao.descricao,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: CoresTrato.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpcaoParcela extends StatelessWidget {
  const _OpcaoParcela({
    super.key,
    required this.titulo,
    required this.detalhe,
    required this.selecionada,
    required this.aoTocar,
  });

  final String titulo;
  final String detalhe;
  final bool selecionada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raio);
    return Semantics(
      button: true,
      selected: selecionada,
      child: Material(
        color: selecionada ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: selecionada ? CoresTrato.petroleo : CoresTrato.borda,
            width: selecionada ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x3,
              vertical: EspacosTrato.x3,
            ),
            child: Row(
              children: [
                Icon(
                  selecionada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 20,
                  color: selecionada ? CoresTrato.petroleo : CoresTrato.textoSecundario,
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: TipografiaTrato.corpoForte),
                      const SizedBox(height: 2),
                      Text(
                        detalhe,
                        style: TipografiaTrato.corpoPequeno.copyWith(
                          color: CoresTrato.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({required this.numero, required this.texto});

  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: CoresTrato.azulSuave, shape: BoxShape.circle),
          child: Text(
            '$numero',
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: CoresTrato.azulTexto,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: EspacosTrato.x3),
        Expanded(child: Text(texto, style: TipografiaTrato.corpo)),
      ],
    );
  }
}

/// "Usar minhas moedas": o app só liga o interruptor; quantas moedas entram e o desconto vêm
/// do backend (limite por serviço em tabela).
class _CartaoMoedas extends StatelessWidget {
  const _CartaoMoedas({
    required this.saldo,
    required this.usadas,
    required this.descontoCentavos,
    required this.ligado,
    required this.ocupado,
    required this.aoAlternar,
  });

  final int saldo;
  final int usadas;
  final int descontoCentavos;
  final bool ligado;
  final bool ocupado;
  final ValueChanged<bool> aoAlternar;

  @override
  Widget build(BuildContext context) {
    final detalhe = ligado && usadas > 0
        ? 'Usando $usadas moedas · desconto de ${Dinheiro.formatar(descontoCentavos)}'
        : 'Você tem $saldo moedas do Trato';
    return Card(
      margin: EdgeInsets.zero,
      child: SwitchListTile(
        key: const Key('interruptor-moedas'),
        secondary: const MoedaTrato(tamanho: 36),
        title: Text('Usar minhas moedas', style: TipografiaTrato.corpoForte),
        subtitle: Text(
          detalhe,
          style: TipografiaTrato.corpoPequeno.copyWith(
            color: ligado && usadas > 0 ? CoresTrato.verdeTexto : CoresTrato.textoSecundario,
          ),
        ),
        value: ligado,
        onChanged: ocupado ? null : aoAlternar,
      ),
    );
  }
}
