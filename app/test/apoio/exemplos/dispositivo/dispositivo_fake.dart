import 'dart:async';
import 'package:trato/dispositivo/dispositivo.dart';

/// PROVISÓRIO — só teste e demonstração.
class CapturaFotoFake implements CapturaFoto {
  CapturaFotoFake({this.cancelar = false});

  final bool cancelar;
  int tiradas = 0;

  @override
  Future<String?> fotografar() async {
    if (cancelar) return null;
    tiradas++;
    return 'fake://foto/$tiradas';
  }

  @override
  Future<List<String>> fotografarMultiplas() async {
    final uma = await fotografar();
    return uma != null ? [uma] : const [];
  }
}

/// PROVISÓRIO — só teste e demonstração.
class LocalizadorFake implements Localizador {
  LocalizadorFake({this.posicao = const PosicaoGps(latitude: -19.92, longitude: -43.94)});

  final PosicaoGps? posicao;

  @override
  Future<PosicaoGps?> posicaoAtual() async => posicao;
}
