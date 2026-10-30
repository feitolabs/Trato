import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'servico_localizacao.dart';

class ServicoLocalizacaoReal implements ServicoLocalizacao {
  const ServicoLocalizacaoReal({this.tempoLimite = const Duration(seconds: 20)});

  final Duration tempoLimite;

  @override
  Future<PosicaoAtual> posicaoAtual() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ErroLocalizacao(FalhaLocalizacao.gpsDesligado);
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: tempoLimite),
      );
      return PosicaoAtual(latitude: p.latitude, longitude: p.longitude, precisaoMetros: p.accuracy);
    } on TimeoutException {
      throw const ErroLocalizacao(FalhaLocalizacao.semSinal);
    } on PermissionDeniedException {
      throw const ErroLocalizacao(FalhaLocalizacao.semPermissao);
    } on LocationServiceDisabledException {
      throw const ErroLocalizacao(FalhaLocalizacao.gpsDesligado);
    }
  }

  @override
  int distanciaAteMetros(PosicaoAtual de, {required double latitude, required double longitude}) =>
      distanciaEmMetros(de.latitude, de.longitude, latitude, longitude).round();
}
