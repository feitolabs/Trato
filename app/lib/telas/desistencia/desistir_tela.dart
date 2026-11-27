import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart';
import '../comuns/textos_dos_termos.dart';
import '../profissional/dinheiro.dart';
import 'modelos.dart';

String _quando(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}, ${horaDoAparelho(d)}';

/// "Desistir do pedido": mostra o efeito antes de confirmar e o comprovante depois.
class DesistirTela extends StatelessWidget {
  const DesistirTela({
    super.key,
    required this.carregar,
    required this.desistir,
    this.aoDesistir,
  });

  /// Nulo: o servidor não tem a desistência.
  final Future<SituacaoDesistencia?> Function() carregar;
  final Future<RegistroDesistencia> Function(String motivo) desistir;

  /// A desistência foi recebida (para as outras telas se atualizarem).
  final VoidCallback? aoDesistir;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Desistir do pedido',
      child: CarregadorTela<SituacaoDesistencia?>(
        carregar: carregar,
        construir: (context, situacao, _) =>
            _Corpo(situacao: situacao, desistir: desistir, aoDesistir: aoDesistir),
      ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({required this.situacao, required this.desistir, this.aoDesistir});

  final SituacaoDesistencia? situacao;
  final Future<RegistroDesistencia> Function(String motivo) desistir;
  final VoidCallback? aoDesistir;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  final _motivo = TextEditingController();
  var _enviando = false;
  String? _erro;
  RegistroDesistencia? _feito;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_enviando) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final registro = await widget.desistir(_motivo.text.trim());
      if (!mounted) return;
      setState(() => _feito = registro);
      widget.aoDesistir?.call();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _erro = e is ErroTrato
            ? e.mensagem
            : 'Não foi possível enviar a desistência. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.situacao;
    final comprovante = _feito ?? (s != null && s.mostraComprovante ? s.registro : null);
    final secundario = TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario);
    final List<Widget> filhos;
    if (comprovante != null) {
      filhos = [_Comprovante(registro: comprovante)];
    } else if (s == null || !s.podeDesistir) {
      filhos = [
        Text('Não dá para desistir agora', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        Text(
          s?.motivoIndisponivel ??
              'A desistência não está disponível para este pedido. $textoAtendimentoHumano',
          key: const Key('desistencia-indisponivel'),
          style: secundario,
        ),
        const SizedBox(height: EspacosTrato.x5),
        BotaoSecundario(texto: 'Voltar', aoTocar: () => Navigator.of(context).maybePop()),
      ];
    } else {
      final integral = s.efeito == EfeitoDesistencia.reembolsoIntegral;
      filhos = [
        Text('O que acontece', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        CartaoTrato(
          key: const Key('efeito-desistencia'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                integral ? 'Reembolso integral' : 'Um analista calcula o reembolso',
                style: TipografiaTrato.tituloCartao,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                integral
                    ? 'O pedido é cancelado e o que você pagou volta por inteiro, pela mesma '
                        'forma de pagamento.'
                    : 'O serviço já começou. O valor fica retido até a decisão do analista.',
                style: TipografiaTrato.corpo,
              ),
              if (!integral) ...[
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  s.pediuExecucaoImediata
                      ? 'Você pediu a execução antes do fim dos 7 dias: o reembolso é '
                          'proporcional à parte não executada.'
                      : 'Você não pediu a execução antes do fim dos 7 dias, e o analista leva '
                          'isso em conta.',
                  style: TipografiaTrato.corpo,
                ),
              ],
            ],
          ),
        ),
        if (s.arrependimentoAte != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Prazo de arrependimento: até ${_quando(s.arrependimentoAte!)}.',
            style: secundario,
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        TextField(
          key: const Key('motivo-desistencia'),
          controller: _motivo,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (_erro != null) ...[
          Text(
            _erro!,
            key: const Key('erro-desistencia'),
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
          ),
          const SizedBox(height: EspacosTrato.x2),
        ],
        BotaoPrimario(
          key: const Key('confirmar-desistencia'),
          texto: _erro == null ? 'Confirmar desistência' : 'Tentar de novo',
          carregando: _enviando,
          aoTocar: _confirmar,
        ),
        const SizedBox(height: EspacosTrato.x2),
        Center(
          child: BotaoLink(
            texto: 'Voltar sem desistir',
            aoTocar: () => Navigator.of(context).maybePop(),
          ),
        ),
      ];
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: filhos,
    );
  }
}

class _Comprovante extends StatefulWidget {
  const _Comprovante({required this.registro});

  final RegistroDesistencia registro;

  @override
  State<_Comprovante> createState() => _ComprovanteState();
}

class _ComprovanteState extends State<_Comprovante> {
  var _copiado = false;

  List<(String, String)> get _linhas {
    final r = widget.registro;
    return [
      ('Protocolo', r.protocolo ?? 'Não informado'),
      if (r.recebidoEm != null) ('Recebida em', _quando(r.recebidoEm!)),
      ('Situação', r.situacaoTexto),
      if (r.reembolsoCentavos != null) ('Reembolso', Dinheiro.formatar(r.reembolsoCentavos!)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Comprovante da desistência', style: TipografiaTrato.titulo),
        if (widget.registro.mensagem != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(widget.registro.mensagem!, style: TipografiaTrato.corpo),
        ],
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          key: const Key('comprovante-desistencia'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (rotulo, valor) in _linhas) ...[
                Text(
                  rotulo,
                  style: TipografiaTrato.corpoPequeno
                      .copyWith(color: context.cores.textoSecundario),
                ),
                SelectableText(valor, style: TipografiaTrato.corpoForte),
                const SizedBox(height: EspacosTrato.x2),
              ],
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        BotaoSecundario(
          texto: _copiado ? 'Comprovante copiado' : 'Copiar comprovante',
          icone: Icons.copy_outlined,
          aoTocar: () async {
            await Clipboard.setData(ClipboardData(
              text: [
                'Desistência do pedido (Trato)',
                for (final (rotulo, valor) in _linhas) '$rotulo: $valor',
              ].join('\n'),
            ));
            if (mounted) setState(() => _copiado = true);
          },
        ),
        const SizedBox(height: EspacosTrato.x2),
        Center(
          child: BotaoLink(texto: 'Voltar', aoTocar: () => Navigator.of(context).maybePop()),
        ),
      ],
    );
  }
}
