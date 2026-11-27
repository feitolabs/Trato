/// Termos 6.9: o cliente contesta material não comprovado ou diferente do combinado e acompanha.
/// Quem confere valor, prazo e decisão é o servidor: o app só pede e mostra, e nunca diz que
/// haverá devolução nem que algo foi devolvido ou pago.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../conclusao/apoio_conclusao.dart' show formatarData, formatarReais;
import '../contestacao_decisao/modelos.dart' show ErroDeArquivo;
import '../medidas/modelos.dart' show ProvaEscolhida, tamanhoLegivel;
import '../profissional/dinheiro.dart';
import 'nota_material.dart';

const motivosContestacaoMaterial = <String, String>{
  'nao_comprovado': 'Material não comprovado',
  'diferente_do_combinado': 'Material diferente do combinado',
};

const maximoDeAnexosDoMaterial = 10;
const minimoDaDescricaoDoMaterial = 10;

const _semFuncao = 'Contestar material pelo app ainda não está disponível. Fale com o Trato.';

/// Uma contestação como o servidor devolve. Campo ausente vira vazio.
class ContestacaoMaterial {
  const ContestacaoMaterial({
    this.id = '',
    this.protocolo = '',
    this.notaId = '',
    this.itemId,
    this.motivo = '',
    this.descricao = '',
    this.quantidadeDeAnexos = 0,
    this.valorContestadoCentavos,
    this.abertaEm,
    this.responderAte,
    this.status = '',
    this.resposta,
    this.valorReconhecidoCentavos,
    this.decididaEm,
  });

  factory ContestacaoMaterial.deJson(Map<Object?, Object?> json) {
    String? texto(String chave) {
      final v = json[chave];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    int? centavos(String chave) {
      final v = json[chave];
      return v is int && v >= 0 ? v : null;
    }

    DateTime? data(String chave) => DateTime.tryParse(texto(chave) ?? '')?.toLocal();
    final anexos = json['anexos'];

    return ContestacaoMaterial(
      id: texto('id') ?? '',
      protocolo: texto('protocolo') ?? '',
      notaId: texto('nota_id') ?? '',
      itemId: texto('item_id'),
      motivo: texto('motivo') ?? '',
      descricao: texto('descricao') ?? '',
      quantidadeDeAnexos: anexos is List ? anexos.length : 0,
      valorContestadoCentavos: centavos('valor_contestado_centavos'),
      abertaEm: data('aberta_em'),
      responderAte: data('responder_ate'),
      status: texto('status') ?? '',
      resposta: texto('resposta'),
      valorReconhecidoCentavos: centavos('valor_reconhecido_centavos'),
      decididaEm: data('decidida_em'),
    );
  }

  final String id;
  final String protocolo;
  final String notaId;
  final String? itemId;
  final String motivo;
  final String descricao;
  final int quantidadeDeAnexos;
  final int? valorContestadoCentavos;
  final DateTime? abertaEm;
  final DateTime? responderAte;
  final String status;
  final String? resposta;
  final int? valorReconhecidoCentavos;
  final DateTime? decididaEm;
}

abstract interface class ServicoContestacaoMaterial {
  bool get podeAnexar;

  /// Nulo: o servidor não tem a função (404/503) ou esta conta não pode ver (403).
  Future<List<ContestacaoMaterial>?> listarContestacoes(String pedidoId);

  /// Envia as fotos que ainda não subiram e depois a contestação.
  Future<ContestacaoMaterial> contestarMaterial(
    String pedidoId,
    String notaId, {
    required String motivo,
    required String descricao,
    required int valorCentavos,
    String? itemId,
    List<ProvaEscolhida> arquivos = const [],
  });
}

(String, TipoStatus) _situacao(String status) => switch (status) {
      'aberta' => ('Contestação enviada', TipoStatus.info),
      'em_analise' => ('Em análise', TipoStatus.info),
      'procedente' => ('Aceita na análise', TipoStatus.sucesso),
      'parcial' => ('Aceita em parte', TipoStatus.alerta),
      'improcedente' => ('Não aceita', TipoStatus.perigo),
      _ => ('Situação não informada', TipoStatus.info),
    };

/// "Nota 2 · Resistência 220 V". Sem como achar a nota ou o item, diz o que dá.
String _alvo(ContestacaoMaterial c, List<NotaMaterial> notas) {
  final posicao = notas.indexWhere((n) => n.id != null && n.id == c.notaId);
  final nota = posicao < 0 ? null : notas[posicao];
  final nome = nota == null || notas.length == 1 ? 'Nota' : 'Nota ${posicao + 1}';
  if (c.itemId == null) return '$nome inteira';
  final item = nota?.itens.where((i) => i.id == c.itemId).firstOrNull;
  return '$nome · ${item?.descricao ?? 'um item'}';
}

/// Lista e botão de contestar, dentro da tela da nota do cliente.
class SecaoContestacaoMaterial extends StatefulWidget {
  const SecaoContestacaoMaterial({
    super.key,
    required this.servico,
    required this.pedidoId,
    required this.notas,
    this.escolherFoto,
  });

