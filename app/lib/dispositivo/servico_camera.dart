import 'dart:typed_data';

/// Foto já pronta para envio: sem localização embutida (EXIF), comprimida e com SHA-256.
class ArquivoCapturado {
  const ArquivoCapturado({
    required this.bytes,
    required this.sha256,
    required this.capturadaEm,
    this.mime = 'image/jpeg',
  });

  final Uint8List bytes;

  /// Hexadecimal minúsculo do conteúdo que será enviado (já comprimido).
  final String sha256;

  /// Relógio do aparelho. Serve só como dica offline: a hora válida é a do servidor.
  final DateTime capturadaEm;
  final String mime;

  int get tamanho => bytes.length;
}

/// Câmera e galeria. Quem implementa devolve o arquivo já tratado; quem usa só envia.
abstract interface class ServicoCamera {
  /// Abre a câmera. Null se a pessoa cancelou. [frontal] para selfie.
  Future<ArquivoCapturado?> tirarFoto({bool frontal = false});

  /// Abre a galeria. Null se a pessoa cancelou.
  Future<ArquivoCapturado?> escolherDaGaleria();
}

