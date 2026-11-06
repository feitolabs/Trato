import 'dart:typed_data';
import 'package:trato/dispositivo/servico_camera.dart';

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
