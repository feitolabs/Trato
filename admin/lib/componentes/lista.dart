import 'package:flutter/material.dart';

import '../tema/tema.dart';
import 'botoes.dart';
import 'feedback.dart';
import 'icones.dart';
import 'modal.dart';

/// Largura a partir da qual lista e detalhe ficam lado a lado.
const kLarguraMestreDetalhe = 760.0;

// ---------------------------------------------------------------------------------------------
// Abas: sublinhado na aba ativa, contagem opcional.
// ---------------------------------------------------------------------------------------------

class AbaTrato {
  const AbaTrato(this.rotulo, {this.contagem, required this.conteudo});
  final String rotulo;
  final int? contagem;
  final Widget conteudo;
}

class AbasTrato extends StatefulWidget {
  const AbasTrato({super.key, required this.abas, this.indiceInicial = 0});

  final List<AbaTrato> abas;
  final int indiceInicial;

  @override
  State<AbasTrato> createState() => _AbasTratoState();
}

class _AbasTratoState extends State<AbasTrato> {
  late int _indice = widget.indiceInicial;

  @override
  Widget build(BuildContext context) {
    final atual = _indice < widget.abas.length ? _indice : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsivo.margemLateral(FaixaPainel.de(context))),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: CoresTrato.bordaSuave)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < widget.abas.length; i++)
                    _ItemAba(
                      aba: widget.abas[i],
                      ativa: i == atual,
                      aoTocar: () => setState(() => _indice = i),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: KeyedSubtree(key: ValueKey('aba-$atual'), child: widget.abas[atual].conteudo)),
      ],
    );
  }
}

class _ItemAba extends StatelessWidget {
  const _ItemAba({required this.aba, required this.ativa, required this.aoTocar});
  final AbaTrato aba;
  final bool ativa;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: ativa,
      button: true,
      child: InkWell(
        onTap: aoTocar,
        child: Container(
          constraints: const BoxConstraints(minHeight: EspacosTrato.alturaBotao),
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: ativa ? CoresTrato.primaria : CoresTrato.transparente,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                aba.rotulo,
                style: TipografiaTrato.corpoForte.copyWith(
                  color: ativa ? CoresTrato.primaria : CoresTrato.textoMudo,
                ),
              ),
              if (aba.contagem != null) ...[
                const SizedBox(width: EspacosTrato.x2),
                Text(
                  _formatarInteiro(aba.contagem!),
                  style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatarInteiro(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

// ---------------------------------------------------------------------------------------------
// Cards.
// ---------------------------------------------------------------------------------------------

/// Card de lista: selecionável (Verificação), com ações à direita (Cupons, Categorias) e dado
/// secundário em segunda linha.
class CartaoLista extends StatelessWidget {
  const CartaoLista({
    super.key,
    required this.titulo,
    this.linhas = const [],
    this.chips = const [],
    this.acoes = const [],
    this.selecionado = false,
    this.aoTocar,
    this.tituloWidget,
  });

  final String titulo;
  final Widget? tituloWidget;
  final List<String> linhas;
  final List<Widget> chips;
  final List<Widget> acoes;
  final bool selecionado;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final conteudo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tituloWidget ?? Text(titulo, style: TipografiaTrato.corpoForte),
        for (final l in linhas)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(l, style: TipografiaTrato.legenda),
          ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x2),
          Wrap(spacing: EspacosTrato.x2, runSpacing: EspacosTrato.x1, children: chips),
        ],
      ],
    );
    final corpo = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: conteudo),
        if (acoes.isNotEmpty) ...[
          const SizedBox(width: EspacosTrato.x3),
          Wrap(spacing: EspacosTrato.x1, runSpacing: EspacosTrato.x1, crossAxisAlignment: WrapCrossAlignment.center, children: acoes),
        ],
      ],
    );
    return Material(
      color: selecionado ? CoresTrato.fundoSelecionado : CoresTrato.fundoSuperficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        side: BorderSide(
          color: selecionado ? CoresTrato.bordaSelecionada : CoresTrato.bordaSuave,
          width: selecionado ? 2 : 1,
        ),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EspacosTrato.raio)),
        onTap: aoTocar,
        child: Padding(padding: const EdgeInsets.all(EspacosTrato.paddingCartao), child: corpo),
      ),
    );
  }
}

/// Card de métrica: ícone, título, valor de 24 px, subtítulo e, opcionalmente, a variação em
/// relação ao período anterior e a ajuda com a definição do cálculo.
class CartaoMetrica extends StatelessWidget {
  const CartaoMetrica({
    super.key,
    required this.titulo,
    required this.valor,
    this.subtitulo,
    this.icone,
    this.variacaoPct,
    this.rotuloComparacao,
    this.ajuda,
    this.tom = Tom.neutro,
  });

