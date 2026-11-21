import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import 'modelos.dart';

/// Tela 15 — Seus pedidos, com abas "Em andamento" e "Finalizados", busca e atualização.
class SeusPedidosTela extends StatefulWidget {
  const SeusPedidosTela({
    super.key,
    required this.emAndamento,
    required this.finalizados,
    this.aoAbrirPedido,
    this.aoFazerPedido,
  });

  final List<PedidoResumo> emAndamento;
  final List<PedidoResumo> finalizados;
  final ValueChanged<PedidoResumo>? aoAbrirPedido;

  /// Ação do estado vazio de "Em andamento" (abre o novo pedido).
  final VoidCallback? aoFazerPedido;

  @override
  State<SeusPedidosTela> createState() => _SeusPedidosTelaState();
}

class _SeusPedidosTelaState extends State<SeusPedidosTela> {
  final _busca = TextEditingController();
  bool _verFinalizados = false;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pedidosDaAba = _verFinalizados ? widget.finalizados : widget.emAndamento;
    final termo = normalizarTextoBusca(_busca.text);
    final pedidos = termo.isEmpty
        ? pedidosDaAba
        : [
            for (final p in pedidosDaAba)
              if (normalizarTextoBusca(p.titulo).contains(termo) ||
                  normalizarTextoBusca(p.subtitulo).contains(termo) ||
                  normalizarTextoBusca(p.profissionalNome).contains(termo) ||
                  normalizarTextoBusca(p.statusTexto).contains(termo))
                p,
          ];
    final recarregar = AtualizadorTela.de(context);
    final mostrarBusca =
        widget.emAndamento.isNotEmpty || widget.finalizados.isNotEmpty || _busca.text.isNotEmpty;

    final lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: EspacosTrato.x6, bottom: EspacosTrato.x4),
      children: [
        Text('Seus pedidos', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x4),
        _Abas(
          finalizados: _verFinalizados,
          aoTrocar: (finalizados) => setState(() => _verFinalizados = finalizados),
        ),
        if (mostrarBusca) ...[
          const SizedBox(height: EspacosTrato.x4),
          TextField(
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
            texto: 'Não achamos "${_busca.text.trim()}" nesta aba.',
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
        child: ConteudoResponsivo(
          child: recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista),
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
          if ((pedido.descricao ?? '').isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              pedido.descricao!,
              key: const ValueKey('descricao-do-pedido'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TipografiaTrato.corpo,
            ),
          ],
          const SizedBox(height: EspacosTrato.x2),
          Text(
            pedido.subtitulo,
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
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
