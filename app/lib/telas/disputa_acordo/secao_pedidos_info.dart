import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import 'pedidos_info.dart';

String _formatarData(DateTime dt) {
  final l = dt.toLocal();
  final d = l.day.toString().padLeft(2, '0');
  final m = l.month.toString().padLeft(2, '0');
  return '$d/$m/${l.year}';
}

(String, TipoStatus) _rotuloStatus(String status) => switch (status) {
      'aguardando_resposta' => ('Aguardando resposta', TipoStatus.alerta),
      'vencido' => ('Prazo vencido', TipoStatus.alerta),
      'respondido' => ('Respondido', TipoStatus.sucesso),
      'encerrado_sem_resposta' => ('Encerrado sem resposta', TipoStatus.info),
      _ => (status, TipoStatus.info),
    };

/// Termos 8.4: seção de pedidos de informação adicional na disputa.
/// Fica oculta silenciosamente quando não há itens ou em servidor antigo (404/503).
class SecaoPedidosInfoDisputa extends StatefulWidget {
  const SecaoPedidosInfoDisputa({
    super.key,
    required this.servico,
    required this.disputaOuPedidoId,
    required this.profissional,
    this.atualizarQuando,
    this.aoResponder,
  });

  final ServicoPedidosInfoDisputa servico;
  final String disputaOuPedidoId;
  final bool profissional;
  final ValueListenable<int>? atualizarQuando;
  final VoidCallback? aoResponder;

  @override
  State<SecaoPedidosInfoDisputa> createState() => _SecaoPedidosInfoDisputaState();
}

class _SecaoPedidosInfoDisputaState extends State<SecaoPedidosInfoDisputa> {
  List<PedidoInfoDisputa> _itens = const [];
  final _controladores = <String, TextEditingController>{};
  final _erros = <String, String?>{};
  final _enviando = <String>{};

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_carregar);
    _carregar();
  }

  @override
  void didUpdateWidget(covariant SecaoPedidosInfoDisputa oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.atualizarQuando != widget.atualizarQuando) {
      oldWidget.atualizarQuando?.removeListener(_carregar);
      widget.atualizarQuando?.addListener(_carregar);
    }
    if (oldWidget.disputaOuPedidoId != widget.disputaOuPedidoId ||
        oldWidget.servico != widget.servico) {
      _carregar();
    }
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_carregar);
    for (final c in _controladores.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista = await widget.servico.listar(widget.disputaOuPedidoId);
      if (!mounted) return;
      setState(() => _itens = lista);
    } on Object {
      // Fallback silencioso para não quebrar a tela da disputa em caso de erro ou backend antigo.
      if (!mounted) return;
      setState(() => _itens = const []);
    }
  }

  TextEditingController _controlador(String id) =>
      _controladores.putIfAbsent(id, TextEditingController.new);

  Future<void> _enviar(PedidoInfoDisputa item) async {
    final texto = _controlador(item.id).text.trim();
    if (texto.isEmpty) {
      setState(() => _erros[item.id] = 'Escreva sua resposta antes de enviar.');
      return;
    }
    if (texto.length > 2000) {
      setState(() => _erros[item.id] = 'A resposta pode ter no máximo 2000 caracteres.');
      return;
    }
    setState(() {
      _erros[item.id] = null;
      _enviando.add(item.id);
    });
    try {
      final atualizado = await widget.servico.responder(
        item.disputaId.isNotEmpty ? item.disputaId : widget.disputaOuPedidoId,
        item.id,
        texto,
      );
      if (!mounted) return;
      setState(() {
        _itens = [for (final x in _itens) x.id == item.id ? atualizado : x];
        _enviando.remove(item.id);
      });
      widget.aoResponder?.call();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando.remove(item.id);
        _erros[item.id] = mensagemErroTrato(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_itens.isEmpty) return const SizedBox.shrink();
    final cores = context.cores;
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        key: const ValueKey('secao-pedidos-info'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pedidos de informação', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x3),
            for (var i = 0; i < _itens.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: EspacosTrato.x3),
                Divider(color: cores.borda, height: 1),
                const SizedBox(height: EspacosTrato.x3),
              ],
              _itemView(context, _itens[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemView(BuildContext context, PedidoInfoDisputa item) {
    final cores = context.cores;
    final (rotulo, tipoStatus) = _rotuloStatus(item.status);
    final destinatario = item.destinatarioPapel == 'profissional'
        ? 'Solicitado ao profissional'
        : 'Solicitado ao cliente';
    final podeResponder = item.podeResponder(profissional: widget.profissional);
    final erro = _erros[item.id];
    final enviando = _enviando.contains(item.id);

    return Column(
      key: ValueKey('pedido-info-${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChipStatus(texto: rotulo, tipo: tipoStatus),
            Text(
              destinatario,
              style: TipografiaTrato.corpoPequeno.copyWith(color: cores.textoSecundario),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(item.mensagem, style: TipografiaTrato.corpo),
        if (item.responderAte case final prazo?) ...[
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Prazo: ${_formatarData(prazo)}',
            style: TipografiaTrato.corpoPequeno.copyWith(color: cores.textoSecundario),
          ),
        ],
        if (item.respostaTexto != null && item.respostaTexto!.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text('Resposta enviada', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x1),
          Text(item.respostaTexto!, style: TipografiaTrato.corpo),
        ],
        if (podeResponder) ...[
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: ValueKey('campo-resposta-info-${item.id}'),
            controller: _controlador(item.id),
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            enabled: !enviando,
            style: TipografiaTrato.corpo,
            decoration: const InputDecoration(
              hintText: 'Escreva sua resposta',
            ),
            onChanged: (_) {
              if (_erros[item.id] != null) {
                setState(() => _erros[item.id] = null);
              }
            },
          ),
          if (erro != null) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              erro,
              key: ValueKey('erro-resposta-info-${item.id}'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: cores.vermelhoTexto),
            ),
          ],
          const SizedBox(height: EspacosTrato.x2),
          BotaoPrimario(
            key: ValueKey('enviar-resposta-info-${item.id}'),
            texto: 'Enviar resposta',
            carregando: enviando,
            aoTocar: () => _enviar(item),
          ),
        ],
      ],
    );
  }
}
