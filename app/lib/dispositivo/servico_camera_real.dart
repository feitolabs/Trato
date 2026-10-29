import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'preparador_imagem.dart';
import 'servico_camera.dart';

/// Câmera e galeria do aparelho via `image_picker`. A permissão é pedida antes, por
/// [garantirPermissao]; aqui só se captura e se trata a imagem.
class ServicoCameraReal implements ServicoCamera {
  ServicoCameraReal({ImagePicker? picker, this.preparador = const PreparadorImagem()})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final PreparadorImagem preparador;

  @override
  Future<ArquivoCapturado?> tirarFoto({bool frontal = false}) =>
      _capturar(ImageSource.camera, frontal ? CameraDevice.front : CameraDevice.rear);

  @override
  Future<ArquivoCapturado?> escolherDaGaleria() =>
      _capturar(ImageSource.gallery, CameraDevice.rear);

  Future<ArquivoCapturado?> _capturar(ImageSource origem, CameraDevice camera) async {
    final arquivo = await _picker.pickImage(source: origem, preferredCameraDevice: camera);
    if (arquivo == null) return null;
    final original = await arquivo.readAsBytes();
    final agora = DateTime.now().toUtc();
    // Decodificar e recomprimir é pesado: fora da thread da interface.
    return compute(_preparar, (preparador, original, agora));
  }
}

ArquivoCapturado _preparar((PreparadorImagem, Uint8List, DateTime) args) =>
    args.$1.preparar(args.$2, capturadaEm: args.$3);