  final ServicoContestacaoMaterial servico;
  final String pedidoId;
  final List<NotaMaterial> notas;
  final Future<ProvaEscolhida?> Function()? escolherFoto;

  @override
  State<SecaoContestacaoMaterial> createState() => _SecaoContestacaoMaterialState();
}

class _SecaoContestacaoMaterialState extends State<SecaoContestacaoMaterial> {
  List<ContestacaoMaterial>? _itens;
  var _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final itens = await widget.servico.listarContestacoes(widget.pedidoId);
      if (!mounted) return;
      setState(() {
        _itens = itens;
        _carregando = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = mensagemErroTrato(e);
        _carregando = false;
      });
    }
  }

  Future<void> _contestar() async {
    final messenger = ScaffoldMessenger.of(context);
    final criada = await Navigator.of(context).push(
      MaterialPageRoute<ContestacaoMaterial>(
        builder: (_) => ContestarMaterialTela(
          servico: widget.servico,
          pedidoId: widget.pedidoId,
          notas: widget.notas,
          escolherFoto: widget.escolherFoto,
        ),
      ),
    );
    if (criada == null || !mounted) return;
    final jaExistia = criada.id.isNotEmpty && (_itens?.any((c) => c.id == criada.id) ?? false);
    final protocolo = criada.protocolo.isEmpty ? '' : ' Protocolo ${criada.protocolo}.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${jaExistia ? 'Essa contestação já estava aberta.' : 'Contestação enviada.'}$protocolo',
        ),
      ),
    );
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpoPequeno.copyWith(color: c.texto);
    final itens = _itens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: EspacosTrato.x5),
        Text(
          'Contestação de material',
          style: TipografiaTrato.tituloCartao.copyWith(color: c.texto),
        ),
        const SizedBox(height: EspacosTrato.x2),
        if (_carregando)
          Semantics(
            label: 'Carregando contestações',
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (_erro != null) ...[
          Text(_erro!, style: corpo.copyWith(color: c.vermelhoTexto)),
          const SizedBox(height: EspacosTrato.x2),
          BotaoSecundario(
            key: const ValueKey('recarregar-contestacoes-material'),
            texto: 'Tentar de novo',
            aoTocar: _carregar,
          ),
        ] else if (itens == null)
          Text(_semFuncao, style: corpo)
        else ...[
          Text(
            'Conteste um material não comprovado ou diferente do combinado. O Trato analisa; '
            'enviar a contestação não garante o resultado.',
            style: corpo,
          ),
          const SizedBox(height: EspacosTrato.x3),
          if (itens.isEmpty) Text('Nenhuma contestação neste pedido.', style: corpo),
          for (final item in itens) ...[
            _CartaoContestacao(item, widget.notas),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (widget.notas.any((n) => n.id != null))
            BotaoSecundario(
              key: const ValueKey('botao-contestar-material'),
              texto: 'Contestar material',
              aoTocar: _contestar,
            )
          else
            Text(_semFuncao, style: corpo),
        ],
      ],
    );
  }
}

class _CartaoContestacao extends StatelessWidget {
  const _CartaoContestacao(this.item, this.notas);

