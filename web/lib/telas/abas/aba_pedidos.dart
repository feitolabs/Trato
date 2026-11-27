import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../dados/erros.dart';
import '../../dados/pedidos.dart';
import '../../tema/tema.dart';

/// Pedidos: lista real de `GET /v1/pedidos` ("Meus pedidos" da conta logada).
/// [cabecalho] entra acima da lista (usado pelo profissional, que não tem aba "Início" própria,
/// igual ao painel do PDF de referência).
class AbaPedidos extends StatefulWidget {
  const AbaPedidos({super.key, required this.repositorio, this.cabecalho});

  final RepositorioPedidos repositorio;
  final Widget? cabecalho;

  @override
  State<AbaPedidos> createState() => _AbaPedidosState();
}

class _AbaPedidosState extends State<AbaPedidos> {
  late Future<List<PedidoResumo>> _futuro = widget.repositorio.listar();

  Future<void> _recarregar() async {
    setState(() => _futuro = widget.repositorio.listar());
    await _futuro;
  }

  @override
  Widget build(BuildContext context) {
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final cabecalho = widget.cabecalho;
    return ConteudoResponsivo(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cabecalho == null) ...[
            const SizedBox(height: EspacosTrato.x4),
            Text('Pedidos', style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo)),
            const SizedBox(height: EspacosTrato.x3),
          ],
          Expanded(
            child: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<List<PedidoResumo>>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  ?cabecalho,
                  const SizedBox(height: EspacosTrato.x8),
                  Center(
                    child: Text(
                      mensagemErroTrato(snapshot.error!),
                      textAlign: TextAlign.center,
                      style: TipografiaTrato.corpo.copyWith(color: CoresTrato.vermelhoTexto),
                    ),
                  ),
                ],
              );
            }
            final pedidos = snapshot.data ?? const [];
            if (pedidos.isEmpty) {
              return ListView(
                children: [
                  ?cabecalho,
                  const SizedBox(height: EspacosTrato.x8),
                  Center(
                    child: Text(
                      'Nenhum pedido ainda.',
                      style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoDica),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
              itemCount: pedidos.length + (cabecalho != null ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (_, indice) {
                if (cabecalho != null) {
                  if (indice == 0) return cabecalho;
                  return _CartaoPedido(pedido: pedidos[indice - 1], formatoData: formatoData);
                }
                return _CartaoPedido(pedido: pedidos[indice], formatoData: formatoData);
              },
            );
          },
        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoPedido extends StatelessWidget {
  const _CartaoPedido({required this.pedido, required this.formatoData});

  final PedidoResumo pedido;
  final DateFormat formatoData;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pedido.estadoNome,
                    style: TipografiaTrato.tituloCartao.copyWith(color: CoresTrato.petroleo),
                  ),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    'Aberto em ${formatoData.format(pedido.abertoEm)}',
                    style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                  ),
                ],
              ),
            ),
            if (pedido.urgente)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x2, vertical: 2),
                decoration: BoxDecoration(
                  color: CoresTrato.ambarSuave,
                  borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                ),
                child: Text(
                  'Urgente',
                  style: TipografiaTrato.legenda.copyWith(color: CoresTrato.ambarTexto),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
