import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart';
import '../comuns/textos_dos_termos.dart';
import '../medidas/modelos.dart' show ProvaEscolhida, nomeDoTipo, tamanhoLegivel, tipoDaProva;
import '../profissional/dinheiro.dart';
import 'modelos.dart';

String _quando(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}, ${horaDoAparelho(d)}';

/// "Contestar a decisão" (Termos 8.7), para o cliente e o profissional.
class ContestacaoDecisaoTela extends StatefulWidget {
  const ContestacaoDecisaoTela({
    super.key,
    required this.servico,
    required this.pedidoId,
    required this.aoFalarComOTrato,
    this.escolherFoto,
  });

  final ServicoContestacaoDecisao servico;
  final String pedidoId;
  final void Function(BuildContext context) aoFalarComOTrato;

  /// Tira a foto para anexar (nulo se a pessoa cancelar).
  final Future<ProvaEscolhida?> Function()? escolherFoto;

  @override
  State<ContestacaoDecisaoTela> createState() => _ContestacaoDecisaoTelaState();
}

class _ContestacaoDecisaoTelaState extends State<ContestacaoDecisaoTela> {
  // Texto e arquivos ficam aqui: erro ou atualização da tela não apaga o que foi preenchido.
  final _texto = TextEditingController();
  final _arquivos = <ProvaEscolhida>[];
  var _enviando = false;
  var _versao = 0;
  String? _erroTexto;
  String? _erroArquivo;
  int? _arquivoComErro;
  String? _erro;
  String? _recebida;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    setState(() => _erroArquivo = null);
    try {
      final foto = await widget.escolherFoto!();
      if (foto == null || !mounted) return;
      setState(() => _arquivos.add(foto));
    } on Object catch (e) {
      if (mounted) setState(() => _erroArquivo = mensagemErroTrato(e));
    }
  }

  Future<void> _enviar() async {
    final texto = _texto.text.trim();
    setState(() {
      _erro = null;
      _erroArquivo = null;
      _arquivoComErro = null;
      _erroTexto =
          texto.length < minimoDoTexto ? 'Escreva pelo menos $minimoDoTexto caracteres.' : null;
    });
    if (_erroTexto != null) return;
    setState(() => _enviando = true);
    try {
      final c = await widget.servico.contestar(widget.pedidoId, texto, arquivos: _arquivos);
      if (!mounted) return;
      setState(() {
        _recebida = c.protocolo == null
            ? 'Contestação enviada.'
            : 'Contestação enviada. Protocolo ${c.protocolo}.';
        _texto.clear();
        _arquivos.clear();
        _enviando = false;
        _versao++;
      });
    } on ErroDeArquivo catch (e) {
      if (!mounted) return;
      setState(() {
        _arquivoComErro = e.indice;
        _erroArquivo = e.mensagem;
        _enviando = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = mensagemErroTrato(e);
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    return MolduraTelaComum(
      titulo: 'Contestar a decisão',
      child: CarregadorTela<ContestacoesDoPedido?>(
        key: ValueKey('contestacoes-$_versao'),
        carregar: () => widget.servico.ver(widget.pedidoId),
        construir: (context, dados, recarregar) {
          if (dados == null) {
            return EstadoVazio(
              icone: Icons.gavel_outlined,
              titulo: 'Contestação indisponível',
              texto: 'Não dá para contestar por aqui agora. Fale com o Trato.',
              textoAcao: 'Falar com o Trato',
              aoAcao: () => widget.aoFalarComOTrato(context),
            );
          }
          if (!dados.temDecisao) {
            return EstadoVazio(
              icone: Icons.gavel_outlined,
              titulo: 'Nenhuma decisão para contestar',
              texto: 'Quando a disputa deste pedido for decidida, a contestação aparece aqui.',
              textoAcao: 'Falar com o Trato',
              aoAcao: () => widget.aoFalarComOTrato(context),
            );
          }
          final ate = dados.contestarAte;
          // Com um erro de envio na tela, o formulário continua mesmo se a lista mudar.
          final formulario = dados.podeContestar || _erro != null || _erroArquivo != null;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_recebida != null) ...[
                  Text(_recebida!,
                      key: const Key('contestacao-da-decisao-recebida'),
                      style: TipografiaTrato.corpoForte),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                for (final c in dados.itens) ...[
                  _CartaoContestacao(item: c),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                if (formulario) ..._formulario(context, ate, secundario),
                if (!formulario && dados.minha == null) ...[
                  Text(
                    ate == null
                        ? 'Não é possível contestar por aqui.'
                        : 'O prazo para contestar terminou em ${_quando(ate)}.',
                    key: const Key('prazo-encerrado'),
                    style: TipografiaTrato.corpo,
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                BotaoLink(
                  key: const Key('falar-sobre-decisao'),
                  texto: 'Falar com o Trato',
                  aoTocar: () => widget.aoFalarComOTrato(context),
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(textoAtendimentoHumano, style: secundario),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _formulario(BuildContext context, DateTime? ate, TextStyle secundario) {
    final erro = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto);
    return [
      Text('Você pode contestar uma vez. Outra pessoa vai analisar.', style: TipografiaTrato.corpo),
      if (ate != null) ...[
        const SizedBox(height: EspacosTrato.x1),
        Text('Dá para contestar até ${_quando(ate)}.',
            key: const Key('prazo-contestar'), style: TipografiaTrato.corpoForte),
      ],
      const SizedBox(height: EspacosTrato.x3),
      Text('O que a análise não considerou?', style: TipografiaTrato.corpoForte),
      const SizedBox(height: EspacosTrato.x1),
      TextField(
        key: const Key('o-que-faltou'),
        controller: _texto,
        enabled: !_enviando,
        minLines: 4,
        maxLines: 8,
        maxLength: maximoDoTexto,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'De $minimoDoTexto a $maximoDoTexto caracteres.',
          errorText: _erroTexto,
          errorMaxLines: 3,
        ),
      ),
      if (widget.escolherFoto != null && widget.servico.podeAnexar) ...[
        const SizedBox(height: EspacosTrato.x2),
        for (final (i, a) in _arquivos.indexed) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${i + 1}. ${nomeDoTipo(tipoDaProva(a.bytes) ?? '')} · '
                  '${tamanhoLegivel(a.bytes.length)}',
                  style: TipografiaTrato.corpo,
                ),
              ),
              IconButton(
                key: ValueKey('remover-arquivo-$i'),
                tooltip: 'Remover arquivo ${i + 1}',
                icon: const Icon(Icons.close),
                onPressed: _enviando
                    ? null
                    : () => setState(() {
                          _arquivos.removeAt(i);
                          _arquivoComErro = null;
                          _erroArquivo = null;
                        }),
              ),
            ],
          ),
          if (_arquivoComErro == i && _erroArquivo != null)
            Text(_erroArquivo!, key: ValueKey('erro-arquivo-$i'), style: erro),
        ],
        if (_arquivoComErro == null && _erroArquivo != null)
          Text(_erroArquivo!, key: const Key('erro-adicionar-arquivo'), style: erro),
        if (_arquivos.length < maximoDeArquivos)
          BotaoSecundario(
            key: const Key('adicionar-arquivo'),
            texto: 'Adicionar foto',
            aoTocar: _enviando ? null : _adicionar,
          ),
      ],
      const SizedBox(height: EspacosTrato.x3),
      if (_erro != null) ...[
        Text(_erro!, key: const Key('erro-contestar-decisao'), style: erro),
        const SizedBox(height: EspacosTrato.x2),
      ],
      BotaoPrimario(
        key: const Key('enviar-contestacao-decisao'),
        texto: 'Enviar contestação',
        carregando: _enviando,
        aoTocar: _enviando ? null : _enviar,
      ),
      const SizedBox(height: EspacosTrato.x2),
    ];
  }
}

class _CartaoContestacao extends StatelessWidget {
  const _CartaoContestacao({required this.item});

  final ContestacaoDaParte item;

  @override
  Widget build(BuildContext context) {
    final c = item;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    List<Widget> bloco(String rotulo, String? texto) => [
          if (texto != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(rotulo, style: secundario),
            Text(texto, style: TipografiaTrato.corpo),
          ],
        ];
    final valor = c.novoValorReembolsoCentavos;
    return CartaoTrato(
      key: ValueKey('contestacao-decisao-${c.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(c.minha ? 'Sua contestação' : 'Contestação da outra parte',
              style: TipografiaTrato.tituloCartao),
          const SizedBox(height: EspacosTrato.x1),
          Text(c.statusTexto, style: TipografiaTrato.corpoForte),
          if (c.protocolo != null) Text('Protocolo ${c.protocolo}', style: secundario),
          ...bloco('Enviada em', c.abertaEm == null ? null : _quando(c.abertaEm!)),
          if (c.decididaEm != null)
            ...bloco('Respondida em', _quando(c.decididaEm!))
          else
            ...bloco('Resposta até', c.responderAte == null ? null : _quando(c.responderAte!)),
          ...bloco('O que você contestou', c.minha ? c.oQueFaltou : null),
          ...bloco(
              'Arquivos enviados', c.minha && c.anexos.isNotEmpty ? '${c.anexos.length}' : null),
          ...bloco('Resposta', c.resposta),
          ...bloco('Nova decisão', c.novaDecisaoTexto),
          ...bloco('Novo valor do reembolso', valor == null ? null : Dinheiro.formatar(valor)),
        ],
      ),
    );
  }
}

/// A entrada no pedido: aparece quando há decisão de disputa. Some com 404/503; numa falha
/// passageira aparece, e a tela dela tem "Tentar de novo".
class SecaoContestacaoDecisao extends StatefulWidget {
  const SecaoContestacaoDecisao({
    super.key,
    required this.carregar,
    required this.aoAbrir,
    this.atualizarQuando,
  });

  final Future<ContestacoesDoPedido?> Function() carregar;
  final Future<void> Function() aoAbrir;
  final Listenable? atualizarQuando;

  @override
  State<SecaoContestacaoDecisao> createState() => _SecaoContestacaoDecisaoState();
}

class _SecaoContestacaoDecisaoState extends State<SecaoContestacaoDecisao> {
  ContestacoesDoPedido? _dados;
  var _falhou = false;
  var _geracao = 0;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_buscar);
    _buscar();
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_buscar);
    super.dispose();
  }

  Future<void> _buscar() async {
    final minha = ++_geracao;
    try {
      final dados = await widget.carregar();
      if (!mounted || minha != _geracao) return;
      setState(() {
        _dados = dados;
        _falhou = false;
      });
    } on Object {
      // Com um dado já lido, ele continua na tela.
      if (mounted && minha == _geracao) setState(() => _falhou = _dados == null);
    }
  }

  Future<void> _abrir() async {
    await widget.aoAbrir();
    if (mounted) await _buscar();
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    if (!_falhou && (d == null || !d.temDecisao)) return const SizedBox.shrink();
    final minha = d?.minha;
    final ate = d?.contestarAte;
    final texto = d == null
        ? 'Não deu para conferir a contestação agora.'
        : minha != null
            ? 'Sua contestação: ${minha.statusTexto.toLowerCase()}.'
            : d.podeContestar
                ? (ate == null
                    ? 'Dá para contestar a decisão.'
                    : 'Dá para contestar até ${_quando(ate)}.')
                : (ate == null
                    ? 'Veja o andamento da contestação.'
                    : 'O prazo para contestar terminou em ${_quando(ate)}.');
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        key: const Key('secao-contestacao-decisao'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Decisão da disputa', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(texto, style: TipografiaTrato.corpo),
            const SizedBox(height: EspacosTrato.x3),
            BotaoSecundario(
              key: const Key('abrir-contestacao-decisao'),
              texto: d?.podeContestar == true ? 'Contestar a decisão' : 'Ver contestação',
              aoTocar: _abrir,
            ),
          ],
        ),
      ),
    );
  }
}
