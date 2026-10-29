import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'dispositivo.dart';

/// Câmera pelo `image_picker`. Pede a permissão na primeira foto; sem permissão devolve null.
class CapturaFotoCamera implements CapturaFoto {
  CapturaFotoCamera({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> fotografar() async {
    try {
      final arquivo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      return arquivo?.path;
    } on Object {
      return null;
    }
  }
}

/// GPS pelo `geolocator`. Pede a permissão ao usar; sem permissão ou GPS desligado, null.
class LocalizadorGps implements Localizador {
  const LocalizadorGps();

  @override
  Future<PosicaoGps?> posicaoAtual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      if (permissao == LocationPermission.denied ||
          permissao == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return PosicaoGps(latitude: p.latitude, longitude: p.longitude);
    } on Object {
      return null;
    }
  }
}

DispositivoTrato dispositivoReal() =>
    DispositivoTrato(camera: CapturaFotoCamera(), localizador: const LocalizadorGps());
