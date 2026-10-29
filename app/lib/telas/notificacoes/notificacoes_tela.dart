import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
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
    this.comVoltar = true,
  });

  final ServicoNotificacoes servico;
  final ValueChanged<Notificacao>? aoAbrirDestino;
  final bool comVoltar;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Notificações',
      comVoltar: comVoltar,
      child: CarregadorTela<List<Notificacao>>(
        carregar: servico.listar,
        construir: (context, itens, _) => itens.isEmpty
            ? const EstadoVazio(
                icone: Icons.notifications_none,
                titulo: 'Nada por aqui',
                texto: 'Quando houver novidades dos seus pedidos, elas aparecem aqui.',
              )
            : _ListaNotificacoes(servico: servico, itens: itens, aoAbrirDestino: aoAbrirDestino),
      ),
    );
  }
}

class _ListaNotificacoes extends StatefulWidget {
  const _ListaNotificacoes({required this.servico, required this.itens, this.aoAbrirDestino});

  final ServicoNotificacoes servico;
  final List<Notificacao> itens;
  final ValueChanged<Notificacao>? aoAbrirDestino;

  @override
  State<_ListaNotificacoes> createState() => _ListaNotificacoesState();
}

class _ListaNotificacoesState extends State<_ListaNotificacoes> {
  late List<Notificacao> _itens = widget.itens;

  int get _naoLidas => _itens.where((n) => !n.lida).length;

  void _abrir(Notificacao n) {
    if (!n.lida) {
      widget.servico.marcarLida(n.id);
      setState(() => _itens = [for (final i in _itens) i.id == n.id ? i.comoLida() : i]);
    }
    widget.aoAbrirDestino?.call(n);
  }

  void _marcarTodas() {
    widget.servico.marcarTodasLidas();
    setState(() => _itens = [for (final i in _itens) i.comoLida()]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _naoLidas == 0
                    ? 'Tudo lido'
                    : '$_naoLidas ${_naoLidas == 1 ? 'não lida' : 'não lidas'}',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
              ),
            ),
            if (_naoLidas > 0)
              BotaoLink(texto: 'Marcar todas como lidas', aoTocar: _marcarTodas),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            itemCount: _itens.length,
            separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
            itemBuilder: (_, i) =>
                _LinhaNotificacao(item: _itens[i], aoTocar: () => _abrir(_itens[i])),
          ),
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
        color: forte ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: const BorderSide(color: CoresTrato.borda),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.tipo.icone, color: CoresTrato.petroleo),
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
                            .copyWith(color: CoresTrato.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(
                        '${item.tipo.rotulo} · ${item.quando}',
                        style: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario),
                      ),
                    ],
                  ),
                ),
                if (forte)
                  Container(
                    margin: const EdgeInsets.only(left: EspacosTrato.x2, top: EspacosTrato.x1),
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: CoresTrato.laranja,
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
