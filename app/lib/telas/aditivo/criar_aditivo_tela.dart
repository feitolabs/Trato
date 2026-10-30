import 'dart:async';

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/campo_longo.dart';
import '../profissional/dinheiro.dart';
import '../profissional/servico_orcamento.dart';
import '../profissional_apoio/apoio.dart';
import 'aditivo.dart';

/// F6.5: o profissional cria um aditivo com preço para um imprevisto.
/// O líquido vem de [ServicoOrcamento] (backend); a tela não calcula taxa.
class CriarAditivoTela extends StatefulWidget {
  const CriarAditivoTela({
    super.key,
    required this.servico,
    required this.servicoLiquido,
    required this.pedidoId,
    required this.tituloPedido,
    this.aoCriado,
  });

  final ServicoAditivo servico;
  final ServicoOrcamento servicoLiquido;
  final String pedidoId;
  final String tituloPedido;
  final VoidCallback? aoCriado;

  @override
  State<CriarAditivoTela> createState() => _CriarAditivoTelaState();
}

class _CriarAditivoTelaState extends State<CriarAditivoTela> {
  final _motivo = TextEditingController();
  final _valor = TextEditingController();
  ResumoOrcamento? _resumo;
  bool _resumoFalhou = false;
  bool _tentou = false;
  bool _enviando = false;
  bool _criado = false;
  String? _erro;
  int _versao = 0;

  @override
  void dispose() {
    _motivo.dispose();
    _valor.dispose();
    super.dispose();
  }

  int? get _centavos {
    final c = Dinheiro.lerCentavos(_valor.text);
    return (c == null || c <= 0) ? null : c;
  }

  String? get _erroMotivo => _motivo.text.trim().length < 5 ? 'Explique o motivo em poucas palavras' : null;
  String? get _erroValor => _centavos == null ? 'Informe o valor, ex.: 45,00' : null;

  Future<void> _atualizarResumo() async {
    final c = _centavos;
    final minha = ++_versao;
    if (c == null) {
      setState(() {
        _resumo = null;
        _resumoFalhou = false;
      });
      return;
    }
    try {
      final r = await widget.servicoLiquido.resumir(c);
      if (!mounted || minha != _versao) return;
      setState(() {
        _resumo = r;
        _resumoFalhou = false;
      });
    } catch (_) {
      if (!mounted || minha != _versao) return;
      setState(() {
        _resumo = null;
        _resumoFalhou = true;
      });
    }
  }

  Future<void> _enviar() async {
    setState(() {
      _tentou = true;
      _erro = null;
    });
    if (_erroMotivo != null || _erroValor != null) return;
    setState(() => _enviando = true);
    try {
      await widget.servico.criar(NovoAditivo(
        pedidoId: widget.pedidoId,
        motivo: _motivo.text.trim(),
        valorCentavos: _centavos!,
      ));
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _criado = true;
      });
      widget.aoCriado?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Não foi possível enviar o aditivo. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaginaTrato(
      titulo: 'Novo aditivo',
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erro != null) ...[
            AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_criado)
            const AvisoFaixa(
              texto: 'Aditivo enviado. Aguardando a resposta do cliente.',
              tipo: TipoStatus.sucesso,
              icone: Icons.check_circle_outline,
            )
          else
            BotaoPrimario(
              texto: 'Enviar aditivo ao cliente',
              carregando: _enviando,
              aoTocar: _enviar,
            ),
        ],
      ),
      children: [
        Text('Imprevisto no serviço', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          widget.tituloPedido,
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        const AvisoFaixa(
          texto: 'O aditivo só vale se o cliente aprovar no app. Sem aprovação, '
              'o valor não muda.',
          tipo: TipoStatus.info,
          icone: Icons.info_outline,
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoLongo(
          rotulo: 'Motivo',
          controlador: _motivo,
          dica: 'O que apareceu que não estava no orçamento?',
          aoMudar: (_) => setState(() {}),
        ),
        if (_tentou && _erroMotivo != null)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2),
            child: Text(
              _erroMotivo!,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto),
            ),
          ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Valor do aditivo',
          controlador: _valor,
          prefixo: 'R\$ ',
          teclado: const TextInputType.numberWithOptions(decimal: true),
          erro: _tentou ? _erroValor : null,
          aoMudar: (_) {
            setState(() {});
            unawaited(_atualizarResumo());
          },
        ),
        const SizedBox(height: EspacosTrato.x4),
        _CartaoLiquido(resumo: _resumo, falhou: _resumoFalhou, digitou: _centavos != null),
      ],
    );
  }
}

class _CartaoLiquido extends StatelessWidget {
  const _CartaoLiquido({required this.resumo, required this.falhou, required this.digitou});

  final ResumoOrcamento? resumo;
  final bool falhou;
  final bool digitou;

  @override
  Widget build(BuildContext context) {
    final r = resumo;
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quanto você recebe', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x2),
          if (r != null) ...[
            _Linha('Valor do aditivo', Dinheiro.formatar(r.totalCentavos)),
            _Linha(r.taxaBps == null ? 'Taxa do Trato' : 'Taxa do Trato (${Dinheiro.formatarBps(r.taxaBps!)})', '- ${Dinheiro.formatar(r.taxaCentavos)}'),
            const Divider(),
            _Linha('Líquido', Dinheiro.formatar(r.liquidoCentavos), forte: true),
          ] else
            Text(
              falhou
                  ? 'Não foi possível calcular agora. Você ainda pode enviar o aditivo.'
                  : digitou
                      ? 'Calculando…'
                      : 'Digite o valor para ver quanto sobra para você.',
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            ),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor, {this.forte = false});

  final String rotulo;
  final String valor;
  final bool forte;

  @override
  Widget build(BuildContext context) {
    final estilo = forte ? TipografiaTrato.corpoForte : TipografiaTrato.corpo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: estilo)),
          const SizedBox(width: EspacosTrato.x2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(valor, style: estilo, maxLines: 1),
            ),
          ),
        ],
      ),
    );
  }
}
