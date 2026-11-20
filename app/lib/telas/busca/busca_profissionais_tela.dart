import 'dart:async';

import 'package:flutter/material.dart';

import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_de_usuario.dart';
import '../cliente/modelos.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import '../pedido_novo/pecas_pedido.dart' show ChipOpcao;
import 'modelos.dart';

/// F5.4 — Busca de profissional ou serviço (busca ao digitar, filtros, recentes e categorias).
class BuscaProfissionaisTela extends StatefulWidget {
  const BuscaProfissionaisTela({
    super.key,
    required this.servico,
    this.aoAbrirProfissional,
    this.termoInicial = '',
    this.sugestoes = const [],
    this.aoEscolherCategoria,
    this.aoVerTodas,
  });

  /// Toque numa categoria das sugestões. Sem isso, o toque busca pelo nome da categoria.
  final ValueChanged<CategoriaServico>? aoEscolherCategoria;

  /// Toque em "Ver todas" nas sugestões.
  final VoidCallback? aoVerTodas;

  final ServicoBusca servico;
  final ValueChanged<Profissional>? aoAbrirProfissional;
  final String termoInicial;

  /// Categorias mostradas antes de qualquer busca.
  final List<CategoriaServico> sugestoes;

  @override
  State<BuscaProfissionaisTela> createState() => _BuscaProfissionaisTelaState();
}

class _BuscaProfissionaisTelaState extends State<BuscaProfissionaisTela> {
  late final _campo = TextEditingController(text: widget.termoInicial);
  final List<String> _recentes = [];
  Timer? _debounce;
  Future<List<Profissional>>? _busca;
  var _termo = '';
  var _soHoje = false;
  var _notaAlta = false;

