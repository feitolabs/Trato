import 'dart:async';

import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';
import 'modal_sigiloso.dart';
import 'provas_modal.dart' show abrirLinkProtegido, formatoDoArquivo, tamanhoLegivel;
import 'seletor_arquivo.dart';

/// Escolher os comprovantes da retenção (Termos 7.4) entre os arquivos do pedido, ou enviar um
/// novo. Devolve id e rótulo dos escolhidos, ou null se a pessoa desistir. Os links ficam só aqui:
/// somem ao vencer, ao fechar e se a sessão cair.
Future<Map<String, String>?> abrirComprovantes(
        BuildContext context, String pedidoId, String pedido, Map<String, String> escolhidos) =>
    mostrarModal<Map<String, String>>(
      context,
      largura: 600,
      construir: (_) => _ModalComprovantes(pedidoId: pedidoId, pedido: pedido, escolhidos: escolhidos),
    );

const _fotos = ['image/jpeg', 'image/png', 'image/webp'];
const _maximoDeComprovantes = 10;

/// Teto só para o navegador não carregar um arquivo enorme; o limite que vale é o do servidor.
const _maximoLido = 25 * 1024 * 1024;

String rotuloDoComprovante(ArquivoComprovante a) =>
    '${formatoDoArquivo(a.tipoConteudo) ?? 'arquivo'} enviada em ${formatarData(a.enviadoEm)} '
        '${a.enviadoPor == 'profissional' ? 'pelo profissional' : 'pela equipe'} · ${tamanhoLegivel(a.tamanhoBytes)}';

class _ModalComprovantes extends StatefulWidget {
  const _ModalComprovantes({required this.pedidoId, required this.pedido, required this.escolhidos});
  final String pedidoId;
  final String pedido;
  final Map<String, String> escolhidos;

  @override
  State<_ModalComprovantes> createState() => _ModalComprovantesState();
}

class _ModalComprovantesState extends State<_ModalComprovantes> with SomeComASessao {
  final _motivo = TextEditingController();
  late final Map<String, String> _escolhidos = {...widget.escolhidos};
  List<ArquivoComprovante>? _arquivos;
  Timer? _validade;
  bool _ocupado = false;
  bool _venceu = false;
  String? _erro;

  /// Envio já feito que falta concluir (dá para tentar de novo sem reenviar).
  String? _envioPendente;

  static const _maximoMotivo = 500;

  bool get _motivoValido {
    final n = _motivo.text.trim().length;
    return n >= kMotivoMinimo && n <= _maximoMotivo;
  }

  @override
  void limparSigiloso() {
    _validade?.cancel();
    _arquivos = null;
  }

  @override
  void dispose() {
    limparSigiloso();
    _motivo.dispose();
    super.dispose();
  }

  bool get _vivo => mounted && context.sessao.logado;

