import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../cliente/modelos.dart' show formatarNota;
import '../conclusao/apoio_conclusao.dart' show LinhaValor, formatarReais;
import '../em_breve_tela.dart';
import '../pedido_novo/pecas_pedido.dart';
import 'modelos.dart';

/// Tela 13 do protótipo: detalhe do orçamento, com aceite e contraproposta.
///
/// Só mostra o que vier de [orcamento]; o 30% adiantado e a taxa são do backend. Os callbacks
/// são opcionais; sem eles, abrem [EmBreveTela]. [aoAceitar] só dispara com o aceite marcado.
class DetalheOrcamentoTela extends StatefulWidget {
  const DetalheOrcamentoTela({
    super.key,
    required this.orcamento,
    this.aoAceitar,
    this.aoFazerContraproposta,
    this.aoConversar,
    this.aoVerPerfil,
  });

  final Orcamento orcamento;
  final ValueChanged<Orcamento>? aoAceitar;
  final ValueChanged<Orcamento>? aoFazerContraproposta;
  final ValueChanged<Orcamento>? aoConversar;

  /// Abre o perfil público do profissional. Sem ele, o link não aparece.
  final ValueChanged<Orcamento>? aoVerPerfil;

  @override
  State<DetalheOrcamentoTela> createState() => _DetalheOrcamentoTelaState();
}

class _DetalheOrcamentoTelaState extends State<DetalheOrcamentoTela> {
  var _leu = false;
  var _tentou = false;

  void _emBreve(String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  void _chamar(ValueChanged<Orcamento>? acao, String titulo) =>
      acao != null ? acao(widget.orcamento) : _emBreve(titulo);

  void _aceitar() {
    setState(() => _tentou = true);
    if (_leu) _chamar(widget.aoAceitar, 'Pagamento');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.orcamento;
    final d = o.detalhe!; // a tela só abre para orçamento com detalhe
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return EstruturaPedido(
      tituloBarra: 'Válido até ${d.validoAte}',
      acoesBarra: [
        TextButton.icon(
          onPressed: () => _chamar(widget.aoConversar, 'Chat'),
          icon: const Icon(Icons.chat_bubble_outline, size: EspacosTrato.x5),
          label: const Text('Conversar'),
          style: TextButton.styleFrom(
            textStyle: TipografiaTrato.corpoForte.copyWith(decoration: TextDecoration.none),
          ),
        ),
        const SizedBox(width: EspacosTrato.x2),
      ],
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotaoPrimario(
            texto: 'Aceitar orçamento · ${formatarReais(o.totalCentavos)}',
            aoTocar: _aceitar,
          ),
          BotaoLink(
            texto: 'Fazer contraproposta',
            aoTocar: () => _chamar(widget.aoFazerContraproposta, 'Contraproposta'),
          ),
        ],
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AvatarIniciais(iniciais: o.iniciais, tamanho: 64),
            const SizedBox(width: EspacosTrato.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.profissional, style: TipografiaTrato.tituloGrande),
                  const SizedBox(height: EspacosTrato.x1),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SeloVerificacao(o.verificacao),
                      Text(
                        ' · Nota ${formatarNota(o.nota)} · ${o.servicosConcluidos} serviços',
                        style: secundario,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (widget.aoVerPerfil != null)
          BotaoLink(
            texto: 'Ver perfil de ${o.profissional}',
            aoTocar: () => widget.aoVerPerfil!(o),
          ),
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('O que está incluso', style: TipografiaTrato.tituloOpcao),
              const SizedBox(height: EspacosTrato.x4),
              for (final item in d.itens) ...[
                LinhaValor(rotulo: item.descricao, valor: formatarReais(item.centavos)),
                const SizedBox(height: EspacosTrato.x3),
              ],
              const Divider(),
              const SizedBox(height: EspacosTrato.x3),
              LinhaValor(rotulo: 'Total', valor: formatarReais(o.totalCentavos), destaque: true),
              const SizedBox(height: EspacosTrato.x3),
              Text(d.notaMaterial, style: secundario),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Card(
          child: Column(
            children: [
              _BlocoRegra(
                icone: Icons.calendar_today_outlined,
                titulo: d.agendaTitulo,
                texto: d.agendaDetalhe,
              ),
              const Divider(height: 1),
              _BlocoRegra(
                icone: Icons.verified_user_outlined,
                titulo: d.garantiaTitulo,
                texto: d.garantiaDetalhe,
              ),
              const Divider(height: 1),
              _BlocoRegra(
                icone: Icons.warning_amber_rounded,
                titulo: 'Fora do escopo',
                texto: d.foraDoEscopo,
              ),
              const Divider(height: 1),
              _BlocoRegra(
                icone: Icons.schedule,
                titulo: 'Cancelamento',
                texto: d.cancelamento,
              ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        MergeSemantics(child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: _leu, onChanged: (v) => setState(() => _leu = v ?? false)),
            const SizedBox(width: EspacosTrato.x2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: EspacosTrato.x3),
                child: Text(
                  'Li o escopo, a garantia e as regras de cancelamento. '
                  'Ao aceitar, este orçamento vira o contrato do serviço.',
                  style: TipografiaTrato.corpo,
                ),
              ),
            ),
          ],
        )),
        if (_tentou && !_leu)
          Text(
            'Marque que leu para aceitar o orçamento.',
            style: TipografiaTrato.legenda.copyWith(color: CoresTrato.vermelhoTexto),
          ),
      ],
    );
  }
}

class _BlocoRegra extends StatelessWidget {
  const _BlocoRegra({required this.icone, required this.titulo, required this.texto});

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: CoresTrato.petroleo),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TipografiaTrato.corpoForte),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  texto,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
