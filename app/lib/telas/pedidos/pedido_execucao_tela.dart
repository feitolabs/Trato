import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';
import 'pecas.dart';
import 'recursos_mvp.dart';

/// Tela 16 — Serviço em execução. O app só mostra e pede: aprovar/recusar o aditivo
/// chama os callbacks (o backend decide); o estado local é provisório.
class PedidoExecucaoTela extends StatefulWidget {
  const PedidoExecucaoTela({
    super.key,
    this.pedido = DadosExemplo.pedidoEmExecucao,
    this.aoAprovarAditivo,
    this.aoRecusarAditivo,
    this.aoTocarSos,
    this.aoConversar,
    this.aoVerConclusao,
  });

  final PedidoEmExecucao pedido;
  final VoidCallback? aoAprovarAditivo;
  final VoidCallback? aoRecusarAditivo;
  final VoidCallback? aoTocarSos;
  final VoidCallback? aoConversar;
  final VoidCallback? aoVerConclusao;

  @override
  State<PedidoExecucaoTela> createState() => _PedidoExecucaoTelaState();
}

class _PedidoExecucaoTelaState extends State<PedidoExecucaoTela> {
  late Aditivo? _aditivo = widget.pedido.aditivo;

  void _decidir(EstadoAditivo estado, VoidCallback? aviso) {
    setState(() => _aditivo = _aditivo?.comEstado(estado));
    aviso?.call();
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ConteudoResponsivo(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
                  children: [
                    _Topo(numero: pedido.numero, aoTocarSos: widget.aoTocarSos),
                    const SizedBox(height: EspacosTrato.x3),
                    Text(pedido.titulo, style: TipografiaTrato.tituloGrande),
                    const SizedBox(height: EspacosTrato.x3),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: ChipStatus(
                        texto: 'Pagamento acompanhado no app',
                        tipo: TipoStatus.info,
                        icone: Icons.lock_outline,
                      ),
                    ),
                    if (_aditivo != null) ...[
                      const SizedBox(height: EspacosTrato.x4),
                      CartaoAditivo(
                        aditivo: _aditivo!,
                        aoRecusar: () => _decidir(EstadoAditivo.recusado, widget.aoRecusarAditivo),
                        aoAprovar: () => _decidir(EstadoAditivo.aprovado, widget.aoAprovarAditivo),
                      ),
                    ],
                    const SizedBox(height: EspacosTrato.x6),
                    Text('Linha do tempo', style: TipografiaTrato.titulo),
                    const SizedBox(height: EspacosTrato.x4),
                    LinhaDoTempo(etapas: pedido.etapas),
                    const SizedBox(height: EspacosTrato.x6),
                    Row(
                      children: [
                        for (var i = 0; i < pedido.fotos.length; i++) ...[
                          if (i > 0) const SizedBox(width: EspacosTrato.x3),
                          Expanded(child: EspacoFoto(rotulo: pedido.fotos[i], altura: 100)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _Rodape(aoConversar: widget.aoConversar, aoVerConclusao: widget.aoVerConclusao),
          ],
        ),
      ),
    );
  }
}

class _Topo extends StatelessWidget {
  const _Topo({required this.numero, required this.aoTocarSos});

  final String numero;
  final VoidCallback? aoTocarSos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Voltar',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          ),
          Expanded(
            child: Text(
              'Pedido $numero',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            ),
          ),
          if (kSosHabilitado) BotaoSos(aoTocar: aoTocarSos),
        ],
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({required this.aoConversar, required this.aoVerConclusao});

  final VoidCallback? aoConversar;
  final VoidCallback? aoVerConclusao;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CoresTrato.superficie,
        border: Border(top: BorderSide(color: CoresTrato.borda)),
      ),
      child: ConteudoResponsivo(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
          child: Row(
            children: [
              Expanded(
                child: BotaoSecundario(
                  texto: 'Conversar',
                  icone: Icons.chat_bubble_outline,
                  aoTocar: aoConversar ?? () {},
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                  child: BotaoSecundario(texto: 'Ver conclusão', aoTocar: aoVerConclusao ?? () {})),
            ],
          ),
        ),
      ),
    );
  }
}
