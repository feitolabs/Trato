import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
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
    this.servicoEmAndamento = true,
  });

  final ServicoNotaMaterial servico;
  final String pedidoId;
  final String tituloPedido;
  final CapturarFoto? aoCapturarFoto;
  final VoidCallback? aoEnviada;

  /// Verdadeiro quando o profissional já fez check-in e o serviço está em andamento.
  final bool servicoEmAndamento;

  @override
  State<EnviarNotaTela> createState() => _EnviarNotaTelaState();
}

class _EnviarNotaTelaState extends State<EnviarNotaTela> {
  final _descricao = TextEditingController();
  final _quantidade = TextEditingController(text: '1');
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
    _quantidade.dispose();
    _valor.dispose();
    super.dispose();
  }

  void _adicionarItem() {
    const maxQtd = 9999;
    const maxTotalCentavos = 100000000;
    final desc = _descricao.text.trim();
    final qtdTexto = _quantidade.text.trim();
    final qtd = int.tryParse(qtdTexto);
    final centavos = Dinheiro.lerCentavos(_valor.text);
    if (desc.isEmpty) {
      return setState(() => _erroItem = 'Descrição vazia. Digite o que é o item.');
    }
    if (qtd == null || qtd <= 0 || qtd > maxQtd) {
      return setState(
          () => _erroItem = 'Quantidade inválida. Digite um número inteiro entre 1 e 9.999.');
    }
    if (centavos == null || centavos <= 0) {
      return setState(() =>
          _erroItem = 'Valor não informado. Digite um valor em reais maior que zero (ex.: 46,50).');
    }
    if (centavos > maxTotalCentavos || qtd > maxTotalCentavos ~/ centavos) {
      return setState(() => _erroItem = 'Valor do item acima do limite permitido.');
    }
    final totalItem = qtd * centavos;
    final somaAtual = _itens.fold<int>(0, (s, i) => s + i.centavos);
    if (somaAtual > maxTotalCentavos - totalItem) {
      return setState(() => _erroItem = 'Soma da nota acima do limite permitido.');
    }
    setState(() {
      _itens.add(ItemNota(
        descricao: desc,
        quantidade: qtd,
        valorUnitarioCentavos: centavos,
      ));
      _descricao.clear();
      _quantidade.text = '1';
      _valor.clear();
      _erroItem = null;
    });
  }

  Future<void> _tirarFoto() async {
    try {
      final ref = await widget.aoCapturarFoto?.call();
      if (ref != null && mounted) setState(() => _foto = ref);
    } on Object {
      if (mounted) {
        setState(() => _erroEnvio = 'Não foi possível capturar a foto agora. Tente de novo.');
      }
    }
  }

  Future<void> _enviar() async {
    if (_enviando) return;
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
    } catch (e) {
      if (!mounted) return;
      // Recusa do backend (ex.: serviço ainda não iniciado): mostra o motivo, não "conexão".
      final motivo = e is ErroTrato && e.tipo != TipoErro.semInternet && e.mensagem.isNotEmpty
          ? e.mensagem
          : null;
      setState(() {
        _enviando = false;
        _erroEnvio =
            motivo ?? 'Não foi possível enviar a nota. Confira sua conexão e tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final soma = _itens.fold<int>(0, (s, i) => s + i.centavos);
    final pronto = _foto != null && _itens.isNotEmpty && !_enviada && widget.servicoEmAndamento;
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
          style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
        ),
        if (!widget.servicoEmAndamento) ...[
          const SizedBox(height: EspacosTrato.x3),
          const AvisoFaixa(
            key: ValueKey('aviso-nota-aguardando-checkin'),
            texto: 'Envio disponível após iniciar o serviço (check-in).',
            tipo: TipoStatus.alerta,
            icone: Icons.info_outline,
          ),
        ],
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
            style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
          )
        else
          CartaoTrato(
            child: Column(
              children: [
                for (var i = 0; i < _itens.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == _itens.length - 1 ? 0 : EspacosTrato.x2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _rotuloItem(_itens[i]),
                            style: TipografiaTrato.corpo,
                          ),
                        ),
                        const SizedBox(width: EspacosTrato.x2),
                        Flexible(
                          flex: 0,
                          child: Text(
                            formatarReais(_itens[i].centavos),
                            style: TipografiaTrato.corpoForte,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remover ${_itens[i].descricao}',
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
        CampoTrato(rotulo: 'Item', controlador: _descricao, dica: 'Ex.: Tomada 20 A'),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: CampoTrato(
                rotulo: 'Quantidade',
                controlador: _quantidade,
                dica: '1',
                teclado: TextInputType.number,
              ),
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              flex: 3,
              child: CampoTrato(
                rotulo: 'Valor',
                controlador: _valor,
                prefixo: 'R\$ ',
                teclado: const TextInputType.numberWithOptions(decimal: true),
                dica: '0,00',
              ),
            ),
          ],
        ),
        if (_erroItem != null) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text(
            _erroItem!,
            style: TipografiaTrato.legenda.copyWith(color: context.cores.vermelhoTexto),
          ),
        ],
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(texto: 'Adicionar item', icone: Icons.add, aoTocar: _adicionarItem),
      ],
    );
  }

  String _rotuloItem(ItemNota item) {
    return item.rotuloComConta(formatarReais);
  }
}
