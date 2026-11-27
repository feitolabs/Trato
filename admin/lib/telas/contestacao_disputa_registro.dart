import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../tema/tema.dart';

/// Registrar a contestação da decisão (8.7) que a parte fez pelo atendimento. Conta e chamado vêm
/// do chamado aberto; a data da contestação é a do chamado. Quem confere tudo é o backend.
Future<void> abrirRegistroDeContestacaoDeDisputa(BuildContext context, Chamado chamado) =>
    mostrarModal<void>(context, largura: 560, construir: (_) => _ModalRegistro(chamado));

class _ModalRegistro extends StatefulWidget {
  const _ModalRegistro(this.chamado);
  final Chamado chamado;

  @override
  State<_ModalRegistro> createState() => _ModalRegistroState();
}

class _ModalRegistroState extends State<_ModalRegistro> {
  late final _pedido = TextEditingController(text: widget.chamado.pedidoId ?? '');
  final _texto = TextEditingController();
  final _anexos = TextEditingController();
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _pedido.dispose();
    _texto.dispose();
    _anexos.dispose();
    super.dispose();
  }

  List<String> get _listaAnexos =>
      [for (final a in _anexos.text.split(RegExp(r'[,;\n]'))) if (a.trim().isNotEmpty) a.trim()];

  bool get _valido {
    final n = _texto.text.trim().length;
    return _pedido.text.trim().isNotEmpty && n >= kMotivoMinimo && n <= 4000 && _listaAnexos.length <= 10;
  }

  Future<void> _registrar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await context.api.registrarContestacaoDisputa(
        pedidoId: _pedido.text.trim(),
        contestanteId: widget.chamado.usuarioId!,
        chamadoId: widget.chamado.id,
        oQueFaltou: _texto.text.trim(),
        anexos: _listaAnexos,
      );
      if (!mounted) return;
      final protocolo = r.contestacao.protocolo;
      mostrarAviso(
        context,
        r.repetida
            ? 'Esta contestação já estava registrada ($protocolo). Nada novo foi criado.'
            : 'Contestação registrada. Protocolo $protocolo.',
      );
      Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final c = widget.chamado;
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar o registro?' : 'Registrar contestação de disputa',
        consequencia: 'Vale a data do chamado ${c.protocolo}. Depois de registrada, o texto não muda.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi registrada.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          Linha('Quem contesta', c.solicitante),
          Linha('Chamado', c.protocolo),
          if (_revisando) ...[
            Linha('Pedido', _pedido.text.trim()),
            Linha('O que a análise não considerou', _texto.text.trim()),
            Linha('Anexos', '${_listaAnexos.length}'),
          ] else ...[
            if (c.pedidoId != null)
              Linha('Pedido', c.pedidoId!)
            else
              TextField(
                controller: _pedido,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Código do pedido'),
              ),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              controller: _texto,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'O que a análise não considerou',
                helperText: 'Pelo menos $kMotivoMinimo caracteres, nas palavras da pessoa',
              ),
            ),
            TextField(
              controller: _anexos,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Códigos dos anexos (opcional)',
                helperText: 'Só arquivos que a própria pessoa enviou neste pedido. Até 10, separados por vírgula.',
                helperMaxLines: 3,
                errorText: _listaAnexos.length > 10 ? 'No máximo 10 anexos' : null,
              ),
            ),
          ],
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(texto: 'O registro fica na auditoria com seu nome e o protocolo do chamado.'),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(),
          ),
          _revisando
              ? BotaoTrato.primario(
                  'Confirmar registro',
                  carregando: _enviando,
                  rotuloCarregando: 'Registrando',
                  aoPressionar: _enviando ? null : _registrar,
                )
              : BotaoTrato.primario(
                  'Revisar',
                  aoPressionar: _valido ? () => setState(() => _revisando = true) : null,
                ),
        ],
      ),
    );
  }
}