  final String titulo;
  final String valor;
  final String? subtitulo;
  final IconData? icone;

  /// Variação em %, positiva ou negativa. Nulo = sem comparação.
  final double? variacaoPct;
  final String? rotuloComparacao;
  final String? ajuda;
  final Tom tom;

  @override
  Widget build(BuildContext context) {
    final alerta = tom == Tom.alerta || tom == Tom.erro;
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
      decoration: BoxDecoration(
        color: alerta ? tom.fundo : CoresTrato.fundoSuperficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        border: Border.all(color: alerta ? tom.texto : CoresTrato.bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icone != null) ...[
                Icon(icone, size: 16, color: CoresTrato.textoMudo),
                const SizedBox(width: EspacosTrato.x2),
              ],
              Expanded(child: Text(titulo, style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoMudo))),
              if (ajuda != null) IconeAjuda(ajuda!),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(valor, style: TipografiaTrato.valor),
          if (subtitulo != null) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(subtitulo!, style: TipografiaTrato.legenda),
          ],
          if (variacaoPct != null) ...[
            const SizedBox(height: EspacosTrato.x1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  variacaoPct! >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: variacaoPct! >= 0 ? CoresTrato.sucessoTexto : CoresTrato.perigoTexto,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    '${variacaoPct! >= 0 ? '+' : '-'}${variacaoPct!.abs().toStringAsFixed(1).replaceAll('.', ',')}% '
                    '${rotuloComparacao ?? 'vs. período anterior'}',
                    style: TipografiaTrato.etiqueta.copyWith(
                      color: variacaoPct! >= 0 ? CoresTrato.sucessoTexto : CoresTrato.perigoTexto,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Card de seção: título (opcional) e conteúdo, com 16 de padding e borda de 1 px.
class CartaoSecao extends StatelessWidget {
  const CartaoSecao({super.key, this.titulo, this.acao, required this.child, this.padding});

  final String? titulo;
  final Widget? acao;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(EspacosTrato.paddingCartao),
      decoration: BoxDecoration(
        color: CoresTrato.fundoSuperficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        border: Border.all(color: CoresTrato.bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
              child: Row(
                children: [
                  Expanded(child: Text(titulo!, style: TipografiaTrato.secao)),
                  if (acao != null) acao!,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Mestre-detalhe: lista à esquerda e detalhe à direita.
// ---------------------------------------------------------------------------------------------

class MestreDetalhe<T> extends StatefulWidget {
  const MestreDetalhe({
    super.key,
    required this.itens,
    required this.itemBuilder,
    required this.detalheBuilder,
    required this.tituloDetalhe,
    this.topo,
    this.mensagemSemItens = 'Nada por aqui.',
  });

  final List<T> itens;
  final Widget Function(BuildContext context, T item, bool selecionado) itemBuilder;
  final Widget Function(BuildContext context, T item) detalheBuilder;
  final String Function(T item) tituloDetalhe;

  /// Fica acima da lista (filtros por status, contador).
  final Widget? topo;
  final String mensagemSemItens;

  @override
  State<MestreDetalhe<T>> createState() => _MestreDetalheState<T>();
}

class _MestreDetalheState<T> extends State<MestreDetalhe<T>> {
  int _selecionado = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final largo = c.maxWidth >= kLarguraMestreDetalhe;
        final margem = Responsivo.margemLateral(FaixaPainel.de(context));
        final atual = _selecionado < widget.itens.length ? _selecionado : 0;
        final Widget lista = widget.itens.isEmpty
            ? EstadoVazio(widget.mensagemSemItens)
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(largo ? margem : margem, EspacosTrato.x2, largo ? EspacosTrato.x3 : margem, EspacosTrato.x6),
                itemCount: widget.itens.length,
                separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.intervaloCartoes),
                itemBuilder: (context, i) {
                  final item = widget.itens[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(EspacosTrato.raio),
                    onTap: () {
                      if (largo) {
                        setState(() => _selecionado = i);
                      } else {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (ctx) => Scaffold(
                            appBar: AppBar(title: Text(widget.tituloDetalhe(item))),
                            body: SafeArea(child: widget.detalheBuilder(ctx, item)),
                          ),
                        ));
                      }
                    },
                    child: widget.itemBuilder(context, item, largo && i == atual),
                  );
                },
              );
        final coluna = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.topo != null) widget.topo!,
            Expanded(child: lista),
          ],
        );
        if (!largo || widget.itens.isEmpty) return coluna;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 380, child: coluna),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(EspacosTrato.x3, EspacosTrato.x2, margem, EspacosTrato.x6),
                child: Container(
                  decoration: BoxDecoration(
                    color: CoresTrato.fundoSuperficie,
                    borderRadius: BorderRadius.circular(EspacosTrato.raio),
                    border: Border.all(color: CoresTrato.bordaSuave),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.detalheBuilder(context, widget.itens[atual]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Lista com busca, filtros, ordenação, contagem e paginação (padrão de interação 5).
// ---------------------------------------------------------------------------------------------

/// Um filtro por seleção (status, tipo…). `valor` null = "Todos".
class FiltroLista<T> {
  const FiltroLista({required this.rotulo, required this.opcoes, required this.aplica});
  final String rotulo;

  /// (valor, rótulo) — o primeiro item "Todos" é acrescentado pela lista.
  final List<(String, String)> opcoes;
  final bool Function(T item, String valor) aplica;
}

class OrdemLista<T> {
  const OrdemLista(this.rotulo, this.comparar);
  final String rotulo;
  final int Function(T a, T b) comparar;
}

class ListaPaginada<T> extends StatefulWidget {
  const ListaPaginada({
    super.key,
    required this.itens,
    required this.construirItem,
    this.textoBusca,
    this.rotuloBusca = 'Buscar',
    this.filtros = const [],
    this.ordens = const [],
    this.porPagina = 25,
    this.mensagemVazia = 'Nada com esses filtros.',
    this.detalheVazio,
    this.rotuloItens = 'itens',
    this.acoesTopo = const [],
    this.separador = EspacosTrato.intervaloCartoes,
  });

  final List<T> itens;
  final Widget Function(BuildContext context, T item) construirItem;

  /// Texto em que a busca procura (nome, código, ID…). Nulo = sem campo de busca.
  final String Function(T item)? textoBusca;
  final String rotuloBusca;
  final List<FiltroLista<T>> filtros;
  final List<OrdemLista<T>> ordens;

  /// Padrão do DS: 25 itens por página (RNF-06).
  final int porPagina;
  final String mensagemVazia;
  final String? detalheVazio;
  final String rotuloItens;
  final List<Widget> acoesTopo;
  final double separador;

  @override
  State<ListaPaginada<T>> createState() => _ListaPaginadaState<T>();
}

class _ListaPaginadaState<T> extends State<ListaPaginada<T>> {
  final _busca = TextEditingController();
  late final List<String?> _valores = List.filled(widget.filtros.length, null);
  int _ordem = 0;
  int _pagina = 0;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<T> get _visiveis {
    var l = widget.itens.toList();
    final termo = _busca.text.trim().toLowerCase();
    if (termo.isNotEmpty && widget.textoBusca != null) {
      l = [for (final i in l) if (widget.textoBusca!(i).toLowerCase().contains(termo)) i];
    }
    for (var f = 0; f < widget.filtros.length; f++) {
      final v = _valores[f];
      if (v != null) l = [for (final i in l) if (widget.filtros[f].aplica(i, v)) i];
    }
    if (widget.ordens.isNotEmpty) l.sort(widget.ordens[_ordem].comparar);
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final todos = _visiveis;
    final paginas = (todos.length / widget.porPagina).ceil().clamp(1, 1 << 30);
    final pagina = _pagina.clamp(0, paginas - 1);
    final ini = pagina * widget.porPagina;
    final fim = (ini + widget.porPagina).clamp(0, todos.length);
    final visiveis = todos.sublist(ini, fim);

    final barra = Wrap(
      spacing: EspacosTrato.x3,
      runSpacing: EspacosTrato.x3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.textoBusca != null)
          SizedBox(
            width: 320,
            child: TextField(
              controller: _busca,
              onChanged: (_) => setState(() => _pagina = 0),
              decoration: InputDecoration(
                labelText: widget.rotuloBusca,
                prefixIcon: const Icon(IconesTrato.buscar, size: 20),
              ),
            ),
          ),
        for (var f = 0; f < widget.filtros.length; f++)
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('filtro-$f-${_valores[f]}'),
              initialValue: _valores[f],
              isExpanded: true,
              decoration: InputDecoration(labelText: widget.filtros[f].rotulo),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                for (final o in widget.filtros[f].opcoes) DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2)),
              ],
              onChanged: (v) => setState(() {
                _valores[f] = v;
                _pagina = 0;
              }),
            ),
          ),
        if (widget.ordens.length > 1)
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<int>(
              initialValue: _ordem,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ordenar'),
              items: [
                for (var i = 0; i < widget.ordens.length; i++)
                  DropdownMenuItem(value: i, child: Text(widget.ordens[i].rotulo)),
              ],
              onChanged: (v) => setState(() => _ordem = v ?? 0),
            ),
          ),
        ...widget.acoesTopo,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.textoBusca != null || widget.filtros.isNotEmpty || widget.ordens.length > 1 || widget.acoesTopo.isNotEmpty)
          Padding(padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x3), child: barra),
        Expanded(
          child: visiveis.isEmpty
              ? EstadoVazio(widget.mensagemVazia, detalhe: widget.detalheVazio)
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x4),
                  itemCount: visiveis.length,
                  separatorBuilder: (_, _) => SizedBox(height: widget.separador),
                  itemBuilder: (context, i) => widget.construirItem(context, visiveis[i]),
                ),
        ),
        if (todos.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
            child: _RodapePaginacao(
              mostrando: 'Mostrando ${_formatarInteiro(ini + 1)} a ${_formatarInteiro(fim)} de '
                  '${_formatarInteiro(todos.length)} ${widget.rotuloItens}',
              pagina: pagina,
              paginas: paginas,
              aoMudar: (p) => setState(() => _pagina = p),
            ),
          ),
      ],
    );
  }
}

