import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/repositorios.dart';
import '../../tema/tema.dart';
import '../cliente/modelos.dart';
import '../pedido_novo/pecas_pedido.dart';

/// Filtros dos pedidos abertos do profissional (categoria, bairro, faixa de preço e ordem).
/// Devolve um [FiltroPedidosAbertos] ao fechar com "Aplicar"; quem aplica o filtro é o backend.
class FiltrosPedidosAbertosTela extends StatefulWidget {
  const FiltrosPedidosAbertosTela({
    super.key,
    this.atual = const FiltroPedidosAbertos(),
    this.categorias = const [],
  });

  final FiltroPedidosAbertos atual;

  /// Categorias que o profissional atende (ids do catálogo).
  final List<CategoriaServico> categorias;

  @override
  State<FiltrosPedidosAbertosTela> createState() => _FiltrosPedidosAbertosTelaState();
}

class _FaixaPreco {
  const _FaixaPreco(this.rotulo, this.min, this.max);

  final String rotulo;
  final int? min;
  final int? max;
}

class _FiltrosPedidosAbertosTelaState extends State<FiltrosPedidosAbertosTela> {
  static const _faixas = [
    _FaixaPreco('Qualquer', null, null),
    _FaixaPreco('Até R\$ 200', null, 20000),
    _FaixaPreco('R\$ 200 a R\$ 500', 20000, 50000),
    _FaixaPreco('Acima de R\$ 500', 50000, null),
  ];

  static const _ordens = [
    ('recentes', 'Mais recentes'),
    ('urgentes', 'Urgentes primeiro'),
    ('maior_valor', 'Maior valor'),
    ('menor_valor', 'Menor valor'),
    ('antigos', 'Mais antigos'),
  ];

  late final _bairro = TextEditingController(text: widget.atual.bairro ?? '');
  late String? _categoria = widget.atual.categoriaId;
  late _FaixaPreco _faixa = _faixas.firstWhere(
    (f) => f.min == widget.atual.precoMinCentavos && f.max == widget.atual.precoMaxCentavos,
    orElse: () => _faixas.first,
  );
  late String _ordem = widget.atual.ordenar;

  @override
  void dispose() {
    _bairro.dispose();
    super.dispose();
  }

  FiltroPedidosAbertos get _filtro => FiltroPedidosAbertos(
        categoriaId: _categoria,
        bairro: _bairro.text.trim().isEmpty ? null : _bairro.text.trim(),
        precoMinCentavos: _faixa.min,
        precoMaxCentavos: _faixa.max,
        ordenar: _ordem,
      );

  void _limpar() => setState(() {
        _bairro.clear();
        _categoria = null;
        _faixa = _faixas.first;
        _ordem = 'recentes';
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filtros', style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  'Escolha o que aparece em "Pedidos abertos".',
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                ),
                if (widget.categorias.isNotEmpty) ...[
                  const SizedBox(height: EspacosTrato.x5),
                  const RotuloSecao('Categoria'),
                  const SizedBox(height: EspacosTrato.x3),
                  Wrap(
                    spacing: EspacosTrato.x2,
                    runSpacing: EspacosTrato.x2,
                    children: [
                      ChipOpcao(
                        texto: 'Todas',
                        marcado: _categoria == null,
                        aoTocar: () => setState(() => _categoria = null),
                      ),
                      for (final c in widget.categorias)
                        ChipOpcao(
                          texto: c.nome,
                          marcado: _categoria == c.id,
                          aoTocar: () => setState(() => _categoria = c.id),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: EspacosTrato.x5),
                const RotuloSecao('Bairro'),
                const SizedBox(height: EspacosTrato.x3),
                TextField(
                  controller: _bairro,
                  style: TipografiaTrato.corpo,
                  decoration: const InputDecoration(hintText: 'Ex.: Savassi'),
                ),
                const SizedBox(height: EspacosTrato.x5),
                const RotuloSecao('Faixa de preço do cliente'),
                const SizedBox(height: EspacosTrato.x3),
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x2,
                  children: [
                    for (final f in _faixas)
                      ChipOpcao(
                        texto: f.rotulo,
                        marcado: identical(f, _faixa),
                        aoTocar: () => setState(() => _faixa = f),
                      ),
                  ],
                ),
                const SizedBox(height: EspacosTrato.x5),
                const RotuloSecao('Ordenar por'),
                const SizedBox(height: EspacosTrato.x3),
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x2,
                  children: [
                    for (final (valor, rotulo) in _ordens)
                      ChipOpcao(
                        texto: rotulo,
                        marcado: _ordem == valor,
                        aoTocar: () => setState(() => _ordem = valor),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _Rodape(
        aoLimpar: _limpar,
        aoAplicar: () => Navigator.of(context).pop(_filtro),
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({required this.aoLimpar, required this.aoAplicar});

  final VoidCallback aoLimpar;
  final VoidCallback aoAplicar;

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(TamanhoTela.de(context));
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CoresTrato.creme,
        border: Border(top: BorderSide(color: CoresTrato.borda)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x4, margem, EspacosTrato.x4),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Responsivo.larguraMaximaConteudo),
              child: Row(
                children: [
                  Expanded(child: BotaoSecundario(texto: 'Limpar', aoTocar: aoLimpar)),
                  const SizedBox(width: EspacosTrato.x3),
                  Expanded(child: BotaoPrimario(texto: 'Aplicar', aoTocar: aoAplicar)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
