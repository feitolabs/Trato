import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';

/// Tela 15 — Seus pedidos, com abas "Em andamento" e "Finalizados".
/// A barra inferior fica por conta do esqueleto do app (quem liga as telas).
class SeusPedidosTela extends StatefulWidget {
  const SeusPedidosTela({
    super.key,
    this.emAndamento = DadosExemplo.pedidosEmAndamento,
    this.finalizados = DadosExemplo.pedidosFinalizados,
    this.aoAbrirPedido,
  });

  final List<PedidoResumo> emAndamento;
  final List<PedidoResumo> finalizados;
  final ValueChanged<PedidoResumo>? aoAbrirPedido;

  @override
  State<SeusPedidosTela> createState() => _SeusPedidosTelaState();
}

class _SeusPedidosTelaState extends State<SeusPedidosTela> {
  bool _verFinalizados = false;

  @override
  Widget build(BuildContext context) {
    final pedidos = _verFinalizados ? widget.finalizados : widget.emAndamento;
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: ListView(
            padding: const EdgeInsets.only(top: EspacosTrato.x6, bottom: EspacosTrato.x4),
            children: [
              Text('Seus pedidos', style: TipografiaTrato.tituloGrande),
              const SizedBox(height: EspacosTrato.x4),
              _Abas(
                finalizados: _verFinalizados,
                aoTrocar: (finalizados) => setState(() => _verFinalizados = finalizados),
              ),
              const SizedBox(height: EspacosTrato.x4),
              for (final pedido in pedidos) ...[
                _CartaoPedido(
                  pedido: pedido,
                  aoTocar: () => widget.aoAbrirPedido?.call(pedido),
                ),
                const SizedBox(height: EspacosTrato.x4),
              ],
            ],
          ),
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CoresTrato.borda)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Aba(
              texto: 'Em andamento',
              ativa: !finalizados,
              aoTocar: () => aoTrocar(false),
            ),
          ),
          Expanded(
            child: _Aba(texto: 'Finalizados', ativa: finalizados, aoTocar: () => aoTrocar(true)),
          ),
        ],
      ),
    );
  }
}

class _Aba extends StatelessWidget {
  const _Aba({required this.texto, required this.ativa, required this.aoTocar});

  final String texto;
  final bool ativa;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ativa,
      child: InkWell(
        onTap: aoTocar,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: ativa ? CoresTrato.petroleo : CoresTrato.creme,
                width: 2,
              ),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              texto,
              maxLines: 1,
              style: TipografiaTrato.corpoForte.copyWith(
                color: ativa ? CoresTrato.petroleo : CoresTrato.textoSecundario,
              ),
            ),
          ),
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
    return CartaoTrato(
      aoTocar: aoTocar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pedido.titulo, style: TipografiaTrato.tituloCartao),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            pedido.subtitulo,
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x3),
          ChipStatus(texto: pedido.statusTexto, tipo: pedido.statusTipo),
        ],
      ),
    );
  }
}
