import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import 'modelos.dart';

enum _PeriodoFiltro {
  qualquer('Qualquer data'),
  hoje('Hoje'),
  ultimos7('Últimos 7 dias'),
  ultimos30('Últimos 30 dias');

  const _PeriodoFiltro(this.rotulo);
  final String rotulo;
}

enum _OrdenacaoPedidos {
  maisRecentes('Mais recentes'),
  maisAntigos('Mais antigos');

  const _OrdenacaoPedidos(this.rotulo);
  final String rotulo;
}

class _FiltrosPedidos {
  const _FiltrosPedidos({
    this.categoria,
    this.periodo = _PeriodoFiltro.qualquer,
    this.ordenacao = _OrdenacaoPedidos.maisRecentes,
    this.status,
    this.apenasUrgente = false,
    this.apenasRemoto = false,
  });

  final String? categoria;
  final _PeriodoFiltro periodo;
  final _OrdenacaoPedidos ordenacao;
  final String? status;
  final bool apenasUrgente;
  final bool apenasRemoto;

  int get quantidadeAtivos {
    var total = 0;
    if (categoria != null) total++;
    if (periodo != _PeriodoFiltro.qualquer) total++;
    if (ordenacao != _OrdenacaoPedidos.maisRecentes) total++;
    if (status != null) total++;
    if (apenasUrgente) total++;
    if (apenasRemoto) total++;
    return total;
  }

  bool get temAtivos => quantidadeAtivos > 0;

  _FiltrosPedidos copiar({
    String? Function()? categoria,
    _PeriodoFiltro? periodo,
    _OrdenacaoPedidos? ordenacao,
    String? Function()? status,
    bool? apenasUrgente,
    bool? apenasRemoto,
  }) =>
      _FiltrosPedidos(
        categoria: categoria != null ? categoria() : this.categoria,
        periodo: periodo ?? this.periodo,
        ordenacao: ordenacao ?? this.ordenacao,
        status: status != null ? status() : this.status,
        apenasUrgente: apenasUrgente ?? this.apenasUrgente,
        apenasRemoto: apenasRemoto ?? this.apenasRemoto,
      );
}

/// Tela 15 — Seus pedidos, com abas "Em andamento" e "Finalizados", busca, filtros inteligentes
/// e atualização.
class SeusPedidosTela extends StatefulWidget {
  const SeusPedidosTela({
    super.key,
    required this.emAndamento,
    required this.finalizados,
    this.aoAbrirPedido,
    this.aoFazerPedido,
    this.agora,
  });

  final List<PedidoResumo> emAndamento;
  final List<PedidoResumo> finalizados;
  final ValueChanged<PedidoResumo>? aoAbrirPedido;

  /// Ação do estado vazio de "Em andamento" (abre o novo pedido).
  final VoidCallback? aoFazerPedido;

  /// Relógio injetável para testes determinísticos dos filtros de período.
  final DateTime Function()? agora;

  @override
  State<SeusPedidosTela> createState() => _SeusPedidosTelaState();
}

class _SeusPedidosTelaState extends State<SeusPedidosTela> {
  final _busca = TextEditingController();
  bool _verFinalizados = false;
  _FiltrosPedidos _filtros = const _FiltrosPedidos();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<String> _categoriasDaAba(List<PedidoResumo> pedidos) {
    final unicas = <String>{};
    for (final p in pedidos) {
      final cat = p.categoria?.trim();
      if (cat != null && cat.isNotEmpty) unicas.add(cat);
    }
    return unicas.toList()..sort(compararAlfabeticoPtBr);
  }

  List<String> _statusDaAba(List<PedidoResumo> pedidos) {
    final unicos = <String>{};
    for (final p in pedidos) {
      final st = p.statusTexto.trim();
      if (st.isNotEmpty) unicos.add(st);
    }
    return unicos.toList()..sort(compararAlfabeticoPtBr);
  }

  void _trocarAba(bool finalizados) {
    if (_verFinalizados == finalizados) return;
    final novaAba = finalizados ? widget.finalizados : widget.emAndamento;
    final cats = _categoriasDaAba(novaAba).toSet();
    final statuses = _statusDaAba(novaAba).toSet();
    final temUrgente = novaAba.any((p) => p.urgente);
    final temRemoto = novaAba.any((p) => p.remoto);

    setState(() {
      _verFinalizados = finalizados;
      _filtros = _filtros.copiar(
        categoria: () =>
            _filtros.categoria != null && cats.contains(_filtros.categoria)
                ? _filtros.categoria
                : null,
        status: () =>
            _filtros.status != null && statuses.contains(_filtros.status)
                ? _filtros.status
                : null,
        apenasUrgente: temUrgente ? _filtros.apenasUrgente : false,
        apenasRemoto: temRemoto ? _filtros.apenasRemoto : false,
      );
    });
  }

