import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;

import 'servico_camera.dart';

/// Hexadecimal minúsculo do SHA-256.
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// Prepara a foto antes do envio: aplica a rotação, reduz o tamanho, recodifica em JPEG
/// (isso descarta todo o EXIF, inclusive a localização) e calcula o SHA-256 do resultado.
class PreparadorImagem {
  const PreparadorImagem({this.ladoMaximo = 1600, this.qualidade = 80});

  final int ladoMaximo;
  final int qualidade;

  /// Lança [FormatException] se os bytes não forem uma imagem.
  ArquivoCapturado preparar(Uint8List original, {required DateTime capturadaEm}) {
    const invalida = FormatException('Arquivo não é uma imagem válida.');
    final img.Image? decodificada;
    try {
      decodificada = img.decodeImage(original);
    } on Object {
      // Arquivo truncado ou corrompido faz o decodificador falhar de várias formas.
      throw invalida;
    }
    if (decodificada == null) throw invalida;
    var imagem = img.bakeOrientation(decodificada);
    final maior = imagem.width > imagem.height ? imagem.width : imagem.height;
    if (maior > ladoMaximo) {
      imagem = imagem.width >= imagem.height
          ? img.copyResize(imagem, width: ladoMaximo)
          : img.copyResize(imagem, height: ladoMaximo);
    }
    // Garantia extra: nenhum metadado segue junto, mesmo que o encoder mude.
    imagem.exif = img.ExifData();
    final bytes = Uint8List.fromList(img.encodeJpg(imagem, quality: qualidade));
    return ArquivoCapturado(bytes: bytes, sha256: sha256Hex(bytes), capturadaEm: capturadaEm);
  }
}