class _RodapePaginacao extends StatelessWidget {
  const _RodapePaginacao({required this.mostrando, required this.pagina, required this.paginas, required this.aoMudar});
  final String mostrando;
  final int pagina;
  final int paginas;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: EspacosTrato.x2,
      children: [
        Text(mostrando, style: TipografiaTrato.legenda),
        if (paginas > 1)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BotaoTrato.secundario('Anterior', aoPressionar: pagina > 0 ? () => aoMudar(pagina - 1) : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3),
                child: Text('Página ${pagina + 1} de $paginas', style: TipografiaTrato.legenda),
              ),
              BotaoTrato.secundario('Próxima', aoPressionar: pagina < paginas - 1 ? () => aoMudar(pagina + 1) : null),
            ],
          ),
      ],
    );
  }
}

/// Faixa de filtros por status com contagem (Enviada 4 · Em análise 1 · Aprovada 38…).
class FiltroStatus extends StatelessWidget {
  const FiltroStatus({super.key, required this.opcoes, required this.selecionado, required this.aoMudar});

  /// (código, rótulo, contagem)
  final List<(String, String, int)> opcoes;
  final String selecionado;
  final ValueChanged<String> aoMudar;

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return Padding(
      padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x3),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        children: [
          for (final o in opcoes)
            ChoiceChip(
              label: Text('${o.$2} ${o.$3}'),
              selected: o.$1 == selecionado,
              onSelected: (_) => aoMudar(o.$1),
              labelStyle: TipografiaTrato.etiqueta.copyWith(
                color: o.$1 == selecionado ? CoresTrato.primaria : CoresTrato.textoMudo,
              ),
              side: BorderSide(color: o.$1 == selecionado ? CoresTrato.bordaSelecionada : CoresTrato.bordaForte),
              visualDensity: VisualDensity.standard,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Seletor: mais de 7 opções vira lista com busca.
// ---------------------------------------------------------------------------------------------

class SeletorTrato<T> extends StatelessWidget {
  const SeletorTrato({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.opcoes,
    required this.aoMudar,
    this.ajuda,
    this.erro,
  });

  final String rotulo;
  final T? valor;

  /// (valor, rótulo)
  final List<(T, String)> opcoes;
  final ValueChanged<T> aoMudar;
  final String? ajuda;
  final String? erro;

  static const limiteSemBusca = 7;

  @override
  Widget build(BuildContext context) {
    if (opcoes.length <= limiteSemBusca) {
      return DropdownButtonFormField<T>(
        initialValue: valor,
        isExpanded: true,
        decoration: InputDecoration(labelText: rotulo, helperText: ajuda, errorText: erro),
        items: [for (final o in opcoes) DropdownMenuItem<T>(value: o.$1, child: Text(o.$2))],
        onChanged: (v) {
          if (v != null) aoMudar(v);
        },
      );
    }
    final atual = opcoes.where((o) => o.$1 == valor).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(EspacosTrato.raio),
      onTap: () async {
        final r = await mostrarModal<T>(
          context,
          construir: (_) => _EscolhaComBusca<T>(titulo: rotulo, opcoes: opcoes),
        );
        if (r != null) aoMudar(r);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: rotulo,
          helperText: ajuda,
          errorText: erro,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        isEmpty: atual == null,
        child: Text(atual?.$2 ?? '', style: TipografiaTrato.corpo),
      ),
    );
  }
}

class _EscolhaComBusca<T> extends StatefulWidget {
  const _EscolhaComBusca({required this.titulo, required this.opcoes});
  final String titulo;
  final List<(T, String)> opcoes;

  @override
  State<_EscolhaComBusca<T>> createState() => _EscolhaComBuscaState<T>();
}

class _EscolhaComBuscaState<T> extends State<_EscolhaComBusca<T>> {
  String _termo = '';

  @override
  Widget build(BuildContext context) {
    final lista = [
      for (final o in widget.opcoes)
        if (o.$2.toLowerCase().contains(_termo.toLowerCase())) o,
    ];
    return CorpoModal(
      titulo: widget.titulo,
      filhos: [
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _termo = v),
          decoration: const InputDecoration(labelText: 'Buscar', prefixIcon: Icon(IconesTrato.buscar, size: 20)),
        ),
        const SizedBox(height: EspacosTrato.x2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: lista.isEmpty
              ? const Padding(padding: EdgeInsets.all(EspacosTrato.x4), child: Text('Nada encontrado.'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in lista)
                      ListTile(
                        title: Text(o.$2),
                        onTap: () => Navigator.of(context).pop(o.$1),
                      ),
                  ],
                ),
        ),
      ],
      acoes: [BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(context).pop())],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Filtro de período: 7, 30, 90 dias e personalizado (RF-DAS-01, RF-PAG-02).
// ---------------------------------------------------------------------------------------------

class PeriodoSelecionado {
  const PeriodoSelecionado.dias(int this.dias)
      : inicio = null,
        fim = null;
  const PeriodoSelecionado.intervalo(DateTime this.inicio, DateTime this.fim) : dias = null;