  bool _passaNoPeriodo(PedidoResumo pedido) {
    if (_filtros.periodo == _PeriodoFiltro.qualquer) return true;
    final data = pedido.abertoEm;
    if (data == null) return false;
    final ref = (widget.agora ?? DateTime.now)();
    final inicioHoje = DateTime(ref.year, ref.month, ref.day);
    final local = data.toLocal();
    return switch (_filtros.periodo) {
      _PeriodoFiltro.qualquer => true,
      _PeriodoFiltro.hoje => !local.isBefore(inicioHoje),
      _PeriodoFiltro.ultimos7 =>
        !local.isBefore(inicioHoje.subtract(const Duration(days: 6))),
      _PeriodoFiltro.ultimos30 =>
        !local.isBefore(inicioHoje.subtract(const Duration(days: 29))),
    };
  }

  List<PedidoResumo> _aplicarBuscaEFiltros(List<PedidoResumo> pedidosDaAba) {
    final termo = normalizarTextoBusca(_busca.text);
    final filtrados = <(int, PedidoResumo)>[];

    for (var i = 0; i < pedidosDaAba.length; i++) {
      final p = pedidosDaAba[i];
      if (termo.isNotEmpty) {
        final bate = normalizarTextoBusca(p.titulo).contains(termo) ||
            normalizarTextoBusca(p.subtitulo).contains(termo) ||
            normalizarTextoBusca(p.profissionalNome).contains(termo) ||
            normalizarTextoBusca(p.statusTexto).contains(termo) ||
            (p.categoria != null && normalizarTextoBusca(p.categoria!).contains(termo));
        if (!bate) continue;
      }
      if (_filtros.categoria != null && p.categoria?.trim() != _filtros.categoria) {
        continue;
      }
      if (_filtros.status != null && p.statusTexto.trim() != _filtros.status) {
        continue;
      }
      if (_filtros.apenasUrgente && !p.urgente) continue;
      if (_filtros.apenasRemoto && !p.remoto) continue;
      if (!_passaNoPeriodo(p)) continue;
      filtrados.add((i, p));
    }

    filtrados.sort((a, b) {
      final da = a.$2.abertoEm;
      final db = b.$2.abertoEm;
      if (da != null && db != null) {
        final cmp = _filtros.ordenacao == _OrdenacaoPedidos.maisRecentes
            ? db.compareTo(da)
            : da.compareTo(db);
        if (cmp != 0) return cmp;
      } else if (da != null || db != null) {
        return da != null ? -1 : 1;
      }
      return _filtros.ordenacao == _OrdenacaoPedidos.maisRecentes
          ? a.$1.compareTo(b.$1)
          : b.$1.compareTo(a.$1);
    });

    return [for (final item in filtrados) item.$2];
  }

