import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_de_usuario.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import 'modelos.dart';

enum _FiltroRapidoConversas {
  todas('Todas'),
  naoLidas('Não lidas'),
  emAndamento('Em andamento'),
  finalizadas('Finalizadas');

  const _FiltroRapidoConversas(this.rotulo);
  final String rotulo;
}

/// F5.12 / F60 — Mensagens: uma conversa por pedido, com busca, chips rápidos, código `#XXXX`,
/// selo de estado e destaque de não lidas.
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
    this.atualizarACada,
    this.atualizarQuando,
    this.aoContarNaoLidas,
    this.textoVazio =
        'Quando você conversar com um profissional sobre um pedido, a conversa aparece aqui.',
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
        if (itens.isEmpty) {
          final vazio = EstadoVazio(
            icone: Icons.chat_bubble_outline,
            titulo: 'Nenhuma conversa ainda',
            texto: textoVazio,
          );
          return recarregar == null ? vazio : RefreshIndicator(onRefresh: recarregar, child: vazio);
        }
        return _PainelConversas(
          itens: itens,
          aoAbrirConversa: aoAbrirConversa,
          aoRecarregar: recarregar,
        );
      },
    );
  }
}

class _PainelConversas extends StatefulWidget {
  const _PainelConversas({
    required this.itens,
    required this.aoAbrirConversa,
    required this.aoRecarregar,
  });

  final List<ConversaResumo> itens;
  final ValueChanged<ConversaResumo>? aoAbrirConversa;
  final Future<void> Function()? aoRecarregar;

  @override
  State<_PainelConversas> createState() => _PainelConversasState();
}

class _PainelConversasState extends State<_PainelConversas> {
  final _busca = TextEditingController();
  _FiltroRapidoConversas _filtro = _FiltroRapidoConversas.todas;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  bool _bateComBusca(ConversaResumo item, String termo) {
    if (termo.isEmpty) return true;
    return normalizarTextoBusca(item.interlocutor).contains(termo) ||
        normalizarTextoBusca(item.tituloPedido).contains(termo) ||
        normalizarTextoBusca(item.subtituloComCodigo).contains(termo) ||
        normalizarTextoBusca(item.codigoEfetivo).contains(termo) ||
        normalizarTextoBusca(item.ultimaMensagem).contains(termo) ||
        normalizarTextoBusca(item.estadoEfetivo).contains(termo);
  }

  bool _bateComChip(ConversaResumo item, _FiltroRapidoConversas chip) {
    return switch (chip) {
      _FiltroRapidoConversas.todas => true,
      _FiltroRapidoConversas.naoLidas => item.naoLidas > 0,
      _FiltroRapidoConversas.emAndamento => !item.encerrada,
      _FiltroRapidoConversas.finalizadas => item.encerrada,
    };
  }

  int _contarParaChip(_FiltroRapidoConversas chip, List<ConversaResumo> baseBusca) {
    return baseBusca.where((i) => _bateComChip(i, chip)).length;
  }