  final int? dias;
  final DateTime? inicio;
  final DateTime? fim;

  bool get personalizado => dias == null;

  /// Dias entre o começo do período e hoje (o que a API entende).
  int diasAteHoje([DateTime? agora]) {
    if (dias != null) return dias!;
    final h = agora ?? DateTime.now();
    final d = h.difference(inicio!).inDays + 1;
    return d < 1 ? 1 : d;
  }

  /// Quantos dias o período tem (para comparar com o período anterior de mesma duração).
  int get duracaoEmDias => dias ?? (fim!.difference(inicio!).inDays + 1);

  bool contem(DateTime d) {
    if (dias != null) return true; // a API já filtra por "últimos N dias"
    final fimDoDia = DateTime(fim!.year, fim!.month, fim!.day, 23, 59, 59);
    return !d.isBefore(inicio!) && !d.isAfter(fimDoDia);
  }

  String get rotulo => dias != null
      ? 'últimos $dias dias'
      : '${_d(inicio!)} a ${_d(fim!)}';

  static String _d(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';

  @override
  bool operator ==(Object other) =>
      other is PeriodoSelecionado && other.dias == dias && other.inicio == inicio && other.fim == fim;

  @override
  int get hashCode => Object.hash(dias, inicio, fim);
}

class FiltroPeriodo extends StatelessWidget {
  const FiltroPeriodo({super.key, required this.selecionado, required this.aoMudar});

