import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../componentes/imagem_trato.dart';
import 'preparador_imagem.dart';
import 'servico_camera.dart';

/// Câmera e galeria do aparelho via `image_picker`. Solicita permissão de câmera se necessário
/// e faz fallback automático para a galeria caso a câmera seja negada ou indisponível.
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
    var fonte = origem;
    if (fonte == ImageSource.camera) {
      try {
        var status = await ph.Permission.camera.status;
        if (!status.isGranted && !status.isLimited) {
          status = await ph.Permission.camera.request();
        }
        if (!status.isGranted && !status.isLimited) {
          fonte = ImageSource.gallery;
        }
      } on Object {
        // Segue com a tentativa padrão do image_picker.
      }
    }
    XFile? arquivo;
    try {
      arquivo = await _picker.pickImage(source: fonte, preferredCameraDevice: camera);
    } on Object {
      if (fonte == ImageSource.camera) {
        arquivo = await _picker.pickImage(source: ImageSource.gallery);
      }
    }
    if (arquivo == null) return null;
    final original = await arquivo.readAsBytes();
    final agora = DateTime.now().toUtc();
    try {
      // Decodificar e recomprimir é pesado: fora da thread da interface.
      final preparado = await compute(_preparar, (preparador, original, agora));
      registrarImagemEmMemoria(
        preparado.sha256,
        bytes: preparado.bytes,
        caminhoLocal: arquivo.path,
      );
      return preparado;
    } on Object {
      // Fallback seguro se o decodificador falhar em formato específico da câmera
      final sha = sha256Hex(original);
      final fallback = ArquivoCapturado(bytes: original, sha256: sha, capturadaEm: agora);
      registrarImagemEmMemoria(sha, bytes: original, caminhoLocal: arquivo.path);
      return fallback;
    }
  }
}

ArquivoCapturado _preparar((PreparadorImagem, Uint8List, DateTime) args) =>
    args.$1.preparar(args.$2, capturadaEm: args.$3);
