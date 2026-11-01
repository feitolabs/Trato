import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/modelos.dart';
import '../comuns/estados.dart';

/// Cartão de um serviço do cliente (Início e lista de serviços recentes).
class CartaoServicoRecente extends StatelessWidget {
  const CartaoServicoRecente({super.key, required this.servico, required this.aoTocar});

  final ServicoRecente servico;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final finalizado = servico.statusTexto == 'Finalizado';
    final quando = servico.profissional.isEmpty
        ? servico.data
        : '${servico.profissional} · ${servico.data}';
    return CartaoTrato(
      aoTocar: aoTocar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(servico.titulo, style: TipografiaTrato.tituloCartao),
              ChipStatus(
                texto: servico.statusTexto,
                tipo: finalizado ? TipoStatus.sucesso : TipoStatus.info,
                icone: finalizado ? Icons.check : null,
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            quando,
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          ),
          if (servico.garantia != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 20, color: CoresTrato.azulTexto),
                const SizedBox(width: EspacosTrato.x2),
                Expanded(
                  child: Text(
                    servico.garantia!,
                    style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
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

/// Lista completa dos serviços do cliente. Tocar abre o detalhe do serviço.
class ServicosRecentesTela extends StatelessWidget {
  const ServicosRecentesTela({super.key, required this.carregar, required this.aoAbrir});

  final Future<List<ServicoRecente>> Function() carregar;
  final ValueChanged<ServicoRecente> aoAbrir;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Serviços recentes',
      child: CarregadorTela<List<ServicoRecente>>(
        carregar: carregar,
        construir: (context, itens, _) => itens.isEmpty
            ? const EstadoVazio(
                icone: Icons.history,
                titulo: 'Nenhum serviço ainda',
                texto: 'Os serviços que você contratar aparecem aqui, com a garantia de cada um.',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                itemCount: itens.length,
                separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                itemBuilder: (_, i) =>
                    CartaoServicoRecente(servico: itens[i], aoTocar: () => aoAbrir(itens[i])),
              ),
      ),
    );
  }
}