  Future<void> _abrirFolhaFiltros(List<PedidoResumo> pedidosDaAba) async {
    final categorias = _categoriasDaAba(pedidosDaAba);
    final statuses = _statusDaAba(pedidosDaAba);
    final temUrgente = pedidosDaAba.any((p) => p.urgente);
    final temRemoto = pedidosDaAba.any((p) => p.remoto);

    final resultado = await showModalBottomSheet<_FiltrosPedidos>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FolhaFiltrosPedidos(
        inicial: _filtros,
        categorias: categorias,
        statuses: statuses,
        temUrgente: temUrgente,
        temRemoto: temRemoto,
      ),
    );
    if (resultado != null && mounted) {
      setState(() => _filtros = resultado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedidosDaAba = _verFinalizados ? widget.finalizados : widget.emAndamento;
    final pedidos = _aplicarBuscaEFiltros(pedidosDaAba);
    final recarregar = AtualizadorTela.de(context);
    final mostrarBusca =
        widget.emAndamento.isNotEmpty || widget.finalizados.isNotEmpty || _busca.text.isNotEmpty;

    final lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        top: EspacosTrato.x6,
        bottom: BarraAbasFlutuante.alturaReservada + 72,
      ),
      children: [
        Text('Seus pedidos', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x4),
        _Abas(
          finalizados: _verFinalizados,
          aoTrocar: _trocarAba,
        ),
        if (mostrarBusca) ...[
          const SizedBox(height: EspacosTrato.x4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busca,
                  style: TipografiaTrato.corpo,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar pedido ou profissional',
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
              ),
              const SizedBox(width: EspacosTrato.x2),
              _BotaoFiltros(
                ativos: _filtros.quantidadeAtivos,
                aoTocar: () => _abrirFolhaFiltros(pedidosDaAba),
              ),
            ],
          ),
          if (_filtros.temAtivos) ...[
            const SizedBox(height: EspacosTrato.x3),
            _FaixaChipsFiltrosAtivos(
              filtros: _filtros,
              aoAlterar: (f) => setState(() => _filtros = f),
            ),
          ],
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (pedidosDaAba.isEmpty)
          EstadoVazio(
            icone: _verFinalizados ? Icons.task_alt_outlined : Icons.assignment_outlined,
            titulo:
                _verFinalizados ? 'Nenhum serviço finalizado ainda' : 'Nenhum pedido em andamento',
            texto: _verFinalizados
                ? 'Os serviços concluídos ou cancelados aparecem aqui.'
                : 'Toque em "Início" e peça um orçamento para começar.',
            textoAcao: _verFinalizados || widget.aoFazerPedido == null ? null : 'Fazer um pedido',
            aoAcao: widget.aoFazerPedido,
          )
        else if (pedidos.isEmpty)
          EstadoVazio(
            icone: Icons.search_off,
            titulo: 'Nenhum pedido encontrado',
            texto: _filtros.temAtivos
                ? 'Nenhum pedido corresponde aos filtros selecionados.'
                : 'Não achamos "${_busca.text.trim()}" nesta aba.',
            textoAcao: _filtros.temAtivos ? 'Limpar filtros' : null,
            aoAcao: _filtros.temAtivos
                ? () => setState(() => _filtros = const _FiltrosPedidos())
                : null,
          )
        else
          for (final pedido in pedidos) ...[
            _CartaoPedido(
              pedido: pedido,
              aoTocar: () => widget.aoAbrirPedido?.call(pedido),
            ),
            const SizedBox(height: EspacosTrato.x4),
          ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ConteudoResponsivo(
          child: recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista),
        ),
      ),
    );
  }
}

class _BotaoFiltros extends StatelessWidget {
  const _BotaoFiltros({required this.ativos, required this.aoTocar});

