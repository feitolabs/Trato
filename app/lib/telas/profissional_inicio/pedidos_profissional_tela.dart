import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'inicio_profissional_tela.dart' show CartaoPedidoAberto;
import 'modelos.dart';

/// Aba Pedidos do profissional: pedidos abertos (com filtros) e, ao lado, as conversas.
/// A lista e os filtros são os mesmos do Início; quem filtra é o backend.
class PedidosProfissionalTela extends StatefulWidget {
  const PedidosProfissionalTela({
    super.key,
    required this.pedidos,
    required this.conversas,
    this.carregando = false,
    this.filtrosAtivos = 0,
    this.aoAbrirFiltros,
    this.aoAbrirPedido,
  });

  final List<PedidoAberto> pedidos;

  /// Lista de conversas (aba "Conversas").
  final Widget conversas;
  final bool carregando;

  /// Quantos filtros estão ligados (para o contador do botão).
  final int filtrosAtivos;
  final VoidCallback? aoAbrirFiltros;
  final ValueChanged<PedidoAberto>? aoAbrirPedido;

  @override
  State<PedidosProfissionalTela> createState() => _PedidosProfissionalTelaState();
}

class _PedidosProfissionalTelaState extends State<PedidosProfissionalTela> {
  var _conversas = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: EspacosTrato.x4),
              Text('Pedidos', style: TipografiaTrato.tituloGrande),
              const SizedBox(height: EspacosTrato.x4),
              Row(
                children: [
                  _Segmento(
                    texto: 'Abertos',
                    ativo: !_conversas,
                    aoTocar: () => setState(() => _conversas = false),
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  _Segmento(
                    texto: 'Conversas',
                    ativo: _conversas,
                    aoTocar: () => setState(() => _conversas = true),
                  ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x3),
              Expanded(child: _conversas ? widget.conversas : _abertos()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _abertos() {
    if (widget.carregando) return const EstadoCarregando();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoSecundario(
            texto: widget.filtrosAtivos == 0 ? 'Filtros' : 'Filtros (${widget.filtrosAtivos})',
            icone: Icons.tune,
            aoTocar: widget.aoAbrirFiltros,
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Expanded(
          child: widget.pedidos.isEmpty
              ? EstadoVazio(
                  icone: Icons.inbox_outlined,
                  titulo: 'Nenhum pedido aberto',
                  texto: widget.filtrosAtivos == 0
                      ? 'Quando chegar um pedido da sua região e categoria, ele aparece aqui.'
                      : 'Nenhum pedido combina com os filtros. Tente mudar ou limpar.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                  itemCount: widget.pedidos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                  itemBuilder: (_, i) => CartaoPedidoAberto(
                    pedido: widget.pedidos[i],
                    aoTocar: widget.aoAbrirPedido == null
                        ? null
                        : () => widget.aoAbrirPedido!(widget.pedidos[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Segmento extends StatelessWidget {
  const _Segmento({required this.texto, required this.ativo, required this.aoTocar});

  final String texto;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ativo,
      child: Material(
        color: ativo ? CoresTrato.petroleo : CoresTrato.superficie,
        shape: StadiumBorder(
          side: BorderSide(color: ativo ? CoresTrato.petroleo : CoresTrato.borda),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x5,
              vertical: EspacosTrato.x3,
            ),
            child: Text(
              texto,
              style: TipografiaTrato.corpoForte.copyWith(
                color: ativo ? CoresTrato.creme : CoresTrato.petroleo,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
