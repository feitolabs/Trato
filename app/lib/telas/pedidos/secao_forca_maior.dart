import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../pedido_novo/pecas_pedido.dart';
import 'forca_maior.dart';

String _rotuloAcao(String acao) => switch (acao) {
      'reagendar' => 'Reagendar sem custo',
      'cancelar' => 'Cancelar sem multa',
      _ => acao,
    };

(String, TipoStatus) _rotuloStatus(String status) => switch (status) {
      'pendente' => ('Em análise', TipoStatus.alerta),
      'aprovado' => ('Aprovado', TipoStatus.sucesso),
      'recusado' => ('Recusado', TipoStatus.perigo),
      _ => (status, TipoStatus.info),
    };

/// Termos 7.8 e 22.6: exibe solicitações de evento externo (força maior) do pedido
/// e permite registrar uma nova solicitação quando o pedido está ativo.
class SecaoForcaMaior extends StatefulWidget {
  const SecaoForcaMaior({
    super.key,
    required this.servico,
    required this.pedidoId,
    required this.pedidoAtivo,
    this.atualizarQuando,
    this.aoCriar,
  });

  final ServicoForcaMaior servico;
  final String pedidoId;
  final bool pedidoAtivo;
  final ValueListenable<int>? atualizarQuando;
  final VoidCallback? aoCriar;

  @override
  State<SecaoForcaMaior> createState() => _SecaoForcaMaiorState();
}

