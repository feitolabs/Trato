import 'package:flutter/material.dart';

import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_de_usuario.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

/// F5.12 — Mensagens: uma conversa por pedido (sem protótipo da lista; segue as vizinhas).
/// O toque chama [aoAbrirConversa]; quem liga as rotas abre `ChatPedidoTela`.
class MensagensTela extends StatelessWidget {
  const MensagensTela({
    super.key,
    required this.servico,
    this.aoAbrirConversa,
    this.comVoltar = false,
    this.atualizarACada,
    this.atualizarQuando,
    this.aoContarNaoLidas,
  });

  final ServicoMensagens servico;
  final ValueChanged<ConversaResumo>? aoAbrirConversa;

  /// Atualiza a lista sozinha neste intervalo (mensagem nova aparece sem fechar o app).
  final Duration? atualizarACada;

  /// Recarrega na hora quando dispara (ex.: ao voltar do chat).
  final Listenable? atualizarQuando;
  final ValueChanged<int>? aoContarNaoLidas;

  /// Falso por padrão: a tela é uma aba da casca do cliente.
  final bool comVoltar;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Mensagens',
      comVoltar: comVoltar,
      child: ListaConversas(
        servico: servico,
        aoAbrirConversa: aoAbrirConversa,
        atualizarACada: atualizarACada,
        atualizarQuando: atualizarQuando,
        aoContarNaoLidas: aoContarNaoLidas,
      ),
    );
  }
}

/// Só a lista de conversas (sem título nem moldura), para a aba Pedidos do profissional.
class ListaConversas extends StatelessWidget {
  const ListaConversas({
    super.key,
    required this.servico,
    this.aoAbrirConversa,
    this.textoVazio = 'Ao pedir um serviço, a conversa com o profissional aparece aqui.',
    this.atualizarACada,
    this.atualizarQuando,
    this.aoContarNaoLidas,
  });

  final Listenable? atualizarQuando;
  final ValueChanged<int>? aoContarNaoLidas;

  final ServicoMensagens servico;
  final ValueChanged<ConversaResumo>? aoAbrirConversa;
  final Duration? atualizarACada;
  final String textoVazio;

  @override
  Widget build(BuildContext context) {
    return CarregadorTela<List<ConversaResumo>>(
      carregar: () async {
        final lista = await servico.listar();
        aoContarNaoLidas?.call(lista.fold<int>(0, (soma, item) => soma + item.naoLidas));
        return lista;
      },
      atualizarACada: atualizarACada,
      atualizarQuando: atualizarQuando,
      construir: (context, itens, _) {
        final recarregar = AtualizadorTela.de(context);
        final Widget corpo = itens.isEmpty
            ? EstadoVazio(
                icone: Icons.chat_bubble_outline,
                titulo: 'Nenhuma conversa ainda',
                texto: textoVazio,
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
                itemCount: itens.length,
                separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
                itemBuilder: (_, i) =>
                    _LinhaConversa(item: itens[i], aoTocar: () => aoAbrirConversa?.call(itens[i])),
              );
        return recarregar == null ? corpo : RefreshIndicator(onRefresh: recarregar, child: corpo);
      },
    );
  }
}

class _LinhaConversa extends StatelessWidget {
  const _LinhaConversa({required this.item, required this.aoTocar});

  final ConversaResumo item;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final novas = item.naoLidas > 0;
    return Semantics(
      button: true,
      label: '${item.interlocutor}, ${item.tituloPedido}. ${item.ultimaMensagem}.'
          '${novas ? ' ${item.naoLidas} não lidas.' : ''}',
      excludeSemantics: true,
      child: Material(
        color: context.cores.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: BorderSide(color: context.cores.borda),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              children: [
                AvatarDeUsuario(iniciais: item.iniciais, usuarioId: item.outraParteId),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.interlocutor, style: TipografiaTrato.tituloCartao),
                      Text(
                        item.tituloPedido,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        item.ultimaMensagem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: novas
                            ? TipografiaTrato.corpoPequeno.copyWith(fontWeight: FontWeight.w700)
                            : TipografiaTrato.corpoPequeno,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: EspacosTrato.x2),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.quando,
                      style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
                    ),
                    if (novas) ...[
                      const SizedBox(height: EspacosTrato.x2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.cores.laranja,
                          borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                        ),
                        child: Text(
                          '${item.naoLidas}',
                          style: TipografiaTrato.legenda
                              .copyWith(color: context.cores.petroleo, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
