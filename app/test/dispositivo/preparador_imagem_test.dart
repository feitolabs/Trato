import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:trato/dispositivo/preparador_imagem.dart';
import 'package:trato/dispositivo/servico_localizacao.dart';

Uint8List _jpegComGps({int largura = 40, int altura = 30}) {
  final imagem = img.Image(width: largura, height: altura);
  img.fill(imagem, color: img.ColorRgb8(200, 80, 40));
  imagem.exif.gpsIfd.data[0x0001] = img.IfdValueAscii('S'); // GPSLatitudeRef
  imagem.exif.gpsIfd.data[0x0002] = img.IfdValueRational(23, 1);
  imagem.exif.imageIfd.data[0x010F] = img.IfdValueAscii('MarcaFalsa');
  return Uint8List.fromList(img.encodeJpg(imagem));
}

void main() {
  group('PreparadorImagem', () {
    final capturada = DateTime.utc(2026, 10, 29, 17);

    test('o arquivo de teste realmente traz GPS no EXIF', () {
      final original = img.decodeJpg(_jpegComGps())!;
      expect(original.exif.gpsIfd.isEmpty, isFalse);
    });

    test('remove o EXIF, inclusive a localização', () {
      final pronto = const PreparadorImagem().preparar(_jpegComGps(), capturadaEm: capturada);

      final saida = img.decodeJpg(pronto.bytes)!;
      expect(saida.exif.gpsIfd.isEmpty, isTrue);
      expect(saida.exif.imageIfd.data.containsKey(0x010F), isFalse);
      expect(pronto.mime, 'image/jpeg');
      expect(pronto.capturadaEm, capturada);
    });

    test('reduz o lado maior ao limite e mantém a proporção', () {
      final pronto = const PreparadorImagem(ladoMaximo: 20)
          .preparar(_jpegComGps(largura: 80, altura: 40), capturadaEm: capturada);

      final saida = img.decodeJpg(pronto.bytes)!;
      expect(saida.width, 20);
      expect(saida.height, 10);
    });

    test('não aumenta imagem pequena', () {
      final pronto =
          const PreparadorImagem(ladoMaximo: 1600).preparar(_jpegComGps(), capturadaEm: capturada);

      final saida = img.decodeJpg(pronto.bytes)!;
      expect((saida.width, saida.height), (40, 30));
    });

    test('o SHA-256 é do arquivo que será enviado', () {
      final pronto = const PreparadorImagem().preparar(_jpegComGps(), capturadaEm: capturada);

      expect(pronto.sha256, sha256Hex(pronto.bytes));
      expect(pronto.sha256, hasLength(64));
    });

    test('bytes que não são imagem viram FormatException', () {
      expect(
        () => const PreparadorImagem()
            .preparar(Uint8List.fromList([1, 2, 3]), capturadaEm: capturada),
        throwsFormatException,
      );
    });
  });

  group('sha256Hex', () {
    test('vetores conhecidos', () {
      expect(
        sha256Hex(const []),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256Hex('abc'.codeUnits),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('distanciaEmMetros', () {
    test('mesmo ponto é zero', () {
      expect(distanciaEmMetros(-23.5, -46.6, -23.5, -46.6), 0);
    });

    test('0,001 grau de latitude vale cerca de 111 m', () {
      expect(distanciaEmMetros(-23.5, -46.6, -23.499, -46.6), closeTo(111.2, 0.5));
    });
  });
}
