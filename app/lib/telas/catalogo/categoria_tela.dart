import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/repositorios_catalogo.dart';
import '../../tema/tema.dart';
import '../cliente/modelos.dart';
import '../comuns/estados.dart';
import '../pedido_novo/pecas_pedido.dart';
import 'pecas_catalogo.dart';

/// Uma categoria: cabeçalho, filtros e a lista de profissionais. Os filtros (bairro, faixa de
/// preço, avaliação e disponibilidade) são pedidos ao catálogo; quem filtra é o backend.
/// "Pedir orçamento" abre o Novo pedido já com a categoria (e, se vier de um cartão, o
/// profissional que o cliente quer convidar).
class CategoriaTela extends StatefulWidget {
  const CategoriaTela({
    super.key,
    required this.categoria,
    required this.carregar,
    this.aoAbrirProfissional,
    this.aoPedirOrcamento,
  });

  final CategoriaServico categoria;
  final Future<List<Profissional>> Function(FiltroProfissionais filtro) carregar;
  final ValueChanged<Profissional>? aoAbrirProfissional;

  /// [profissional] é nulo no botão geral da categoria.
  final void Function(Profissional? profissional)? aoPedirOrcamento;

  @override
  State<CategoriaTela> createState() => _CategoriaTelaState();
}

class _CategoriaTelaState extends State<CategoriaTela> {
  var _filtro = const FiltroProfissionais();
  late Future<List<Profissional>> _futuro = widget.carregar(_filtro);

  void _recarregar() => setState(() => _futuro = widget.carregar(_filtro));

