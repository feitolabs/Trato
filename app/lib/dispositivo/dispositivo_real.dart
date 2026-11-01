import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../tema/tema.dart';
import 'dispositivo.dart';

/// Câmera e galeria pelo `image_picker`. Pede permissão de câmera na primeira foto;
/// sem permissão ou se a pessoa cancelar, devolve null.
class CapturaFotoCamera implements CapturaFoto {
  CapturaFotoCamera({
    ImagePicker? picker,
    this.navegador,
  }) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final GlobalKey<NavigatorState>? navegador;

  @override
  Future<String?> fotografar() async {
    try {
      final ctx = navegador?.currentContext;
      var origem = ImageSource.camera;
      if (ctx != null && ctx.mounted) {
        final escolhida = await _escolherOrigem(ctx);
        if (escolhida == null) return null;
        origem = escolhida;
      }
      if (origem == ImageSource.camera) {
        var status = await ph.Permission.camera.status;
        if (!status.isGranted && !status.isLimited) {
          status = await ph.Permission.camera.request();
        }
        if (!status.isGranted && !status.isLimited) {
          final c = navegador?.currentContext;
          if (c != null && c.mounted) {
            ScaffoldMessenger.of(c)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: const Text(
                    'Permissão de câmera necessária para tirar foto. Você também pode escolher da galeria.',
                  ),
                  action: status.isPermanentlyDenied
                      ? const SnackBarAction(
                          label: 'Ajustes',
                          onPressed: ph.openAppSettings,
                        )
                      : null,
                ),
              );
          }
          return null;
        }
      }
      final arquivo = await _picker.pickImage(
        source: origem,
        maxWidth: 1600,
        imageQuality: 85,
      );
      return arquivo?.path;
    } on Object {
      return null;
    }
  }

  Future<ImageSource?> _escolherOrigem(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EspacosTrato.x4,
                EspacosTrato.x4,
                EspacosTrato.x4,
                EspacosTrato.x2,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Adicionar imagem', style: TipografiaTrato.titulo),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: CoresTrato.petroleo),
              title: const Text('Tirar foto com a câmera'),
              onTap: () => Navigator.of(folha).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: CoresTrato.petroleo),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(folha).pop(ImageSource.gallery),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
        ),
      ),
    );
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

DispositivoTrato dispositivoReal({GlobalKey<NavigatorState>? navegador}) =>
    DispositivoTrato(
      camera: CapturaFotoCamera(navegador: navegador),
      localizador: const LocalizadorGps(),
    );
