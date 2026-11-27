import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';
import 'lgpd_pedidos_tela.dart';

Future<bool> abrirResponderPedidoLgpd(BuildContext context, PedidoTitularLgpd p) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => _ModalResponderLgpd(p)) ?? false;

class _ModalResponderLgpd extends StatefulWidget {
  const _ModalResponderLgpd(this.pedido);
  final PedidoTitularLgpd pedido;

  @override
  State<_ModalResponderLgpd> createState() => _ModalResponderLgpdState();
}

class _ModalResponderLgpdState extends State<_ModalResponderLgpd> {
  String _status = 'atendido';
  final _resposta = TextEditingController();
  final _motivoNaoAtendido = TextEditingController();
  final _criterios = TextEditingController();
  bool _enviando = false;
  bool _revisando = false;
  String? _erro;

  bool get _exigeMotivoNaoAtendido => _status == 'atendido_parcial' || _status == 'negado';
  bool get _exigeCriterios => widget.pedido.tipo == kTipoRevisaoAutomatizada;

  @override
  void dispose() {
    _resposta.dispose();
    _motivoNaoAtendido.dispose();
    _criterios.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.api.responderPedidoLgpd(
        widget.pedido.id,
        status: _status,
        resposta: _resposta.text.trim(),
        motivoNaoAtendido: _exigeMotivoNaoAtendido ? _motivoNaoAtendido.text.trim() : null,
        criteriosInformados: _exigeCriterios ? _criterios.text.trim() : null,
      );
      if (!mounted) return;
      mostrarAviso(context, 'Resposta registrada.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  Widget _campo(String rotulo, TextEditingController c, {int maximo = 2000, int linhas = 3, String? ajuda}) =>
      Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas + 3,
          maxLength: maximo,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: rotulo,
            helperText: ajuda,
            helperMaxLines: 2,
            counterText: '',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final resp = _resposta.text.trim();
    final mot = _motivoNaoAtendido.text.trim();
    final crit = _criterios.text.trim();
    final valido = resp.length >= kMotivoMinimo &&
        (!_exigeMotivoNaoAtendido || mot.length >= kMotivoMinimo) &&
        (!_exigeCriterios || crit.length >= kMotivoMinimo);
    const opcoesStatus = {
      'atendido': 'Atendido',
      'atendido_parcial': 'Atendido parcialmente',
      'negado': 'Negado',
    };
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar resposta?' : 'Responder pedido ${widget.pedido.protocolo}',
        consequencia: 'A resposta encerra o pedido do titular e fica registrada na auditoria sem texto livre.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (!_revisando) ...[
            Padding(
              padding: const EdgeInsets.only(top: EspacosTrato.x3),
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Desfecho'),
                items: [
                  for (final e in opcoesStatus.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ),
            _campo('Resposta ao titular', _resposta, maximo: 4000, ajuda: 'Pelo menos $kMotivoMinimo caracteres'),
            if (_exigeMotivoNaoAtendido)
              _campo(
                'Motivo do não atendimento',
                _motivoNaoAtendido,
                maximo: 2000,
                ajuda: 'Obrigatório quando parcial ou negado (Termos 14.9)',
              ),
            if (_exigeCriterios)
              _campo(
                'Critérios informados',
                _criterios,
                maximo: 2000,
                ajuda: 'Critérios e procedimentos usados na decisão automatizada (Termos 14.10)',
              ),
          ] else ...[
            Linha('Desfecho', opcoesStatus[_status] ?? _status),
            Linha('Resposta', resp),
            if (_exigeMotivoNaoAtendido) Linha('Motivo do não atendimento', mot),
            if (_exigeCriterios) Linha('Critérios informados', crit),
          ],
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(false),
          ),
          if (!_revisando)
            BotaoTrato.primario('Revisar', aoPressionar: valido ? () => setState(() => _revisando = true) : null)
          else
            BotaoTrato.primario(
              'Confirmar resposta',
              carregando: _enviando,
              rotuloCarregando: 'Enviando',
              aoPressionar: _enviando ? null : _confirmar,
            ),
        ],
      ),
    );
  }
}