  Future<void> _filtros() async {
    final novo = await mostrarFiltrosProfissionais(context, atual: _filtro);
    if (novo == null || !mounted) return;
    _filtro = novo;
    _recarregar();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.categoria;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: CoresTrato.azulClaro,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(c.icone, color: CoresTrato.petroleo),
                  ),
                  const SizedBox(width: EspacosTrato.x3),
                  Expanded(child: Text(c.nome, style: TipografiaTrato.tituloGrande)),
                ],
              ),
              if (c.descricao.isNotEmpty) ...[
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  c.descricao,
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
              const SizedBox(height: EspacosTrato.x4),
              Align(
                alignment: Alignment.centerLeft,
                child: BotaoSecundario(
                  texto: _filtro.vazio ? 'Filtros' : 'Filtros (${_filtro.ativos})',
                  icone: Icons.tune,
                  aoTocar: _filtros,
                ),
              ),
              const SizedBox(height: EspacosTrato.x3),
              Expanded(
                child: FutureBuilder<List<Profissional>>(
                  key: ValueKey(_futuro),
                  future: _futuro,
                  builder: (context, snap) {
                    if (snap.hasError) return EstadoErro(aoTentarNovamente: _recarregar);
                    if (!snap.hasData) return const EstadoCarregando();
                    final lista = snap.data!;
                    if (lista.isEmpty) {
                      return EstadoVazio(
                        icone: Icons.person_search_outlined,
                        titulo: 'Nenhum profissional encontrado',
                        texto: _filtro.vazio
                            ? 'Ainda não há profissionais em ${c.nome}. '
                                'Peça um orçamento e avisamos quem atende.'
                            : 'Nenhum profissional combina com os filtros. Tente mudar ou limpar.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                      itemCount: lista.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return Text(
                            '${lista.length} ${lista.length == 1 ? 'profissional' : 'profissionais'}',
                            style: TipografiaTrato.corpoPequeno
                                .copyWith(color: CoresTrato.textoSecundario),
                          );
                        }
                        final p = lista[i - 1];
                        return CartaoProfissional(
                          profissional: p,
                          aoAbrir: () => widget.aoAbrirProfissional?.call(p),
                          aoPedirOrcamento: widget.aoPedirOrcamento == null
                              ? null
                              : () => widget.aoPedirOrcamento!(p),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.aoPedirOrcamento == null
          ? null
          : BarraAcaoInferior(
              child: BotaoPrimario(
                texto: 'Pedir orçamento em ${c.nome}',
                aoTocar: () => widget.aoPedirOrcamento!(null),
              ),
            ),
    );
  }
}

/// Folha com os filtros da categoria. Devolve o novo filtro ou nulo se o cliente fechar.
Future<FiltroProfissionais?> mostrarFiltrosProfissionais(
  BuildContext context, {
  FiltroProfissionais atual = const FiltroProfissionais(),
}) {
  return showModalBottomSheet<FiltroProfissionais>(
    context: context,
    isScrollControlled: true,
    backgroundColor: CoresTrato.creme,
    builder: (_) => _FolhaFiltros(atual: atual),
  );
}

class _FolhaFiltros extends StatefulWidget {
  const _FolhaFiltros({required this.atual});

  final FiltroProfissionais atual;

  @override
  State<_FolhaFiltros> createState() => _FolhaFiltrosState();
}

class _FolhaFiltrosState extends State<_FolhaFiltros> {
  static const _precos = [(null, 'Qualquer'), (8000, 'Até R\$ 80'), (12000, 'Até R\$ 120'), (18000, 'Até R\$ 180')];
  static const _notas = [(null, 'Qualquer'), (4.5, '4,5 ou mais'), (4.8, '4,8 ou mais')];

  late final _bairro = TextEditingController(text: widget.atual.bairro ?? '');
  late int? _preco = widget.atual.precoMaxCentavos;
  late double? _nota = widget.atual.notaMinima;
  late bool _hoje = widget.atual.soDisponiveisHoje;

  @override
  void dispose() {
    _bairro.dispose();
    super.dispose();
  }

  FiltroProfissionais get _filtro => FiltroProfissionais(
        bairro: _bairro.text.trim().isEmpty ? null : _bairro.text.trim(),
        precoMaxCentavos: _preco,
        notaMinima: _nota,
        soDisponiveisHoje: _hoje,
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(EspacosTrato.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Filtros', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x4),
              const RotuloSecao('Bairro'),
              const SizedBox(height: EspacosTrato.x2),
              TextField(
                controller: _bairro,
                style: TipografiaTrato.corpo,
                decoration: const InputDecoration(hintText: 'Ex.: Savassi'),
              ),
              const SizedBox(height: EspacosTrato.x4),
              const RotuloSecao('Faixa de preço'),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  for (final (valor, rotulo) in _precos)
                    ChipOpcao(
                      texto: rotulo,
                      marcado: _preco == valor,
                      aoTocar: () => setState(() => _preco = valor),
                    ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x4),
              const RotuloSecao('Avaliação'),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  for (final (valor, rotulo) in _notas)
                    ChipOpcao(
                      texto: rotulo,
                      marcado: _nota == valor,
                      aoTocar: () => setState(() => _nota = valor),
                    ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x4),
              MergeSemantics(
                child: Row(
                  children: [
                    const Expanded(child: RotuloSecao('Atende hoje')),
                    Switch(
                      value: _hoje,
                      onChanged: (v) => setState(() => _hoje = v),
                      activeTrackColor: CoresTrato.petroleo,
                      activeThumbColor: CoresTrato.creme,
                      inactiveTrackColor: CoresTrato.borda,
                      inactiveThumbColor: CoresTrato.superficie,
                      trackOutlineColor: const WidgetStatePropertyAll(CoresTrato.petroleo),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: EspacosTrato.x4),
              Row(
                children: [
                  Expanded(
                    child: BotaoSecundario(
                      texto: 'Limpar',
                      aoTocar: () => Navigator.of(context).pop(const FiltroProfissionais()),
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x3),
                  Expanded(
                    child: BotaoPrimario(
                      texto: 'Aplicar',
                      aoTocar: () => Navigator.of(context).pop(_filtro),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
