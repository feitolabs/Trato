/// Termos 5.3: confirmado o pagamento, o cliente baixa o comprovante e a cópia dos Termos.
/// Quem diz se já pode, e quais Termos valiam, é o servidor.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';

const textoSemCopiaDosTermos = 'A cópia dos Termos desta contratação não está disponível no '
    'aplicativo. Peça ao atendimento.';

enum DocumentoContratacao {
  comprovante('comprovante', 'Comprovante'),
  termos('termos', 'Cópia dos Termos');

  const DocumentoContratacao(this.arquivo, this.rotulo);

  /// Nome do PDF na rota e no arquivo salvo.
  final String arquivo;
  final String rotulo;
}

class ContratacaoDoPedido {
  const ContratacaoDoPedido({required this.termosDisponiveis});

  /// Falso também quando o servidor não informa: sem certeza, o download não aparece.
  final bool termosDisponiveis;

  /// Nulo: a resposta não confirma a contratação.
  static ContratacaoDoPedido? deJson(Object? json) {
    if (json is! Map) return null;
    if (json['confirmada_em'] == null && json['comprovante_url'] == null) return null;
    return ContratacaoDoPedido(termosDisponiveis: json['termos_disponiveis'] == true);
  }
}

abstract interface class ServicoContratacao {
  /// Nulo: não há documentos para mostrar (antes do pagamento, sem acesso ou servidor antigo).
  Future<ContratacaoDoPedido?> contratacao(String pedidoId);

  Future<List<int>> baixarDocumentoContratacao(String pedidoId, DocumentoContratacao documento);
}

class SecaoDocumentosContratacao extends StatefulWidget {
  const SecaoDocumentosContratacao({
    super.key,
    required this.carregar,
    required this.baixar,
    this.atualizarQuando,
  });

  final Future<ContratacaoDoPedido?> Function() carregar;

  /// Baixa e salva o PDF; lança se falhar (a mensagem fica junto do botão).
  final Future<void> Function(DocumentoContratacao documento) baixar;
  final Listenable? atualizarQuando;

  @override
  State<SecaoDocumentosContratacao> createState() => _SecaoDocumentosContratacaoState();
}

class _SecaoDocumentosContratacaoState extends State<SecaoDocumentosContratacao> {
  ContratacaoDoPedido? _dados;
  var _carregando = true;
  String? _erro;
  final _baixando = <DocumentoContratacao>{};
  final _errosDeDownload = <DocumentoContratacao, String>{};

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_atualizar);
    _carregar();
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_atualizar);
    super.dispose();
  }

  void _atualizar() {
    if (_dados == null && !_carregando) _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await widget.carregar();
      if (!mounted) return;
      setState(() {
        _dados = dados;
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

  Future<void> _baixar(DocumentoContratacao documento) async {
    if (_baixando.contains(documento)) return;
    setState(() {
      _baixando.add(documento);
      _errosDeDownload.remove(documento);
    });
    String? erro;
    try {
      await widget.baixar(documento);
    } on ErroTrato catch (e) {
      erro = e.mensagem;
    } on Object {
      erro = 'Não foi possível baixar agora. Tente de novo.';
    }
    if (!mounted) return;
    setState(() {
      _baixando.remove(documento);
      if (erro != null) _errosDeDownload[documento] = erro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final dados = _dados;
    if (!_carregando && _erro == null && dados == null) return const SizedBox.shrink();
    final erroTexto = TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto);
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Documentos da contratação', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x3),
            if (_carregando)
              Semantics(
                label: 'Carregando documentos',
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (dados == null) ...[
              Text(_erro!, style: erroTexto),
              const SizedBox(height: EspacosTrato.x2),
              BotaoSecundario(
                key: const ValueKey('recarregar-contratacao'),
                texto: 'Tentar de novo',
                aoTocar: _carregar,
              ),
            ] else ...[
              for (final documento in DocumentoContratacao.values)
                if (documento == DocumentoContratacao.comprovante || dados.termosDisponiveis) ...[
                  BotaoSecundario(
                    key: ValueKey('contratacao-${documento.arquivo}'),
                    texto: _baixando.contains(documento) ? 'Baixando...' : documento.rotulo,
                    icone: Icons.picture_as_pdf_outlined,
                    aoTocar: _baixando.contains(documento) ? null : () => _baixar(documento),
                  ),
                  if (_errosDeDownload[documento] case final erro?) ...[
                    const SizedBox(height: EspacosTrato.x1),
                    Semantics(liveRegion: true, child: Text(erro, style: erroTexto)),
                  ],
                  const SizedBox(height: EspacosTrato.x2),
                ],
              if (!dados.termosDisponiveis)
                Text(
                  textoSemCopiaDosTermos,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