  @override
  void initState() {
    super.initState();
    if (widget.termoInicial.trim().isNotEmpty) {
      _buscar(widget.termoInicial, registrar: false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _campo.dispose();
    super.dispose();
  }

  void _registrarRecente(String termo) {
    final limpo = termo.trim();
    if (limpo.length < 2) return;
    _recentes.removeWhere((e) => e.toLowerCase() == limpo.toLowerCase());
    _recentes.insert(0, limpo);
    if (_recentes.length > 5) _recentes.removeRange(5, _recentes.length);
  }

  void _aoDigitar(String texto) {
    _debounce?.cancel();
    setState(() {});
    final termo = texto.trim();
    if (termo.isEmpty) {
      setState(() {
        _termo = '';
        _busca = null;
      });
      return;
    }
    if (termo.length < 2) {
      setState(() {
        _termo = termo;
        _busca = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) _buscar(termo, registrar: false);
    });
  }

  void _buscar(String texto, {bool registrar = true}) {
    _debounce?.cancel();
    final termo = texto.trim();
    if (termo.isEmpty) {
      setState(() {
        _termo = '';
        _busca = null;
      });
      return;
    }
    if (termo.length < 2) {
      setState(() {
        _termo = termo;
        _busca = null;
      });
      return;
    }
    if (registrar) _registrarRecente(termo);
    setState(() {
      _termo = termo;
      _busca = widget.servico.buscar(termo);
    });
  }

  Future<void> _recarregarBusca() async {
    if (_termo.length < 2) {
      await AtualizadorTela.de(context)?.call();
      return;
    }
    final futuro = widget.servico.buscar(_termo);
    setState(() => _busca = futuro);
    await futuro;
  }

  void _limpar() {
    _debounce?.cancel();
    _campo.clear();
    setState(() {
      _termo = '';
      _busca = null;
      _soHoje = false;
      _notaAlta = false;
    });
  }

  List<CategoriaServico> _sugestoesOrdenadas() {
    final verTodas = <CategoriaServico>[];
    final outras = <CategoriaServico>[];
    for (final c in widget.sugestoes) {
      if (c.nome == 'Ver todas') {
        verTodas.add(c);
      } else {
        outras.add(c);
      }
    }
    outras.sort((a, b) => compararAlfabeticoPtBr(a.nome, b.nome));
    return [...outras, ...verTodas];
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Buscar',
      comVoltar: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _campo,
            style: TipografiaTrato.corpo,
            textInputAction: TextInputAction.search,
            onChanged: _aoDigitar,
            onSubmitted: _buscar,
            decoration: InputDecoration(
              hintText: 'Serviço, especialidade, bairro ou nome',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: EspacosTrato.x4, right: EspacosTrato.x3),
                child: Icon(Icons.search, size: 22, color: CoresTrato.petroleo),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: EspacosTrato.alturaCampo,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_campo.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _limpar,
                    ),
                  IconButton(
                    tooltip: 'Buscar',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _buscar(_campo.text),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: EspacosTrato.x4),
          Expanded(
            child: _busca == null ? _antesDaBusca() : _resultado(),
          ),
        ],
      ),
    );
  }

  Widget _antesDaBusca() {
    if (_termo.length == 1) {
      return const EstadoVazio(
        icone: Icons.edit_outlined,
        titulo: 'Continue digitando',
        texto: 'Digite pelo menos 2 letras para buscar serviços, bairros ou profissionais.',
      );
    }
    final atualizador = AtualizadorTela.de(context);
    final conteudo = _Sugestoes(
      sugestoes: _sugestoesOrdenadas(),
      recentes: _recentes,
      aoLimparRecentes: () => setState(_recentes.clear),
      aoEscolherRecente: _escolher,
      aoEscolherCategoria: widget.aoEscolherCategoria,
      aoVerTodas: widget.aoVerTodas,
      aoEscolherTexto: _escolher,
    );
    if (atualizador == null) return conteudo;
    return RefreshIndicator(onRefresh: atualizador, child: conteudo);
  }

  void _escolher(String nome) {
    _campo.text = nome;
    _campo.selection = TextSelection.collapsed(offset: nome.length);
    _buscar(nome);
  }

  Widget _resultado() {
    return FutureBuilder<List<Profissional>>(
      key: ValueKey(_busca),
      future: _busca,
      builder: (context, snap) {
        if (snap.hasError) {
          return RefreshIndicator(
            onRefresh: _recarregarBusca,
            child: EstadoErro(
              mensagem: mensagemErroTrato(snap.error!),
              aoTentarNovamente: () => _buscar(_termo),
            ),
          );
        }
        if (!snap.hasData) return const EstadoCarregando();
        final brutos = snap.data!;
        final filtrados = [
          for (final p in brutos)
            if ((!_soHoje || p.atendeHoje) && (!_notaAlta || p.nota >= 4.5)) p,
        ];

        final barraFiltros = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChipOpcao(
                texto: 'Atende hoje',
                marcado: _soHoje,
                aoTocar: () => setState(() => _soHoje = !_soHoje),
              ),
              const SizedBox(width: EspacosTrato.x2),
              ChipOpcao(
                texto: 'Nota 4,5+',
                marcado: _notaAlta,
                aoTocar: () => setState(() => _notaAlta = !_notaAlta),
              ),
            ],
          ),
        );

        if (brutos.isEmpty) {
          return RefreshIndicator(
            onRefresh: _recarregarBusca,
            child: EstadoVazio(
              icone: Icons.search_off,
              titulo: 'Nada encontrado',
              texto:
                  'Não achamos resultados para "$_termo". Tente outro serviço, bairro ou categoria.',
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            barraFiltros,
            const SizedBox(height: EspacosTrato.x3),
            Expanded(
              child: filtrados.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _recarregarBusca,
                      child: EstadoVazio(
                        icone: Icons.filter_alt_off_outlined,
                        titulo: 'Nenhum resultado com esses filtros',
                        texto: 'Limpe os filtros acima para ver todos os resultados de "$_termo".',
                        textoAcao: 'Limpar filtros',
                        aoAcao: () => setState(() {
                          _soHoje = false;
                          _notaAlta = false;
                        }),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _recarregarBusca,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                        itemCount: filtrados.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return Text(
                              '${filtrados.length} ${filtrados.length == 1 ? 'resultado' : 'resultados'}',
                              style: TipografiaTrato.corpoPequeno
                                  .copyWith(color: CoresTrato.textoSecundario),
                            );
                          }
                          final p = filtrados[i - 1];
                          return _CartaoResultado(
                            profissional: p,
                            aoTocar: () {
                              _registrarRecente(_termo);
                              widget.aoAbrirProfissional?.call(p);
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Sugestoes extends StatelessWidget {
  const _Sugestoes({
    required this.sugestoes,
    required this.recentes,
    required this.aoLimparRecentes,
    required this.aoEscolherRecente,
    required this.aoEscolherCategoria,
    required this.aoVerTodas,
    required this.aoEscolherTexto,
  });

  final List<CategoriaServico> sugestoes;
  final List<String> recentes;
  final VoidCallback aoLimparRecentes;
  final ValueChanged<String> aoEscolherRecente;
  final ValueChanged<CategoriaServico>? aoEscolherCategoria;
  final VoidCallback? aoVerTodas;
  final ValueChanged<String> aoEscolherTexto;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recentes.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: Text('BUSCAS RECENTES', style: TipografiaTrato.sobretitulo)),
                TextButton(
                  onPressed: aoLimparRecentes,
                  child: const Text('Limpar'),
                ),
              ],
            ),
            const SizedBox(height: EspacosTrato.x2),
            Wrap(
              spacing: EspacosTrato.x2,
              runSpacing: EspacosTrato.x2,
              children: [
                for (final termo in recentes)
                  ActionChip(
                    avatar: const Icon(Icons.history, size: 18, color: CoresTrato.petroleo),
                    label: Text(termo, style: TipografiaTrato.corpoPequeno),
                    backgroundColor: CoresTrato.superficie,
                    side: const BorderSide(color: CoresTrato.borda),
                    onPressed: () => aoEscolherRecente(termo),
                  ),
              ],
            ),
            const SizedBox(height: EspacosTrato.x5),
          ],
          Text('CATEGORIAS', style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (final c in sugestoes)
                ActionChip(
                  avatar: Icon(c.icone, size: 18, color: CoresTrato.petroleo),
                  label: Text(c.nome, style: TipografiaTrato.corpoPequeno),
                  backgroundColor: CoresTrato.superficie,
                  side: const BorderSide(color: CoresTrato.borda),
                  onPressed: () {
                    if (c.nome == 'Ver todas' && aoVerTodas != null) {
                      aoVerTodas!();
                    } else if (aoEscolherCategoria != null && c.nome != 'Ver todas') {
                      aoEscolherCategoria!(c);
                    } else {
                      aoEscolherTexto(c.nome);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartaoResultado extends StatelessWidget {
  const _CartaoResultado({required this.profissional, required this.aoTocar});

  final Profissional profissional;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final p = profissional;
    return Semantics(
      button: true,
      label: '${p.nome}, ${p.especialidade}, nota ${p.nota}',
      excludeSemantics: true,
      child: Material(
        color: CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: const BorderSide(color: CoresTrato.borda),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              children: [
                AvatarDeUsuario(iniciais: p.iniciais, usuarioId: p.id),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nome, style: TipografiaTrato.tituloCartao),
                      Text(
                        p.especialidade,
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: CoresTrato.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        '${p.nota.toStringAsFixed(1).replaceAll('.', ',')} · '
                        '${p.servicosConcluidos} ${p.servicosConcluidos == 1 ? 'serviço' : 'serviços'}'
                        '${p.regiao != null && p.regiao!.isNotEmpty ? ' · ${p.regiao}' : ''}'
                        '${p.distanciaKm > 0 ? ' · ${p.distanciaKm.toStringAsFixed(1).replaceAll('.', ',')} km' : ''}',
                        style: TipografiaTrato.legenda,
                      ),
                      if (p.atendeHoje) ...[
                        const SizedBox(height: EspacosTrato.x1),
                        Text(
                          'Atende hoje',
                          style: TipografiaTrato.legenda.copyWith(
                            color: CoresTrato.petroleo,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: CoresTrato.petroleo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
