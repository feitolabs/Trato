import 'dart:math' as math;

class PosicaoAtual {
  const PosicaoAtual({
    required this.latitude,
    required this.longitude,
    required this.precisaoMetros,
  });

  final double latitude;
  final double longitude;

  /// Raio de incerteza informado pelo GPS.
  final double precisaoMetros;
}

enum FalhaLocalizacao {
  /// O GPS (serviço de localização) está desligado no aparelho.
  gpsDesligado,
  semPermissao,
  semSinal,
}

class ErroLocalizacao implements Exception {
  const ErroLocalizacao(this.falha);

  final FalhaLocalizacao falha;

  @override
  String toString() => 'ErroLocalizacao($falha)';
}

/// Localização do aparelho. A permissão é pedida antes, por [garantirPermissao].
abstract interface class ServicoLocalizacao {
  /// Posição atual com precisão. Lança [ErroLocalizacao].
  Future<PosicaoAtual> posicaoAtual();

  /// Distância em metros até um ponto (o endereço liberado). Só informativa para a tela:
  /// quem decide se a pessoa está no local é o backend.
  int distanciaAteMetros(PosicaoAtual de, {required double latitude, required double longitude});
}

/// Distância entre dois pontos (fórmula de haversine), em metros.
double distanciaEmMetros(double lat1, double lon1, double lat2, double lon2) {
  const raioTerra = 6371000.0;
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * raioTerra * math.asin(math.sqrt(a));
}

