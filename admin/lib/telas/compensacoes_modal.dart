import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

/// Registrar uma compensação: preencher, revisar e confirmar. Quem diz o máximo é o backend.
/// [pedidoId] e [contestacaoId] vêm preenchidos pelo atalho da contestação; o valor, nunca.
Future<void> abrirRegistroDeCompensacao(BuildContext context, {String? pedidoId, String? contestacaoId}) =>
    mostrarModal<void>(context,
        largura: 560, construir: (_) => _ModalRegistro(pedidoId: pedidoId, contestacaoId: contestacaoId));

class _ModalRegistro extends StatefulWidget {
  const _ModalRegistro({this.pedidoId, this.contestacaoId});
  final String? pedidoId;
  final String? contestacaoId;

  @override
  State<_ModalRegistro> createState() => _ModalRegistroState();
}

class _ModalRegistroState extends State<_ModalRegistro> {
  late final _pedido = TextEditingController(text: widget.pedidoId ?? '');
  late final _contestacao = TextEditingController(text: widget.contestacaoId ?? '');
  final _valor = TextEditingController();
  final _motivo = TextEditingController();
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_pedido, _contestacao, _valor, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Compensação precisa ser maior que zero.
  int? get _centavos {
    final v = lerReaisEmCentavos(_valor.text);
    return v == null || v <= 0 ? null : v;
  }

  bool get _valido {
    final n = _motivo.text.trim().length;
    return _pedido.text.trim().isNotEmpty && _centavos != null && n >= kMotivoMinimo && n <= 1000;
  }

  static String _mensagemDeErro(Object e) {
    if (e is! ErroApi) return 'Algo deu errado. Confira a lista antes de repetir.';
    final maximo = e.maximoCentavos;
    if (e.codigo == 'acima_do_devido' && maximo != null) {
      return '${e.mensagem} O máximo é ${formatarReais(maximo)}.';
    }
    // Sem código HTTP: a resposta se perdeu e o registro pode ter acontecido.
    if (e.status == null && !e.proibido && !e.sessao) {
      return '${e.mensagem} Confira a lista antes de repetir.';
    }
    return e.mensagem;
  }

  Future<void> _registrar() async {
    final centavos = _centavos;
    if (_enviando || centavos == null) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final contestacao = _contestacao.text.trim();
    try {
      final r = await context.api.registrarCompensacao(
        pedidoId: _pedido.text.trim(),
        contestacaoId: contestacao.isEmpty ? null : contestacao,
        valorCentavos: centavos,
        motivo: _motivo.text.trim(),
      );
      if (!mounted) return;
      final valor = formatarReais(r.compensacao.valorCentavos);
      final base = r.resultado == 'ja_registrada'
          ? 'Esta compensação já estava registrada ($valor). Nada novo foi criado.'
          : 'Compensação de $valor registrada.';
      mostrarAviso(
        context,
        r.avisado ? base : '$base O aviso não saiu: sem aviso, nada é descontado. Use "Avisar profissional".',
        erro: !r.avisado,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = _mensagemDeErro(e);
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  Widget _campo(String rotulo, TextEditingController c,
          {int maximo = 64, int linhas = 1, String? ajuda, String? erro, String? prefixo, TextInputType? teclado}) =>
      Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 3,
          maxLength: maximo,
          keyboardType: teclado,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: rotulo,
            helperText: ajuda,
            helperMaxLines: 3,
            errorText: erro,
            errorMaxLines: 3,
            prefixText: prefixo,
            counterText: '',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final centavos = _centavos;
    final contestacao = _contestacao.text.trim();
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar a compensação?' : 'Registrar compensação',
        consequencia: _revisando
            ? 'O valor passa a ser descontado dos próximos repasses depois que o profissional for avisado.'
            : 'Reembolso ao cliente descontado de repasses futuros do profissional (Termos 8.6).',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi registrada.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_revisando && centavos != null) ...[
            Linha('Pedido', _pedido.text.trim()),
            Linha('Origem', contestacao.isEmpty ? 'Decisão original' : 'Contestação $contestacao'),
            Linha('Valor', formatarReais(centavos)),
            Linha('Motivo (o profissional lê)', _motivo.text.trim()),
          ] else ...[
            _campo('Código do pedido', _pedido),
            _campo('Código da contestação (opcional)', _contestacao,
                ajuda: 'Só quando uma contestação mudou a decisão. Vazio = decisão original.'),
            _campo(
              'Valor a compensar',
              _valor,
              maximo: 16,
              prefixo: 'R\$ ',
              teclado: const TextInputType.numberWithOptions(decimal: true),
              ajuda: centavos == null ? 'Use vírgula nos centavos. Exemplo: 1.234,56' : 'Vai como ${formatarReais(centavos)}',
              erro: _valor.text.trim().isEmpty || centavos != null
                  ? null
                  : (lerReaisEmCentavos(_valor.text) == 0 ? 'Informe um valor maior que zero' : kErroReais),
            ),
            _campo('Motivo (o profissional lê)', _motivo,
                maximo: 1000, linhas: 3, ajuda: 'Pelo menos $kMotivoMinimo caracteres. Não cite dado de terceiros.'),
          ],
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(),
          ),
          _revisando
              ? BotaoTrato.destrutivo(
                  'Confirmar compensação',
                  carregando: _enviando,
                  rotuloCarregando: 'Registrando',
                  aoPressionar: _enviando ? null : _registrar,
                )
              : BotaoTrato.primario(
                  'Revisar',
                  aoPressionar: _valido
                      ? () => setState(() {
                            _erro = null;
                            _revisando = true;
                          })
                      : null,
                ),
        ],
      ),
    );
  }
}