  void _limparFiltros() {
    setState(() {
      _busca.clear();
      _filtro = _FiltroRapidoConversas.todas;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final termo = normalizarTextoBusca(_busca.text);
    final baseBusca = [
      for (final item in widget.itens)
        if (_bateComBusca(item, termo)) item,
    ];
    final filtradas = [
      for (final item in baseBusca)
        if (_bateComChip(item, _filtro)) item,
    ];

    final Widget listaOuVazio = filtradas.isEmpty
        ? EstadoVazio(
            icone: Icons.search_off,
            titulo: 'Nenhuma conversa encontrada para este filtro',
            texto: 'Tente buscar outro nome ou código, ou volte para todas as conversas.',
            textoAcao: 'Limpar filtro',
            aoAcao: _limparFiltros,
          )
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: BarraAbasFlutuante.folgaInferior(context) + EspacosTrato.x4,
            ),
            itemCount: filtradas.length,
            separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
            itemBuilder: (_, i) => _LinhaConversa(
              item: filtradas[i],
              aoTocar: () => widget.aoAbrirConversa?.call(filtradas[i]),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('campo-busca-mensagens'),
          controller: _busca,
          style: TipografiaTrato.corpo,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar conversa, serviço ou #código',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      _busca.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _FiltroRapidoConversas.values.length; i++) ...[
                if (i > 0) const SizedBox(width: EspacosTrato.x2),
                Builder(
                  builder: (_) {
                    final chip = _FiltroRapidoConversas.values[i];
                    final qtd = _contarParaChip(chip, baseBusca);
                    final selecionado = _filtro == chip;
                    final rotulo = qtd > 0 ? '${chip.rotulo} ($qtd)' : chip.rotulo;
                    return Material(
                      key: ValueKey('chip-mensagens-${chip.name}'),
                      color: selecionado ? c.petroleo : c.superficie,
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: selecionado ? c.petroleo : c.bordaControle,
                          width: EspacosTrato.bordaFina,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => setState(() => _filtro = chip),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: EspacosTrato.x3 + 2,
                            vertical: EspacosTrato.x2,
                          ),
                          child: Text(
                            rotulo,
                            style: TipografiaTrato.corpoPequeno.copyWith(
                              color: selecionado ? c.sobrePetroleo : c.texto,
                              fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Expanded(
          child: widget.aoRecarregar == null
              ? listaOuVazio
              : RefreshIndicator(onRefresh: widget.aoRecarregar!, child: listaOuVazio),
        ),
      ],
    );
  }
}

class _LinhaConversa extends StatelessWidget {
  const _LinhaConversa({required this.item, required this.aoTocar});

  final ConversaResumo item;
  final VoidCallback aoTocar;

  (Color, Color) _coresEstado(CoresTemaTrato c, String estado) {
    return switch (estado) {
      'Concluído' => (c.verdeSuave, c.verdeTexto),
      'Retrabalho' => (c.ambarSuave, c.ambarTexto),
      'Em andamento' => (c.azulSuave, c.azulTexto),
      _ => (c.ambarSuave, c.ambarTexto),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final novas = item.naoLidas > 0;
    final subtitulo = item.subtituloComCodigo;
    final estado = item.estadoEfetivo;
    final (fundoEstado, textoEstado) = _coresEstado(c, estado);

    return Semantics(
      button: true,
      label: '${item.interlocutor}, $subtitulo ($estado). ${item.ultimaMensagem}.'
          '${novas ? ' ${item.naoLidas} não lidas.' : ''}',
      excludeSemantics: true,
      child: Material(
        color: c.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: BorderSide(
            color: novas ? c.laranja.withValues(alpha: 0.65) : c.borda,
            width: novas ? EspacosTrato.bordaControle : EspacosTrato.bordaFina,
          ),
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
                      Text(
                        item.interlocutor,
                        style: TipografiaTrato.tituloCartao.copyWith(color: c.texto),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: EspacosTrato.x2,
                        runSpacing: EspacosTrato.x1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            subtitulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: fundoEstado,
                              borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
                            ),
                            child: Text(
                              estado,
                              style: TipografiaTrato.legenda.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: textoEstado,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        item.ultimaMensagem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: novas
                            ? TipografiaTrato.corpoPequeno.copyWith(
                                color: c.texto,
                                fontWeight: FontWeight.w700,
                              )
                            : TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
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
                      style: TipografiaTrato.legenda.copyWith(
                        color: novas ? c.texto : c.textoSecundario,
                        fontWeight: novas ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (novas) ...[
                      const SizedBox(height: EspacosTrato.x2),
                      Container(
                        key: ValueKey('badge-nao-lidas-${item.pedidoId}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.laranja,
                          borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                        ),
                        child: Text(
                          '${item.naoLidas}',
                          style: TipografiaTrato.legenda.copyWith(
                            color: CoresTrato.petroleo,
                            fontWeight: FontWeight.w700,
                          ),
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
