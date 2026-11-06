import 'dart:math' as math;
import 'package:trato/dispositivo/servico_localizacao.dart';

class ServicoLocalizacaoFake implements ServicoLocalizacao {
  ServicoLocalizacaoFake({
    this.posicao = const PosicaoAtual(latitude: -23.5, longitude: -46.6, precisaoMetros: 8),
    this.falha,
  });

  PosicaoAtual? posicao;
  FalhaLocalizacao? falha;

  @override
  Future<PosicaoAtual> posicaoAtual() async {
    if (falha != null) throw ErroLocalizacao(falha!);
    return posicao ?? (throw const ErroLocalizacao(FalhaLocalizacao.semSinal));
  }

  @override
  int distanciaAteMetros(PosicaoAtual de, {required double latitude, required double longitude}) =>
      distanciaEmMetros(de.latitude, de.longitude, latitude, longitude).round();
}
