import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Cache em memória de imagens capturadas/enviadas (ex.: `upload_id` -> bytes JPEG ou caminho),
/// permitindo que o preview e a miniatura funcionem mesmo quando o serviço devolve um id do backend.
final Map<String, Uint8List> _bytesPorReferencia = {};
final Map<String, String> _caminhoPorReferencia = {};

/// Registra os bytes ou caminho local associados a uma [referencia] (ex.: `upload_id` ou `arquivoId`).
void registrarImagemEmMemoria(String referencia, {Uint8List? bytes, String? caminhoLocal}) {
  if (referencia.isEmpty) return;
  if (bytes != null && bytes.isNotEmpty) {
    _bytesPorReferencia[referencia] = bytes;
  }
  if (caminhoLocal != null && caminhoLocal.isNotEmpty) {
    _caminhoPorReferencia[referencia] = caminhoLocal;
  }
}

/// Obtém os bytes da imagem em memória associada a [referencia], se disponível.
Uint8List? obterBytesImagem(String? referencia) {
  if (referencia == null || referencia.isEmpty) return null;
  return _bytesPorReferencia[referencia];
}

/// Obtém o caminho local da imagem associada a [referencia], se disponível.
String? obterCaminhoImagem(String? referencia) {
  if (referencia == null || referencia.isEmpty) return null;
  return _caminhoPorReferencia[referencia];
}

/// Verifica se [referencia] aponta para um arquivo de imagem existente no dispositivo ou em memória.
bool temArquivoImagem(String? referencia) {
  if (referencia == null || referencia.isEmpty) return false;
  if (_bytesPorReferencia.containsKey(referencia)) return true;
  final caminhoMapeado = _caminhoPorReferencia[referencia];
  if (caminhoMapeado != null && temArquivoImagem(caminhoMapeado)) return true;
  if (referencia.startsWith('[') ||
      referencia.startsWith('fake://') ||
      referencia.startsWith('http://') ||
      referencia.startsWith('https://')) {
    return false;
  }
  try {
    return File(referencia).existsSync();
  } on Object {
    return false;
  }
}

/// Verifica se [referencia] é uma URL HTTP/HTTPS.
bool ehUrlImagem(String? referencia) {
  if (referencia == null) return false;
  return referencia.startsWith('http://') || referencia.startsWith('https://');
}

/// Constrói um widget [Image] se [referencia] for um arquivo local real, bytes em memória ou URL;
/// caso contrário, devolve null.
Widget? construirImagemReal(String? referencia, {BoxFit fit = BoxFit.cover}) {
  if (referencia == null || referencia.isEmpty) return null;
  final bytes = _bytesPorReferencia[referencia];
  if (bytes != null) {
    return Image.memory(
      bytes,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  final caminhoMapeado = _caminhoPorReferencia[referencia];
  if (caminhoMapeado != null && caminhoMapeado != referencia) {
    final img = construirImagemReal(caminhoMapeado, fit: fit);
    if (img != null) return img;
  }
  if (ehUrlImagem(referencia)) {
    return Image.network(
      referencia,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  if (temArquivoImagem(referencia)) {
    return Image.file(
      File(referencia),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  return null;
}

/// Legenda amigável para exibição (evita mostrar caminhos completos de arquivos locais).
String rotuloAmigavelFoto(String texto) {
  if (temArquivoImagem(texto) || ehUrlImagem(texto) || texto.startsWith('fake://')) {
    return 'Foto anexada';
  }
  return texto;
}

/// Detector de toque leve por ponteiro para abrir o preview da imagem sem interferir em
/// varreduras de botões de navegação, funcionando também dentro de listas roláveis.
class ToquePreviewImagem extends StatefulWidget {
  const ToquePreviewImagem({
    super.key,
    required this.referencia,
    this.legenda,
    required this.child,
  });

  final String referencia;
  final String? legenda;
  final Widget child;

  @override
  State<ToquePreviewImagem> createState() => _ToquePreviewImagemState();
}

class _ToquePreviewImagemState extends State<ToquePreviewImagem> {
  Offset? _inicio;
  DateTime? _instante;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _inicio = e.position;
        _instante = DateTime.now();
      },
      onPointerUp: (e) {
        final pos = _inicio;
        final t0 = _instante;
        _inicio = null;
        _instante = null;
        final duracaoMs = t0 == null ? 0 : DateTime.now().difference(t0).inMilliseconds;
        if (pos != null && (e.position - pos).distance < 32 && duracaoMs < 700) {
          abrirPreviewImagem(
            context,
            referencia: widget.referencia,
            legenda: widget.legenda ?? rotuloAmigavelFoto(widget.referencia),
          );
        }
      },
      child: widget.child,
    );
  }
}

/// Abre o visualizador de imagem em tela cheia com suporte a zoom (pinça).
Future<void> abrirPreviewImagem(
  BuildContext context, {
  required String referencia,
  String? legenda,
}) {
  final titulo = legenda ?? rotuloAmigavelFoto(referencia);
  final imagemReal = construirImagemReal(referencia, fit: BoxFit.contain);
  return showDialog<void>(
    context: context,
    barrierColor: CoresTrato.fundoModalFoto,
    builder: (dialogo) => Dialog.fullscreen(
      backgroundColor: CoresTrato.fundoFotoPreto,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EspacosTrato.x4,
                vertical: EspacosTrato.x2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TipografiaTrato.tituloCartao.copyWith(color: CoresTrato.creme),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar visualização',
                    onPressed: () => Navigator.of(dialogo).pop(),
                    icon: const Icon(Icons.close, color: CoresTrato.creme),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(EspacosTrato.x4),
                    child: imagemReal ?? _IlustracaoPreviewDemo(titulo: titulo),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _IlustracaoPreviewDemo extends StatelessWidget {
  const _IlustracaoPreviewDemo({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    final limpo = titulo.replaceAll('[', '').replaceAll(']', '');
    final ehNota = limpo.toLowerCase().contains('nota');
    final ehAntes = limpo.toLowerCase().contains('antes');
    final ehDepois = limpo.toLowerCase().contains('depois');
    final icone = ehNota
        ? Icons.receipt_long_outlined
        : ehAntes
            ? Icons.build_circle_outlined
            : ehDepois
                ? Icons.verified_outlined
                : Icons.photo_outlined;

    return Container(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
      width: double.infinity,
      padding: const EdgeInsets.all(EspacosTrato.x6),
      decoration: BoxDecoration(
        color: CoresTrato.azulClaro,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
        border: Border.all(color: CoresTrato.borda, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: CoresTrato.superficie,
              shape: BoxShape.circle,
            ),
            child: Icon(icone, size: 48, color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x5),
          Text(
            limpo.isEmpty ? 'Imagem do serviço' : limpo,
            textAlign: TextAlign.center,
            style: TipografiaTrato.titulo.copyWith(color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            'Registro fotográfico anexado ao pedido no Trato.',
            textAlign: TextAlign.center,
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
        ],
      ),
    );
  }
}