  final int ativos;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final temAtivos = ativos > 0;
    return Semantics(
      button: true,
      label: temAtivos ? 'Filtros ($ativos ativos)' : 'Filtros',
      child: Material(
        key: const ValueKey('botao-filtros-pedidos'),
        color: temAtivos ? c.azulSuave : c.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
          side: BorderSide(
            color: temAtivos ? c.petroleo : c.bordaControle,
            width: EspacosTrato.bordaControle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: SizedBox(
            width: EspacosTrato.alturaCampo,
            height: EspacosTrato.alturaCampo,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune,
                  color: temAtivos ? c.azulTexto : c.texto,
                ),
                if (temAtivos)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      key: const ValueKey('badge-filtros-pedidos'),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.petroleo,
                        borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                      ),
                      child: Text(
                        '$ativos',
                        style: TipografiaTrato.legenda.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.sobrePetroleo,
                        ),
                      ),
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

class _FaixaChipsFiltrosAtivos extends StatelessWidget {
  const _FaixaChipsFiltrosAtivos({
    required this.filtros,
    required this.aoAlterar,
  });

  final _FiltrosPedidos filtros;
  final ValueChanged<_FiltrosPedidos> aoAlterar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final chips = <Widget>[
      if (filtros.categoria != null)
        _ChipFiltroRemovivel(
          rotulo: filtros.categoria!,
          aoRemover: () => aoAlterar(filtros.copiar(categoria: () => null)),
        ),
      if (filtros.periodo != _PeriodoFiltro.qualquer)
        _ChipFiltroRemovivel(
          rotulo: filtros.periodo.rotulo,
          aoRemover: () => aoAlterar(filtros.copiar(periodo: _PeriodoFiltro.qualquer)),
        ),
      if (filtros.ordenacao != _OrdenacaoPedidos.maisRecentes)
        _ChipFiltroRemovivel(
          rotulo: filtros.ordenacao.rotulo,
          aoRemover: () => aoAlterar(filtros.copiar(ordenacao: _OrdenacaoPedidos.maisRecentes)),
        ),
      if (filtros.status != null)
        _ChipFiltroRemovivel(
          rotulo: filtros.status!,
          aoRemover: () => aoAlterar(filtros.copiar(status: () => null)),
        ),
      if (filtros.apenasUrgente)
        _ChipFiltroRemovivel(
          rotulo: 'Urgente',
          aoRemover: () => aoAlterar(filtros.copiar(apenasUrgente: false)),
        ),
      if (filtros.apenasRemoto)
        _ChipFiltroRemovivel(
          rotulo: 'Remoto',
          aoRemover: () => aoAlterar(filtros.copiar(apenasRemoto: false)),
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: EspacosTrato.x2),
            chips[i],
          ],
          if (filtros.quantidadeAtivos >= 2) ...[
            const SizedBox(width: EspacosTrato.x2),
            TextButton(
              key: const ValueKey('limpar-filtros-chips'),
              onPressed: () => aoAlterar(const _FiltrosPedidos()),
              style: TextButton.styleFrom(
                foregroundColor: c.azulTexto,
                padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x2),
                minimumSize: const Size(0, 34),
              ),
              child: const Text('Limpar'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipFiltroRemovivel extends StatelessWidget {
  const _ChipFiltroRemovivel({required this.rotulo, required this.aoRemover});

  final String rotulo;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Material(
      color: c.azulSuave,
      shape: StadiumBorder(side: BorderSide(color: c.petroleo, width: EspacosTrato.bordaFina)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoRemover,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspacosTrato.x3,
            vertical: EspacosTrato.x1 + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rotulo,
                style: TipografiaTrato.corpoPequeno.copyWith(
                  color: c.azulTexto,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: EspacosTrato.x1),
              Icon(Icons.close, size: 15, color: c.azulTexto),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolhaFiltrosPedidos extends StatefulWidget {
  const _FolhaFiltrosPedidos({
    required this.inicial,
    required this.categorias,
    required this.statuses,
    required this.temUrgente,
    required this.temRemoto,
  });

  final _FiltrosPedidos inicial;
  final List<String> categorias;
  final List<String> statuses;
  final bool temUrgente;
  final bool temRemoto;

  @override
  State<_FolhaFiltrosPedidos> createState() => _FolhaFiltrosPedidosState();
}

class _FolhaFiltrosPedidosState extends State<_FolhaFiltrosPedidos> {
  late _FiltrosPedidos _rascunho = widget.inicial;

  Widget _pilula({
    required String rotulo,
    required bool selecionado,
    required VoidCallback aoTocar,
  }) {
    final c = context.cores;
    return Material(
      color: selecionado ? c.petroleo : c.superficie,
      shape: StadiumBorder(
        side: BorderSide(
          color: selecionado ? c.petroleo : c.bordaControle,
          width: EspacosTrato.bordaFina,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspacosTrato.x3 + 2,
            vertical: EspacosTrato.x2,
          ),
          child: Text(
            rotulo,
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: selecionado ? c.sobrePetroleo : c.texto,
              fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final temStatusOuTipo = widget.statuses.isNotEmpty || widget.temUrgente || widget.temRemoto;

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: EspacosTrato.x3, bottom: EspacosTrato.x2),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.bordaControle,
                  borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EspacosTrato.x4,
                vertical: EspacosTrato.x2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtrar pedidos',
                      style: TipografiaTrato.titulo.copyWith(color: c.texto),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: Icon(Icons.close, color: c.textoSecundario),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.borda),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(EspacosTrato.x4),
                children: [
                  if (widget.categorias.isNotEmpty) ...[
                    Text('Categoria', style: TipografiaTrato.corpoForte.copyWith(color: c.texto)),
                    const SizedBox(height: EspacosTrato.x2),
                    Wrap(
                      spacing: EspacosTrato.x2,
                      runSpacing: EspacosTrato.x2,
                      children: [
                        for (final cat in widget.categorias)
                          _pilula(
                            rotulo: cat,
                            selecionado: _rascunho.categoria == cat,
                            aoTocar: () => setState(() {
                              _rascunho = _rascunho.copiar(
                                categoria: () => _rascunho.categoria == cat ? null : cat,
                              );
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: EspacosTrato.x5),
                  ],
                  Text('Período', style: TipografiaTrato.corpoForte.copyWith(color: c.texto)),
                  const SizedBox(height: EspacosTrato.x2),
                  Wrap(
                    spacing: EspacosTrato.x2,
                    runSpacing: EspacosTrato.x2,
                    children: [
                      for (final p in _PeriodoFiltro.values)
                        _pilula(
                          rotulo: p.rotulo,
                          selecionado: _rascunho.periodo == p,
                          aoTocar: () => setState(() => _rascunho = _rascunho.copiar(periodo: p)),
                        ),
                    ],
                  ),
                  const SizedBox(height: EspacosTrato.x5),
                  Text('Ordenação', style: TipografiaTrato.corpoForte.copyWith(color: c.texto)),
                  const SizedBox(height: EspacosTrato.x2),
                  Wrap(
                    spacing: EspacosTrato.x2,
                    runSpacing: EspacosTrato.x2,
                    children: [
                      for (final o in _OrdenacaoPedidos.values)
                        _pilula(
                          rotulo: o.rotulo,
                          selecionado: _rascunho.ordenacao == o,
                          aoTocar: () => setState(() => _rascunho = _rascunho.copiar(ordenacao: o)),
                        ),
                    ],
                  ),
                  if (temStatusOuTipo) ...[
                    const SizedBox(height: EspacosTrato.x5),
                    Text(
                      'Status e tipo',
                      style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
                    ),
                    const SizedBox(height: EspacosTrato.x2),
                    Wrap(
                      spacing: EspacosTrato.x2,
                      runSpacing: EspacosTrato.x2,
                      children: [
                        for (final st in widget.statuses)
                          _pilula(
                            rotulo: st,
                            selecionado: _rascunho.status == st,
                            aoTocar: () => setState(() {
                              _rascunho = _rascunho.copiar(
                                status: () => _rascunho.status == st ? null : st,
                              );
                            }),
                          ),
                        if (widget.temUrgente)
                          _pilula(
                            rotulo: 'Urgente',
                            selecionado: _rascunho.apenasUrgente,
                            aoTocar: () => setState(() {
                              _rascunho = _rascunho.copiar(
                                apenasUrgente: !_rascunho.apenasUrgente,
                              );
                            }),
                          ),
                        if (widget.temRemoto)
                          _pilula(
                            rotulo: 'Remoto',
                            selecionado: _rascunho.apenasRemoto,
                            aoTocar: () => setState(() {
                              _rascunho = _rascunho.copiar(
                                apenasRemoto: !_rascunho.apenasRemoto,
                              );
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(EspacosTrato.x4),
              decoration: BoxDecoration(
                color: c.superficie,
                border: Border(top: BorderSide(color: c.borda)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: BotaoSecundario(
                      texto: 'Limpar',
                      aoTocar: () => Navigator.of(context).pop(const _FiltrosPedidos()),
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x3),
                  Expanded(
                    flex: 3,
                    child: BotaoPrimario(
                      texto: 'Aplicar',
                      aoTocar: () => Navigator.of(context).pop(_rascunho),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Abas extends StatelessWidget {
  const _Abas({required this.finalizados, required this.aoTrocar});

  final bool finalizados;
  final ValueChanged<bool> aoTrocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.borda)),
      ),
      child: Row(
        children: [
          Flexible(
            child: _Aba(
              rotulo: 'Em andamento',
              ativa: !finalizados,
              aoTocar: () => aoTrocar(false),
            ),
          ),
          const SizedBox(width: EspacosTrato.x5),
          Flexible(
            child: _Aba(
              rotulo: 'Finalizados',
              ativa: finalizados,
              aoTocar: () => aoTrocar(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aba extends StatelessWidget {
  const _Aba({required this.rotulo, required this.ativa, required this.aoTocar});

  final String rotulo;
  final bool ativa;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final estilo = ativa
        ? TipografiaTrato.corpoForte.copyWith(color: c.texto)
        : TipografiaTrato.corpo.copyWith(color: c.textoSecundario);
    return Semantics(
      selected: ativa,
      button: true,
      child: InkWell(
        onTap: aoTocar,
        child: Container(
          padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: ativa ? c.petroleo : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo),
        ),
      ),
    );
  }
}

class _CartaoPedido extends StatelessWidget {
  const _CartaoPedido({required this.pedido, required this.aoTocar});

  final PedidoResumo pedido;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return CartaoTrato(
      aoTocar: aoTocar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pedido.titulo, style: TipografiaTrato.tituloCartao),
          if (pedido.descricao != null) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              pedido.descricao!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
            ),
          ],
          const SizedBox(height: EspacosTrato.x1),
          Text(
            pedido.subtitulo,
            style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x1,
            children: [
              ChipStatus(texto: pedido.statusTexto, tipo: pedido.statusTipo),
              if (pedido.remoto)
                const ChipStatus(
                  key: ValueKey('selo-remoto'),
                  texto: 'Remoto',
                  tipo: TipoStatus.info,
                  icone: Icons.videocam_outlined,
                ),
              if (pedido.urgente)
                const ChipStatus(
                  key: ValueKey('selo-urgente'),
                  texto: 'Urgente',
                  tipo: TipoStatus.destaque,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
