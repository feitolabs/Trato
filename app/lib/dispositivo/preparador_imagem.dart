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

/// Há metadado no arquivo? JPEG com segmento APP1 (EXIF/XMP), APP13 (IPTC/Photoshop) ou
/// comentário; qualquer coisa que não seja JPEG também conta (PNG/HEIC/WebP carregam metadado).
bool temMetadados(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return true;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return true; // estrutura estranha: não confia
    final marcador = b[i + 1];
    if (marcador == 0xFF) {
      i++; // preenchimento
      continue;
    }
    if (marcador == 0xDA || marcador == 0xD9) return false; // início dos pixels
    if (marcador == 0xE1 || marcador == 0xED || marcador == 0xFE) return true;
    if (marcador >= 0xE2 && marcador <= 0xEF && marcador != 0xE2) return true;
    if (marcador >= 0xD0 && marcador <= 0xD8 || marcador == 0x01) {
      i += 2;
      continue;
    }
    i += 2 + ((b[i + 2] << 8) | b[i + 3]);
  }
  return false;
}

/// Última barreira antes do envio (revisão M8): se por qualquer caminho a foto chegou com
/// metadado (EXIF/GPS), recodifica aqui. O backend deve revalidar quando existir a rota de upload.
ArquivoCapturado garantirSemMetadados(ArquivoCapturado arquivo, {PreparadorImagem preparador = const PreparadorImagem()}) {
  if (!temMetadados(arquivo.bytes)) return arquivo;
  return preparador.preparar(arquivo.bytes, capturadaEm: arquivo.capturadaEm);
}
