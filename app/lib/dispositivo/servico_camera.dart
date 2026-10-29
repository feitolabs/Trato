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

/// Foto de teste: um arquivo fixo, sem tocar no aparelho.
class ServicoCameraFake implements ServicoCamera {
  ServicoCameraFake({this.cancelar = false, DateTime? agora})
      : _agora = agora ?? DateTime.utc(2026, 10, 29, 17, 6);

  /// Simula a pessoa fechando a câmera.
  bool cancelar;
  final DateTime _agora;
  int tiradas = 0;
  int daGaleria = 0;

  ArquivoCapturado _arquivo(int n) => ArquivoCapturado(
        bytes: Uint8List.fromList([0xFF, 0xD8, n, 0xFF, 0xD9]),
        sha256: 'fake-sha-$n',
        capturadaEm: _agora,
      );

  @override
  Future<ArquivoCapturado?> tirarFoto({bool frontal = false}) async =>
      cancelar ? null : _arquivo(++tiradas);

  @override
  Future<ArquivoCapturado?> escolherDaGaleria() async =>
      cancelar ? null : _arquivo(100 + ++daGaleria);
}