class _SecaoForcaMaiorState extends State<SecaoForcaMaior> {
  List<EventoForcaMaior>? _itens;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_carregar);
    _carregar();
  }

  @override
  void didUpdateWidget(covariant SecaoForcaMaior oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.atualizarQuando != widget.atualizarQuando) {
      oldWidget.atualizarQuando?.removeListener(_carregar);
      widget.atualizarQuando?.addListener(_carregar);
    }
    if (oldWidget.pedidoId != widget.pedidoId || oldWidget.servico != widget.servico) {
      _carregar();
    }
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista = await widget.servico.listar(widget.pedidoId);
      if (!mounted) return;
      setState(() => _itens = lista);
    } on Object {
      // Fallback silencioso para não quebrar a tela em backend antigo ou erro temporário.
      if (!mounted) return;
      setState(() => _itens = null);
    }
  }

  Future<void> _abrirFormulario() async {
    final criado = await showModalBottomSheet<EventoForcaMaior>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cores.fundo,
      builder: (_) => _FolhaForcaMaior(
        servico: widget.servico,
        pedidoId: widget.pedidoId,
      ),
    );
    if (criado == null || !mounted) return;
    setState(() => _itens = [criado, ...?_itens]);
    widget.aoCriar?.call();
  }

  @override
  Widget build(BuildContext context) {
    final itens = _itens;
    if (itens == null) return const SizedBox.shrink();
    if (itens.isEmpty && !widget.pedidoAtivo) return const SizedBox.shrink();

    final cores = context.cores;
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        key: const ValueKey('secao-forca-maior'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Evento externo (força maior)', style: TipografiaTrato.tituloCartao),
            if (itens.isNotEmpty) ...[
              const SizedBox(height: EspacosTrato.x3),
              for (var i = 0; i < itens.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  Divider(color: cores.borda, height: 1),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                _itemView(context, itens[i]),
              ],
            ],
            if (widget.pedidoAtivo) ...[
              const SizedBox(height: EspacosTrato.x3),
              BotaoSecundario(
                key: const ValueKey('alegar-forca-maior'),
                texto: 'Alegar evento externo (força maior)',
                aoTocar: _abrirFormulario,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemView(BuildContext context, EventoForcaMaior item) {
    final cores = context.cores;
    final (rotuloStatus, tipoStatus) = _rotuloStatus(item.status);
    return Column(
      key: ValueKey('forca-maior-${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChipStatus(texto: rotuloStatus, tipo: tipoStatus),
            Text(
              _rotuloAcao(item.acaoSolicitada),
              style: TipografiaTrato.corpoForte,
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(item.descricao, style: TipografiaTrato.corpo),
        if (item.justificativaDecisao != null && item.justificativaDecisao!.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text('Decisão da equipe', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            item.justificativaDecisao!,
            style: TipografiaTrato.corpoPequeno.copyWith(color: cores.textoSecundario),
          ),
        ],
      ],
    );
  }
}

class _FolhaForcaMaior extends StatefulWidget {
  const _FolhaForcaMaior({required this.servico, required this.pedidoId});

  final ServicoForcaMaior servico;
  final String pedidoId;

  @override
  State<_FolhaForcaMaior> createState() => _FolhaForcaMaiorState();
}

class _FolhaForcaMaiorState extends State<_FolhaForcaMaior> {
  String _acao = 'reagendar';
  final _descricao = TextEditingController();
  final _comprovante = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _descricao.dispose();
    _comprovante.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _descricao.text.trim();
    if (texto.length < 10) {
      setState(() => _erro = 'Descreva o ocorrido com pelo menos 10 caracteres.');
      return;
    }
    if (texto.length > 1000) {
      setState(() => _erro = 'A descrição pode ter no máximo 1000 caracteres.');
      return;
    }
    final compBruto = _comprovante.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(10)
        .toList();
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final criado = await widget.servico.solicitar(
        widget.pedidoId,
        acaoSolicitada: _acao,
        descricao: texto,
        comprovantes: compBruto,
      );
      if (!mounted) return;
      Navigator.of(context).pop(criado);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = mensagemErroTrato(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = context.cores;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(EspacosTrato.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Alegar evento externo (força maior)', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'A equipe do Trato vai analisar sua solicitação (Termos 7.8 e 22.6).',
                style: TipografiaTrato.corpoPequeno.copyWith(color: cores.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x4),
              const RotuloSecao('O que você precisa?'),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  ChipOpcao(
                    key: const ValueKey('opcao-forca-maior-reagendar'),
                    texto: 'Reagendar sem custo',
                    marcado: _acao == 'reagendar',
                    aoTocar: () {
                      if (!_enviando) setState(() => _acao = 'reagendar');
                    },
                  ),
                  ChipOpcao(
                    key: const ValueKey('opcao-forca-maior-cancelar'),
                    texto: 'Cancelar sem multa',
                    marcado: _acao == 'cancelar',
                    aoTocar: () {
                      if (!_enviando) setState(() => _acao = 'cancelar');
                    },
                  ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x4),
              const RotuloSecao('O que aconteceu?'),
              const SizedBox(height: EspacosTrato.x2),
              TextField(
                key: const ValueKey('campo-descricao-forca-maior'),
                controller: _descricao,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                enabled: !_enviando,
                style: TipografiaTrato.corpo,
                decoration: const InputDecoration(
                  hintText: 'Explique o evento externo (mínimo de 10 caracteres)',
                ),
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
              ),
              const SizedBox(height: EspacosTrato.x3),
              const RotuloSecao('Comprovante ou link (opcional)'),
              const SizedBox(height: EspacosTrato.x2),
              TextField(
                key: const ValueKey('campo-comprovante-forca-maior'),
                controller: _comprovante,
                minLines: 1,
                maxLines: 3,
                enabled: !_enviando,
                style: TipografiaTrato.corpo,
                decoration: const InputDecoration(
                  hintText: 'Link ou referência do comprovante (opcional)',
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  _erro!,
                  key: const ValueKey('erro-forca-maior'),
                  style: TipografiaTrato.corpoPequeno.copyWith(color: cores.vermelhoTexto),
                ),
              ],
              const SizedBox(height: EspacosTrato.x4),
              BotaoPrimario(
                key: const ValueKey('enviar-forca-maior'),
                texto: 'Enviar solicitação',
                carregando: _enviando,
                aoTocar: _enviar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
