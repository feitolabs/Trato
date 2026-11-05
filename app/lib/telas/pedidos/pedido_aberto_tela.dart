import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/repositorios.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import '../pedido_novo/pecas_pedido.dart';

/// "R$ 1.250,50", "1250,5" ou "1250" viram centavos. Vazio ou inválido: nulo.
int? centavosDoTexto(String texto) {
  final limpo = texto.replaceAll(RegExp(r'[^0-9,]'), '').replaceAll('.', '');
  if (limpo.isEmpty) return null;
  final partes = limpo.split(',');
  final reais = int.tryParse(partes[0].isEmpty ? '0' : partes[0]);
  if (reais == null) return null;
  var centavos = 0;
  if (partes.length > 1 && partes[1].isNotEmpty) {
    centavos = int.tryParse(partes[1].padRight(2, '0').substring(0, 2)) ?? 0;
  }
  return reais * 100 + centavos;
}

/// O pedido do cliente enquanto aguarda orçamentos: mostra o que foi descrito e deixa trocar
/// descrição, valor pretendido e endereço. O backend decide se ainda pode editar.
class PedidoAbertoTela extends StatefulWidget {
  const PedidoAbertoTela({
    super.key,
    required this.numero,
    required this.dados,
    required this.aoSalvar,
    required this.aoVerOrcamentos,
  });

  final String numero;
  final DadosDoPedido dados;

  /// Devolve os dados como ficaram gravados; se falhar, a própria função avisa e devolve nulo.
  final Future<DadosDoPedido?> Function({
    required String descricao,
    required int faixaMaxCentavos,
    required String logradouro,
    required String numero,
    required String bairro,
  })
  aoSalvar;
  final VoidCallback aoVerOrcamentos;

  @override
  State<PedidoAbertoTela> createState() => _PedidoAbertoTelaState();
}

class _PedidoAbertoTelaState extends State<PedidoAbertoTela> {
  late DadosDoPedido _dados = widget.dados;
  var _editando = false;
  var _salvando = false;
  String? _erro;

  late final _descricao = TextEditingController(text: _dados.descricao);
  late final _valor = TextEditingController();
  late final _rua = TextEditingController(text: _dados.logradouro ?? '');
  late final _numero = TextEditingController(text: _dados.numero ?? '');
  late final _bairro = TextEditingController(text: _dados.bairro ?? '');

  @override
  void dispose() {
    for (final c in [_descricao, _valor, _rua, _numero, _bairro]) {
      c.dispose();
    }
    super.dispose();
  }

  void _comecarEdicao() {
    _descricao.text = _dados.descricao;
    final max = _dados.faixaMaxCentavos;
    _valor.text = max == null ? '' : (max / 100).toStringAsFixed(2).replaceAll('.', ',');
    _rua.text = _dados.logradouro ?? '';
    _numero.text = _dados.numero ?? '';
    _bairro.text = _dados.bairro ?? '';
    setState(() {
      _editando = true;
      _erro = null;
    });
  }

  Future<void> _salvar() async {
    final descricao = _descricao.text.trim();
    if (descricao.isEmpty) {
      setState(() => _erro = 'Descreva o que precisa ser feito.');
      return;
    }
    final textoValor = _valor.text.trim();
    final valor = textoValor.isEmpty ? 0 : centavosDoTexto(textoValor);
    if (valor == null) {
      setState(() => _erro = 'Digite o valor em reais. Ex.: 900,00');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final novos = await widget.aoSalvar(
      descricao: descricao,
      faixaMaxCentavos: valor,
      logradouro: _rua.text,
      numero: _numero.text,
      bairro: _bairro.text,
    );
    if (!mounted) return;
    setState(() {
      _salvando = false;
      if (novos != null) {
        _dados = novos;
        _editando = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return EstruturaPedido(
      tituloBarra: 'Pedido #${widget.numero}',
      rodape: _editando
          ? Row(
              children: [
                Expanded(
                  child: BotaoSecundario(
                    texto: 'Cancelar',
                    aoTocar: _salvando ? null : () => setState(() => _editando = false),
                  ),
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: BotaoPrimario(
                    texto: 'Salvar',
                    carregando: _salvando,
                    aoTocar: _salvar,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BotaoPrimario(texto: 'Ver orçamentos', aoTocar: widget.aoVerOrcamentos),
                const SizedBox(height: EspacosTrato.x2),
                BotaoSecundario(texto: 'Editar pedido', aoTocar: _comecarEdicao),
              ],
            ),
      children: [
        const SizedBox(width: double.infinity, height: EspacosTrato.x2),
        Text('Seu pedido', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          _dados.titulo,
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        if (_editando) ..._formulario() else ..._resumo(),
      ],
    );
  }

  List<Widget> _resumo() {
    final max = _dados.faixaMaxCentavos;
    return [
      CartaoTrato(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('O que precisa ser feito', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(_dados.descricao, style: TipografiaTrato.corpo),
            const SizedBox(height: EspacosTrato.x4),
            Text('Quanto pretende gastar', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(
              max == null ? 'Sem limite definido' : 'Até ${formatarReais(max)}',
              style: TipografiaTrato.corpo,
            ),
            const SizedBox(height: EspacosTrato.x4),
            Text('Endereço', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(_dados.enderecoResumo ?? 'Ainda sem endereço', style: TipografiaTrato.corpo),
          ],
        ),
      ),
    ];
  }

  List<Widget> _formulario() => [
    CampoTrato(rotulo: 'Descreva o que precisa', controlador: _descricao),
    const SizedBox(height: EspacosTrato.x4),
    CampoTrato(
      rotulo: 'Quanto pretende gastar (no máximo)',
      controlador: _valor,
      prefixo: 'R\$ ',
      dica: '900,00',
      ajuda: 'Deixe vazio para não limitar.',
      teclado: const TextInputType.numberWithOptions(decimal: true),
    ),
    const SizedBox(height: EspacosTrato.x4),
    CampoTrato(rotulo: 'Rua', controlador: _rua),
    const SizedBox(height: EspacosTrato.x4),
    CampoTrato(rotulo: 'Número', controlador: _numero),
    const SizedBox(height: EspacosTrato.x4),
    CampoTrato(rotulo: 'Bairro', controlador: _bairro),
    if (_erro != null) ...[
      const SizedBox(height: EspacosTrato.x3),
      Text(_erro!, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.vermelhoTexto)),
    ],
  ];
}
