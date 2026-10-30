import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show LinhaValor, formatarReais;
import '../profissional/dinheiro.dart';
import '../profissional_apoio/apoio.dart';
import 'nota_material.dart';

/// F6.5: o profissional manda ao cliente a foto da notinha e o valor de cada item.
/// [aoCapturarFoto] abre a câmera fora da tela e devolve a referência.
class EnviarNotaTela extends StatefulWidget {
  const EnviarNotaTela({
    super.key,
    required this.servico,
    required this.pedidoId,
    required this.tituloPedido,
    this.aoCapturarFoto,
    this.aoEnviada,
  });

  final ServicoNotaMaterial servico;
  final String pedidoId;
  final String tituloPedido;
  final CapturarFoto? aoCapturarFoto;
  final VoidCallback? aoEnviada;

  @override
  State<EnviarNotaTela> createState() => _EnviarNotaTelaState();
}

class _EnviarNotaTelaState extends State<EnviarNotaTela> {
  final _descricao = TextEditingController();
  final _valor = TextEditingController();
  final _itens = <ItemNota>[];
  String? _foto;
  String? _erroItem;
  bool _enviando = false;
  bool _enviada = false;
  String? _erroEnvio;

  @override
  void dispose() {
    _descricao.dispose();
    _valor.dispose();
    super.dispose();
  }

  void _adicionarItem() {
    final desc = _descricao.text.trim();
    final centavos = Dinheiro.lerCentavos(_valor.text);
    if (desc.isEmpty) return setState(() => _erroItem = 'Diga o que é o item');
    if (centavos == null || centavos <= 0) {
      return setState(() => _erroItem = 'Informe o valor do item, ex.: 46,50');
    }
    setState(() {
      _itens.add(ItemNota(descricao: desc, centavos: centavos));
      _descricao.clear();
      _valor.clear();
      _erroItem = null;
    });
  }

  Future<void> _tirarFoto() async {
    final ref = await widget.aoCapturarFoto?.call();
    if (ref != null && mounted) setState(() => _foto = ref);
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erroEnvio = null;
    });
    try {
      await widget.servico.enviar(
        EnvioNota(pedidoId: widget.pedidoId, fotoNota: _foto!, itens: [..._itens]),
      );
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _enviada = true;
      });
      widget.aoEnviada?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erroEnvio = 'Não foi possível enviar a nota. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final soma = _itens.fold<int>(0, (s, i) => s + i.centavos);
    final pronto = _foto != null && _itens.isNotEmpty && !_enviada;
    return PaginaTrato(
      titulo: 'Nota dos materiais',
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erroEnvio != null) ...[
            AvisoFaixa(texto: _erroEnvio!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_enviada) ...[
            const AvisoFaixa(
              texto: 'Nota enviada ao cliente.',
              tipo: TipoStatus.sucesso,
              icone: Icons.check_circle_outline,
            ),
          ] else
            BotaoPrimario(
              texto: 'Enviar nota ao cliente',
              carregando: _enviando,
              aoTocar: pronto ? _enviar : null,
            ),
        ],
      ),
      children: [
        Text('Mostre quanto custou cada material', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          widget.tituloPedido,
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const TituloSecao('Foto da notinha'),
        CampoFoto(
          rotulo: 'Foto da nota',
          referencia: _foto,
          aoTocar: widget.aoCapturarFoto == null ? () {} : _tirarFoto,
        ),
        const TituloSecao('Itens'),
        if (_itens.isEmpty)
          Text(
            'Nenhum item ainda. Adicione cada material da nota.',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          )
        else
          CartaoTrato(
            child: Column(
              children: [
                for (var i = 0; i < _itens.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == _itens.length - 1 ? 0 : EspacosTrato.x2),
                    child: Row(
                      children: [
                        Expanded(child: Text(_itens[i].descricao, style: TipografiaTrato.corpo)),
                        const SizedBox(width: EspacosTrato.x2),
                        Text(formatarReais(_itens[i].centavos), style: TipografiaTrato.corpoForte),
                        IconButton(
                          tooltip: 'Remover ${_itens[i].descricao}',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _itens.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                LinhaValor(rotulo: 'Soma dos itens', valor: formatarReais(soma)),
              ],
            ),
          ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(rotulo: 'Item', controlador: _descricao, dica: 'Ex.: 2 tomadas 20 A'),
        const SizedBox(height: EspacosTrato.x3),
        CampoTrato(
          rotulo: 'Valor',
          controlador: _valor,
          prefixo: 'R\$ ',
          teclado: const TextInputType.numberWithOptions(decimal: true),
          erro: _erroItem,
        ),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(texto: 'Adicionar item', icone: Icons.add, aoTocar: _adicionarItem),
      ],
    );
  }
}