  final PeriodoSelecionado selecionado;
  final ValueChanged<PeriodoSelecionado> aoMudar;

  Future<void> _personalizado(BuildContext context) async {
    final agora = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(agora.year - 3),
      lastDate: agora,
      locale: const Locale('pt', 'BR'),
      helpText: 'Escolha o período',
      saveText: 'Aplicar',
    );
    if (r != null) aoMudar(PeriodoSelecionado.intervalo(r.start, r.end));
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String texto, bool ativo, VoidCallback aoTocar) => ChoiceChip(
          label: Text(texto),
          selected: ativo,
          onSelected: (_) => aoTocar(),
          labelStyle: TipografiaTrato.etiqueta.copyWith(
            color: ativo ? CoresTrato.primaria : CoresTrato.textoMudo,
          ),
          side: BorderSide(color: ativo ? CoresTrato.bordaSelecionada : CoresTrato.bordaForte),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        );
    return Wrap(
      spacing: EspacosTrato.x2,
      runSpacing: EspacosTrato.x2,
      children: [
        for (final d in const [7, 30, 90])
          chip('$d dias', selecionado.dias == d, () => aoMudar(PeriodoSelecionado.dias(d))),
        chip(
          selecionado.personalizado ? selecionado.rotulo : 'Personalizado',
          selecionado.personalizado,
          () => _personalizado(context),
        ),
      ],
    );
  }
}
