import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import '../em_breve_tela.dart';
import '../pedido_novo/pecas_pedido.dart';
import 'dados_exemplo.dart';
import 'detalhe_orcamento_tela.dart';
import 'modelos.dart';

/// Tela 12 do protótipo: "Orçamentos recebidos", com ordenação por valor, nota ou data.
///
/// [aoVerOrcamento] abre o detalhe. Sem ele, abre [DetalheOrcamentoTela] quando o orçamento
/// tem detalhe e [EmBreveTela] quando não tem.
final _padrao = orcamentosExemplo;

class OrcamentosRecebidosTela extends StatefulWidget {
  OrcamentosRecebidosTela({
    super.key,
    this.pedido = resumoPedidoExemplo,
    List<Orcamento>? orcamentos,
    this.aoVerOrcamento,
  }) : orcamentos = orcamentos ?? _padrao;

  final ResumoPedido pedido;
  final List<Orcamento> orcamentos;
  final ValueChanged<Orcamento>? aoVerOrcamento;

  @override
  State<OrcamentosRecebidosTela> createState() => _OrcamentosRecebidosTelaState();
}

class _OrcamentosRecebidosTelaState extends State<OrcamentosRecebidosTela> {
  var _ordem = Ordenacao.menorValor;

  List<Orcamento> get _ordenados {
    final lista = [...widget.orcamentos];
    switch (_ordem) {
      case Ordenacao.menorValor:
        lista.sort((a, b) => a.totalCentavos.compareTo(b.totalCentavos));
      case Ordenacao.maiorNota:
        lista.sort((a, b) => b.nota.compareTo(a.nota));
      case Ordenacao.maisCedo:
        lista.sort((a, b) => a.inicio.compareTo(b.inicio));
    }
    return lista;
  }

  void _ver(Orcamento o) {
    if (widget.aoVerOrcamento != null) {
      widget.aoVerOrcamento!(o);
      return;
    }
    final tela = o.detalhe == null
        ? EmBreveTela(titulo: 'Orçamento de ${o.profissional}')
        : DetalheOrcamentoTela(orcamento: o);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tela));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    return EstruturaPedido(
      tituloBarra: 'Pedido #${p.numero}',
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Text('Orçamentos recebidos', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          p.titulo,
          style: TipografiaTrato.corpoGrande.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        AvisoInfo(
          texto: TextSpan(
            children: [
              TextSpan(
                text: '${p.recebidos} de ${p.limite}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: ' orçamentos. Recebendo por mais ${p.tempoRestante}.'),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final o in Ordenacao.values)
              ChipOpcao(
                texto: o.rotulo,
                marcado: o == _ordem,
                aoTocar: () => setState(() => _ordem = o),
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        for (final o in _ordenados) ...[
          _CartaoOrcamento(orcamento: o, aoVer: () => _ver(o)),
          const SizedBox(height: EspacosTrato.x4),
        ],
      ],
    );
  }
}

class _CartaoOrcamento extends StatelessWidget {
  const _CartaoOrcamento({required this.orcamento, required this.aoVer});

  final Orcamento orcamento;
  final VoidCallback aoVer;

  @override
  Widget build(BuildContext context) {
    final o = orcamento;
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarIniciais(iniciais: o.iniciais),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.profissional, style: TipografiaTrato.tituloCartao),
                    const SizedBox(height: EspacosTrato.x1),
                    SeloVerificacao(o.verificacao),
                  ],
                ),
              ),
              const SizedBox(width: EspacosTrato.x2),
              Flexible(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatarReais(o.totalCentavos),
                        maxLines: 1,
                        style: TipografiaTrato.titulo,
                      ),
                    ),
                    Text(
                      'total',
                      style: TipografiaTrato.corpoPequeno.copyWith(
                        color: CoresTrato.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Dado(rotulo: 'Nota', valor: o.notaResumo)),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: _Dado(rotulo: 'Serviços concluídos', valor: o.servicosResumo)),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Dado(rotulo: 'Quando', valor: o.quando)),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: _Dado(rotulo: 'Garantia', valor: o.garantia)),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            o.observacao,
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x4),
          BotaoSecundario(texto: 'Ver orçamento', aoTocar: aoVer),
        ],
      ),
    );
  }
}

class _Dado extends StatelessWidget {
  const _Dado({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x1),
        Text(valor, style: TipografiaTrato.corpoForte),
      ],
    );
  }
}
