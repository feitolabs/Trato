import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../cliente/modelos.dart';
import '../comuns/estados.dart';

/// Todas as categorias ativas do catálogo, com busca por nome. Serve para explorar e também
/// para escolher a categoria do pedido ([titulo] muda). Só mostra o que o catálogo devolveu.
class TodasCategoriasTela extends StatelessWidget {
  const TodasCategoriasTela({
    super.key,
    required this.carregar,
    required this.aoEscolher,
    this.titulo = 'Todas as categorias',
  });

  final Future<List<CategoriaServico>> Function() carregar;
  final ValueChanged<CategoriaServico> aoEscolher;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: titulo,
      child: CarregadorTela<List<CategoriaServico>>(
        carregar: carregar,
        construir: (context, itens, _) => itens.isEmpty
            ? const EstadoVazio(
                icone: Icons.grid_view,
                titulo: 'Nenhuma categoria por enquanto',
                texto: 'Quando houver serviços disponíveis, eles aparecem aqui.',
              )
            : _Grade(itens: itens, aoEscolher: aoEscolher),
      ),
    );
  }
}

class _Grade extends StatefulWidget {
  const _Grade({required this.itens, required this.aoEscolher});

  final List<CategoriaServico> itens;
  final ValueChanged<CategoriaServico> aoEscolher;

  @override
  State<_Grade> createState() => _GradeState();
}

class _GradeState extends State<_Grade> {
  final _campo = TextEditingController();

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  static String _sem(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final termo = _sem(_campo.text.trim());
    final lista = [
      for (final c in widget.itens)
        if (termo.isEmpty || _sem(c.nome).contains(termo) || _sem(c.descricao).contains(termo)) c,
    ];
    final escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _campo,
          style: TipografiaTrato.corpo,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Buscar categoria',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Expanded(
          child: lista.isEmpty
              ? EstadoVazio(
                  icone: Icons.search_off,
                  titulo: 'Nenhuma categoria encontrada',
                  texto: 'Não achamos "${_campo.text.trim()}". Tente outro nome.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisExtent: 116 * escala,
                    mainAxisSpacing: EspacosTrato.x3,
                    crossAxisSpacing: EspacosTrato.x3,
                  ),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _Bloco(
                    categoria: lista[i],
                    aoTocar: () => widget.aoEscolher(lista[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.categoria, required this.aoTocar});

  final CategoriaServico categoria;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raioGrande);
    return Semantics(
      button: true,
      label: 'Categoria ${categoria.nome}',
      excludeSemantics: true,
      child: Material(
        color: CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: const BorderSide(color: CoresTrato.borda),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(categoria.icone, size: 28, color: CoresTrato.petroleo),
                const SizedBox(height: EspacosTrato.x2),
                Flexible(
                  child: Text(
                    categoria.nome,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TipografiaTrato.corpoForte,
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
