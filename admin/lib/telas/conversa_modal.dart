import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'modal_sigiloso.dart';

/// "Ver conversa" (Termos 11.3). Não há leitura de rotina: nada é carregado antes de motivo e base,
/// o backend confere o vínculo e grava o acesso, e o texto some ao fechar o modal.
Future<void> abrirConversa(BuildContext context, String pedidoId, String pedido, {String baseInicial = 'disputa'}) =>
    mostrarModal<void>(
      context,
      largura: 640,
      construir: (_) => _ConversaModal(pedidoId: pedidoId, pedido: pedido, baseInicial: baseInicial),
    );

const _bases = [
  ('disputa', 'Disputa'),
  ('relato', 'Relato de problema'),
  ('denuncia', 'Denúncia'),
  ('incidente', 'Incidente de segurança'),
  ('fraude', 'Suspeita de fraude'),
  ('ordem_judicial', 'Ordem judicial'),
  ('autorizacao_usuario', 'Autorização do usuário'),
];

class _ConversaModal extends StatefulWidget {
  const _ConversaModal({required this.pedidoId, required this.pedido, required this.baseInicial});
  final String baseInicial;
  final String pedidoId;
  final String pedido;

  @override
  State<_ConversaModal> createState() => _ConversaModalState();
}

class _ConversaModalState extends State<_ConversaModal> with SomeComASessao {
  final _motivo = TextEditingController();
  final _referencia = TextEditingController();
  late String _base = widget.baseInicial;
  List<ConversaLida>? _conversas;
  bool _carregando = false;
  String? _erro;

  @override
  void limparSigiloso() => _conversas = null;

  @override
  void dispose() {
    limparSigiloso();
    _motivo.dispose();
    _referencia.dispose();
    super.dispose();
  }

  String? get _rotuloReferencia => switch (_base) {
        'ordem_judicial' => 'Número do processo',
        'autorizacao_usuario' => 'Protocolo do SAC',
        _ => null,
      };

  bool get _valido {
    final n = _motivo.text.trim().length;
    return n >= kMotivoMinimo && n <= 1000 && (_rotuloReferencia == null || _referencia.text.trim().isNotEmpty);
  }

  Future<void> _ler() async {
    if (_carregando || !_valido) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await context.api.lerConversas(
        widget.pedidoId,
        motivo: _motivo.text.trim(),
        base: _base,
        referencia: _rotuloReferencia == null ? null : _referencia.text.trim(),
      );
      // Fechou ou a sessão caiu enquanto carregava: o texto é descartado.
      if (!mounted || !context.sessao.logado) return;
      setState(() => _conversas = r);
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<Widget> _pedirAcesso() => [
        DropdownButtonFormField<String>(
          initialValue: _base,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Base do acesso'),
          // O servidor também recusa: ordem judicial é só para administrador.
          items: [
            for (final (v, r) in _bases)
              if (v != 'ordem_judicial' || context.eu?.papel == Papel.administrador)
                DropdownMenuItem(value: v, child: Text(r)),
          ],
          onChanged: _carregando ? null : (v) => setState(() => _base = v ?? _base),
        ),
        if (_rotuloReferencia != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: _referencia,
            maxLength: 120,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: _rotuloReferencia),
          ),
        ],
        const SizedBox(height: EspacosTrato.x3),
        CampoMotivo(controle: _motivo, aoMudar: () => setState(() {})),
        const SizedBox(height: EspacosTrato.x3),
        const AvisoAuditoria(),
      ];

  List<Widget> _mensagens(List<ConversaLida> conversas) {
    if (conversas.isEmpty) {
      return [
        const BannerInfo(
          'O servidor não devolveu nenhuma conversa entre as partes ligadas a essa base. '
          'O acesso ficou registrado.',
          titulo: 'Nenhuma conversa para mostrar.',
        ),
      ];
    }
    if (conversas.every((c) => c.mensagens.isEmpty)) {
      return [Text('Nenhuma mensagem neste pedido.', style: TipografiaTrato.corpo)];
    }
    return [
      for (final (i, c) in conversas.indexed) ...[
        if (conversas.length > 1) Text('Conversa ${i + 1}', style: TipografiaTrato.secao),
        for (final m in c.mensagens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m.autorId == c.profissionalId ? 'Profissional' : 'Cliente'} · ${formatarData(m.enviadaEm)}',
                  style: TipografiaTrato.legenda,
                ),
                Text(m.texto, style: TipografiaTrato.corpo),
                if (m.mascarada) Text('No app apareceu: ${m.textoExibido}', style: TipografiaTrato.legenda),
              ],
            ),
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final conversas = _conversas;
    return CorpoModal(
      titulo: 'Conversa · ${widget.pedido}',
      consequencia: conversas == null
          ? 'A equipe só lê mensagens com um motivo previsto nos Termos. O acesso fica registrado.'
          : 'Dado pessoal: use só neste caso. Fechar apaga o texto da tela.',
      filhos: [
        if (_erro != null) ...[
          BannerInfo(_erro!, titulo: 'Nada foi mostrado.', tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (conversas == null) ..._pedirAcesso() else ..._mensagens(conversas),
      ],
      acoes: [
        BotaoTrato.secundario('Fechar', aoPressionar: () => Navigator.of(context).pop()),
        if (conversas == null)
          BotaoTrato.primario(
            'Ler mensagens',
            aoPressionar: _valido && !_carregando ? _ler : null,
            carregando: _carregando,
            rotuloCarregando: 'Buscando',
          ),
      ],
    );
  }
}
