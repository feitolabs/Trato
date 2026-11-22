import 'dart:async';

import 'package:flutter/material.dart';

import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

/// F5.12 — Notificações (sem protótipo; segue o padrão das telas vizinhas).
/// Toque em um item marca como lido e chama [aoAbrirDestino]; quem liga as rotas decide a tela.
class NotificacoesTela extends StatelessWidget {
  const NotificacoesTela({
    super.key,
    required this.servico,
    this.aoAbrirDestino,
    this.aoAbrirPreferencias,
    this.comVoltar = true,
    this.atualizarACada,
    this.atualizarQuando,
    this.aoContarNaoLidas,
  });

  /// Atualiza a lista sozinha neste intervalo (aviso novo aparece sem fechar o app).
  final Duration? atualizarACada;
  final Listenable? atualizarQuando;
  final ValueChanged<int>? aoContarNaoLidas;

  final ServicoNotificacoes servico;
  final ValueChanged<Notificacao>? aoAbrirDestino;
  final VoidCallback? aoAbrirPreferencias;
  final bool comVoltar;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Notificações',
      comVoltar: comVoltar,
      acoes: [
        if (aoAbrirPreferencias != null)
          IconButton(
            key: const Key('botao-preferencias-notificacoes'),
            tooltip: 'Preferências de notificação',
            onPressed: aoAbrirPreferencias,
            icon: const Icon(Icons.tune),
          ),
      ],
      child: CarregadorTela<List<Notificacao>>(
        carregar: () async {
          final lista = await servico.listar();
          aoContarNaoLidas?.call(lista.where((n) => !n.lida).length);
          return lista;
        },
        atualizarACada: atualizarACada,
        atualizarQuando: atualizarQuando,
        construir: (context, itens, _) {
          final recarregar = AtualizadorTela.de(context);
          if (itens.isEmpty) {
            final vazio = EstadoVazio(
              icone: Icons.notifications_none,
              titulo: 'Nada por aqui',
              texto: 'Quando houver novidades dos seus pedidos, elas aparecem aqui.',
              textoAcao: aoAbrirPreferencias == null ? null : 'Ajustar avisos',
              aoAcao: aoAbrirPreferencias,
            );
            return recarregar == null
                ? vazio
                : RefreshIndicator(onRefresh: recarregar, child: vazio);
          }
          return _ListaNotificacoes(
            servico: servico,
            itens: itens,
            aoAbrirDestino: aoAbrirDestino,
            aoContarNaoLidas: aoContarNaoLidas,
          );
        },
      ),
    );
  }
}

class _ListaNotificacoes extends StatefulWidget {
  const _ListaNotificacoes({
    required this.servico,
    required this.itens,
    this.aoAbrirDestino,
    this.aoContarNaoLidas,
  });

  final ServicoNotificacoes servico;
  final List<Notificacao> itens;
  final ValueChanged<Notificacao>? aoAbrirDestino;
  final ValueChanged<int>? aoContarNaoLidas;

  @override
  State<_ListaNotificacoes> createState() => _ListaNotificacoesState();
}

class _ListaNotificacoesState extends State<_ListaNotificacoes> {
  late List<Notificacao> _itens = widget.itens;

  /// Abrir a lista é ver os avisos: marca tudo como lido (sino e contador zeram).
  @override
  void initState() {
    super.initState();
    if (_naoLidas == 0) return;
    unawaited(widget.servico.marcarTodasLidas().catchError((Object _) {}));
    _itens = [for (final i in _itens) i.comoLida()];
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.aoContarNaoLidas?.call(0));
  }

  @override
  void didUpdateWidget(covariant _ListaNotificacoes antigo) {
    super.didUpdateWidget(antigo);
    if (identical(antigo.itens, widget.itens)) return;
    // Lista nova do servidor (atualização automática): o que já li aqui continua lido.
    final lidas = {for (final i in _itens) if (i.lida) i.id};
    _itens = [for (final n in widget.itens) lidas.contains(n.id) ? n.comoLida() : n];
  }

  int get _naoLidas => _itens.where((n) => !n.lida).length;

  void _abrir(Notificacao n) {
    if (!n.lida) {
      widget.servico.marcarLida(n.id);
      setState(() => _itens = [for (final i in _itens) i.id == n.id ? i.comoLida() : i]);
      widget.aoContarNaoLidas?.call(_naoLidas);
    }
    widget.aoAbrirDestino?.call(n);
  }

  void _marcarTodas() {
    widget.servico.marcarTodasLidas();
    setState(() => _itens = [for (final i in _itens) i.comoLida()]);
    widget.aoContarNaoLidas?.call(0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: EspacosTrato.x2,
          children: [
            Text(
              _naoLidas == 0
                  ? 'Tudo lido'
                  : '$_naoLidas ${_naoLidas == 1 ? 'não lida' : 'não lidas'}',
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
            ),
            if (_naoLidas > 0)
              TextButton(
                onPressed: _marcarTodas,
                child: const Text('Marcar todas como lidas', maxLines: 1),
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        Expanded(
          child: () {
            final recarregar = AtualizadorTela.de(context);
            final lista = ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
              itemCount: _itens.length,
              separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (_, i) =>
                  _LinhaNotificacao(item: _itens[i], aoTocar: () => _abrir(_itens[i])),
            );
            return recarregar == null
                ? lista
                : RefreshIndicator(onRefresh: recarregar, child: lista);
          }(),
        ),
      ],
    );
  }
}

class _LinhaNotificacao extends StatelessWidget {
  const _LinhaNotificacao({required this.item, required this.aoTocar});

  final Notificacao item;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final forte = !item.lida;
    return Semantics(
      button: true,
      label: '${forte ? 'Não lida. ' : ''}${item.tipo.rotulo}. ${item.titulo}. ${item.quando}',
      excludeSemantics: true,
      child: Material(
        color: forte ? context.cores.azulSuave : context.cores.superficie,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.tipo.icone, color: context.cores.petroleo),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.titulo,
                        style: forte ? TipografiaTrato.corpoForte : TipografiaTrato.corpo,
                      ),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        item.texto,
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: context.cores.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(
                        '${item.tipo.rotulo} · ${item.quando}',
                        style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
                      ),
                    ],
                  ),
                ),
                if (forte)
                  Container(
                    margin: const EdgeInsets.only(left: EspacosTrato.x2, top: EspacosTrato.x1),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: context.cores.laranja,
                      shape: BoxShape.circle,
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