  final ContestacaoMaterial item;
  final List<NotaMaterial> notas;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpoPequeno.copyWith(color: c.texto);
    final forte = corpo.copyWith(fontWeight: FontWeight.w600);
    final (situacao, tipo) = _situacao(item.status);
    final valor = item.valorContestadoCentavos;
    final reconhecido = item.valorReconhecidoCentavos;
    return CartaoTrato(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChipStatus(texto: situacao, tipo: tipo),
            const SizedBox(height: EspacosTrato.x2),
            Text(_alvo(item, notas), style: forte),
            Text(motivosContestacaoMaterial[item.motivo] ?? 'Motivo não informado', style: corpo),
            SelectableText(
              'Protocolo: ${item.protocolo.isEmpty ? 'não informado' : item.protocolo}',
              style: corpo,
            ),
            if (valor != null) Text('Valor contestado: ${formatarReais(valor)}', style: corpo),
            if (item.abertaEm != null)
              Text('Enviada em ${formatarData(item.abertaEm!)}', style: corpo),
            if (item.responderAte != null && item.decididaEm == null)
              Text('Prazo para resposta: até ${formatarData(item.responderAte!)}', style: corpo),
            if (item.descricao.isNotEmpty) Text(item.descricao, style: corpo),
            if (item.quantidadeDeAnexos > 0)
              Text('Fotos enviadas: ${item.quantidadeDeAnexos}', style: corpo),
            if (item.decididaEm != null || item.resposta != null) ...[
              const SizedBox(height: EspacosTrato.x2),
              Text(
                item.decididaEm == null
                    ? 'Resposta'
                    : 'Resposta em ${formatarData(item.decididaEm!)}',
                style: forte,
              ),
              if (item.resposta != null) Text(item.resposta!, style: corpo),
            ],
            if (reconhecido != null) ...[
              Text('Valor reconhecido na análise: ${formatarReais(reconhecido)}', style: corpo),
              Text(
                'É o resultado da análise, não um comprovante de pagamento.',
                style: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Formulário. Fecha devolvendo a contestação que o servidor registrou.
class ContestarMaterialTela extends StatefulWidget {
  const ContestarMaterialTela({
    super.key,
    required this.servico,
    required this.pedidoId,
    required this.notas,
    this.escolherFoto,
  });

  final ServicoContestacaoMaterial servico;
  final String pedidoId;
  final List<NotaMaterial> notas;
  final Future<ProvaEscolhida?> Function()? escolherFoto;

  @override
  State<ContestarMaterialTela> createState() => _ContestarMaterialTelaState();
}

class _ContestarMaterialTelaState extends State<ContestarMaterialTela> {
  final _descricao = TextEditingController();
  final _valor = TextEditingController();
  final _arquivos = <ProvaEscolhida>[];
  String? _notaId;
  String? _itemId;
  String? _motivo;
  var _enviando = false;
  String? _erro;
  String? _erroFoto;
  int? _fotoComErro;

  @override
  void dispose() {
    _descricao.dispose();
    _valor.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    setState(() => _erroFoto = null);
    try {
      final foto = await widget.escolherFoto!();
      if (foto == null || !mounted) return;
      setState(() => _arquivos.add(foto));
    } on Object catch (e) {
      if (mounted) setState(() => _erroFoto = mensagemErroTrato(e));
    }
  }

  Future<void> _enviar() async {
    final descricao = _descricao.text.trim();
    final valor = Dinheiro.lerCentavos(_valor.text);
    final falta = _notaId == null
        ? 'Escolha a nota inteira ou um item.'
        : _motivo == null
            ? 'Escolha o motivo.'
            : valor == null || valor < 1
                ? 'Informe o valor contestado em reais, por exemplo 25,50.'
                : descricao.length < minimoDaDescricaoDoMaterial
                    ? 'Descreva com pelo menos $minimoDaDescricaoDoMaterial caracteres.'
                    : null;
    setState(() {
      _erro = falta;
      _erroFoto = null;
      _fotoComErro = null;
    });
    if (falta != null) return;
    setState(() => _enviando = true);
    try {
      final criada = await widget.servico.contestarMaterial(
        widget.pedidoId,
        _notaId!,
        itemId: _itemId,
        motivo: _motivo!,
        descricao: descricao,
        valorCentavos: valor!,
        arquivos: _arquivos,
      );
      if (mounted) Navigator.of(context).pop(criada);
    } on ErroDeArquivo catch (e) {
      if (!mounted) return;
      setState(() {
        _fotoComErro = e.indice;
        _erroFoto = e.mensagem;
        _enviando = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is ErroTrato && e.codigoHttp == 503 ? _semFuncao : mensagemErroTrato(e);
        _enviando = false;
      });
    }
  }

  Widget _opcao(String chave, String texto, bool marcada, VoidCallback aoTocar) {
    final c = context.cores;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: marcada,
      child: ListTile(
        key: ValueKey(chave),
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: c.petroleo,
        ),
        title: Text(texto, style: TipografiaTrato.corpo.copyWith(color: c.texto)),
        onTap: _enviando
            ? null
            : () => setState(() {
                  _erro = null;
                  aoTocar();
                }),
      ),
    );
  }

  /// Uma opção por nota inteira e por item com identificador do servidor.
  List<Widget> _alvos() {
    final varias = widget.notas.length > 1;
    return [
      for (final (k, nota) in widget.notas.indexed)
        if (nota.id != null) ...[
          _opcao(
            'alvo-${nota.id}',
            varias ? 'Nota ${k + 1} inteira' : 'Nota inteira',
            _notaId == nota.id && _itemId == null,
            () {
              _notaId = nota.id;
              _itemId = null;
            },
          ),
          for (final item in nota.itens)
            if (item.id != null)
              _opcao(
                'alvo-${nota.id}-${item.id}',
                '${varias ? 'Nota ${k + 1} · ' : ''}${item.descricao} '
                    '(${formatarReais(item.centavos)})',
                _notaId == nota.id && _itemId == item.id,
                () {
                  _notaId = nota.id;
                  _itemId = item.id;
                },
              ),
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final titulo = TipografiaTrato.corpoForte.copyWith(color: c.texto);
    final erroTexto = TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto);
    final podeFotografar = widget.servico.podeAnexar && widget.escolherFoto != null;
    return MolduraTelaComum(
      titulo: 'Contestar material',
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('O que você contesta?', style: titulo),
            ..._alvos(),
            const SizedBox(height: EspacosTrato.x4),
            Text('Motivo', style: titulo),
            for (final m in motivosContestacaoMaterial.entries)
              _opcao('motivo-${m.key}', m.value, _motivo == m.key, () => _motivo = m.key),
            const SizedBox(height: EspacosTrato.x4),
            CampoTrato(
              key: const ValueKey('valor-contestado'),
              rotulo: 'Valor contestado',
              prefixo: r'R$ ',
              controlador: _valor,
              teclado: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: EspacosTrato.x4),
            Text('O que aconteceu?', style: titulo),
            const SizedBox(height: EspacosTrato.x2),
            TextField(
              key: const ValueKey('descricao-contestacao-material'),
              controller: _descricao,
              enabled: !_enviando,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(hintText: 'Explique o problema'),
            ),
            if (podeFotografar) ...[
              const SizedBox(height: EspacosTrato.x2),
              Text('Fotos (opcional, até $maximoDeAnexosDoMaterial)', style: titulo),
              for (final (i, a) in _arquivos.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Foto ${i + 1} · ${tamanhoLegivel(a.bytes.length)}'),
                  subtitle: _fotoComErro == i ? Text(_erroFoto ?? '', style: erroTexto) : null,
                  trailing: IconButton(
                    tooltip: 'Remover foto ${i + 1}',
                    icon: const Icon(Icons.close),
                    onPressed: _enviando
                        ? null
                        : () => setState(() {
                              _arquivos.removeAt(i);
                              _fotoComErro = null;
                              _erroFoto = null;
                            }),
                  ),
                ),
              if (_erroFoto != null && _fotoComErro == null) Text(_erroFoto!, style: erroTexto),
              if (_arquivos.length < maximoDeAnexosDoMaterial)
                BotaoSecundario(
                  key: const ValueKey('adicionar-foto-material'),
                  texto: 'Tirar foto',
                  icone: Icons.add_a_photo_outlined,
                  aoTocar: _enviando ? null : _adicionar,
                ),
            ],
            const SizedBox(height: EspacosTrato.x4),
            if (_erro != null) ...[
              Semantics(
                liveRegion: true,
                child:
                    Text(_erro!, key: const ValueKey('erro-contestar-material'), style: erroTexto),
              ),
              const SizedBox(height: EspacosTrato.x3),
            ],
            BotaoPrimario(
              key: const ValueKey('botao-enviar-contestacao-material'),
              texto: 'Enviar contestação',
              carregando: _enviando,
              aoTocar: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