  Future<void> _fazer(Future<void> Function() acao) async {
    if (_ocupado || !_motivoValido) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await acao();
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Os links vencem juntos, pelo menor prazo.
  void _contarValidade(List<ArquivoComprovante> lista) {
    _validade?.cancel();
    final segundos = lista.fold(300, (menor, a) => a.expiraEmSegundos < menor ? a.expiraEmSegundos : menor);
    _validade = Timer(Duration(seconds: segundos), () {
      if (mounted) {
        setState(() {
          _arquivos = null;
          _venceu = true;
        });
      }
    });
  }

  Future<void> _listar() => _fazer(() async {
        final lista = await context.api.listarComprovantes(widget.pedidoId, motivo: _motivo.text.trim());
        if (!_vivo) return;
        _contarValidade(lista);
        setState(() {
          _arquivos = lista;
          _venceu = false;
          // Some da escolha o que não está mais na lista do servidor.
          _escolhidos.removeWhere((id, _) => !lista.any((a) => a.arquivoId == id));
        });
      });

  Future<void> _enviarNovo() => _fazer(() async {
        final api = context.api;
        final a = await seletorDeArquivo(_fotos.join(','), _maximoLido);
        if (a == null || !_vivo) return;
        final problema = problemaDoArquivo(a, _fotos, maximoBytes: _maximoLido);
        if (problema != null) {
          setState(() => _erro = problema);
          return;
        }
        final motivo = _motivo.text.trim();
        setState(() => _envioPendente = null);
        final envio = await api.pedirEnvioComprovante(widget.pedidoId,
            motivo: motivo, nomeArquivo: a.nome, tipoConteudo: a.tipo, tamanhoBytes: a.tamanho);
        if (!_vivo) return;
        await api.enviarArquivo(envio.url, tipoConteudo: a.tipo, bytes: a.bytes);
        if (!_vivo) return;
        _envioPendente = envio.id;
        await _concluir();
      });

  Future<void> _concluir() async {
    final id = _envioPendente;
    if (id == null) return;
    final novo = await context.api.concluirComprovante(widget.pedidoId, id, motivo: _motivo.text.trim());
    if (!_vivo) return;
    final lista = [
      for (final a in _arquivos ?? const <ArquivoComprovante>[])
        if (a.arquivoId != novo.arquivoId) a,
      novo,
    ];
    _contarValidade(lista);
    setState(() {
      _envioPendente = null;
      _arquivos = lista;
      if (_escolhidos.length < _maximoDeComprovantes) {
        _escolhidos[novo.arquivoId] = rotuloDoComprovante(novo);
      }
    });
  }

  void _marcar(ArquivoComprovante a, bool marcar) => setState(() {
        if (!marcar) {
          _escolhidos.remove(a.arquivoId);
        } else if (_escolhidos.length < _maximoDeComprovantes) {
          _escolhidos[a.arquivoId] = rotuloDoComprovante(a);
        }
      });

  @override
  Widget build(BuildContext context) {
    final arquivos = _arquivos;
    return PopScope(
      canPop: !_ocupado,
      child: CorpoModal(
        titulo: 'Comprovantes · ${widget.pedido}',
        consequencia: 'O acesso e o envio ficam na auditoria com seu nome e o motivo. Os links valem 5 minutos. '
            'O cliente vê os comprovantes escolhidos.',
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_venceu) ...[
            const BannerInfo('Os links venceram. Liste de novo se precisar.', tom: Tom.alerta),
            const SizedBox(height: EspacosTrato.x3),
          ],
          CampoMotivo(controle: _motivo, aoMudar: () => setState(() {}), rotulo: 'Motivo do acesso'),
          Text('Até $_maximoMotivo caracteres. Não escreva dado pessoal no motivo.', style: TipografiaTrato.legenda),
          const SizedBox(height: EspacosTrato.x3),
          if (arquivos != null && arquivos.isEmpty)
            Text('Nenhum arquivo deste pedido serve de comprovante. Envie um novo.', style: TipografiaTrato.corpo),
          for (final a in arquivos ?? const <ArquivoComprovante>[])
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: ValueKey('comprovante-${a.arquivoId}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(rotuloDoComprovante(a), style: TipografiaTrato.corpo),
                subtitle: Align(
                  alignment: Alignment.centerLeft,
                  child: BotaoTrato.link('Abrir', aoPressionar: () => abrirLinkProtegido(context, a.url)),
                ),
                value: _escolhidos.containsKey(a.arquivoId),
                onChanged: _ocupado ? null : (v) => _marcar(a, v ?? false),
              ),
            ),
          const SizedBox(height: EspacosTrato.x2),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              BotaoTrato.secundario('Listar arquivos do pedido',
                  aoPressionar: _motivoValido && !_ocupado ? _listar : null),
              BotaoTrato.secundario('Enviar foto nova',
                  aoPressionar: _motivoValido && !_ocupado ? _enviarNovo : null),
              if (_envioPendente != null)
                BotaoTrato.secundario('Concluir envio',
                    aoPressionar: _motivoValido && !_ocupado ? () => _fazer(_concluir) : null),
            ],
          ),
          if (_ocupado) const LinearProgressIndicator(),
          const SizedBox(height: EspacosTrato.x2),
          Text('Escolhidos: ${_escolhidos.length} de $_maximoDeComprovantes', style: TipografiaTrato.legenda),
        ],
        acoes: [
          BotaoTrato.secundario('Cancelar', aoPressionar: _ocupado ? null : () => Navigator.of(context).pop()),
          BotaoTrato.primario(
            'Usar escolhidos',
            aoPressionar: _ocupado ? null : () => Navigator.of(context).pop(_escolhidos),
          ),
        ],
      ),
    );
  }
}
