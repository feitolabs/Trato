import 'dart:async';

/// Ponto GPS capturado no aparelho. Só coordenadas: quem confere proximidade é o backend.
class PosicaoGps {
  const PosicaoGps({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Câmera. Devolve a referência do arquivo local, ou null se a pessoa cancelou ou negou a
/// permissão. As telas nunca conhecem o plugin.
abstract interface class CapturaFoto {
  Future<String?> fotografar();
}

/// Localização. Null se negada, desligada ou sem sinal.
abstract interface class Localizador {
  Future<PosicaoGps?> posicaoAtual();
}

/// Envio do arquivo capturado. O upload será por URL assinada do backend (rota ainda não
/// existe, ver docs/STATUS-MVP.md): quando existir, basta uma implementação nova desta interface.
abstract interface class EnvioMidia {
  /// Recebe a referência local e devolve a referência que vai para o backend.
  Future<String> enviar(String referenciaLocal);
}

/// Enquanto não há rota de upload: a referência local segue como está. Não sobe nada.
class EnvioMidiaSemRota implements EnvioMidia {
  const EnvioMidiaSemRota();

  @override
  Future<String> enviar(String referenciaLocal) async => referenciaLocal;
}

/// Os três juntos, como o `rotas.dart` os usa.
class DispositivoTrato {
  const DispositivoTrato({
    required this.camera,
    required this.localizador,
    this.envio = const EnvioMidiaSemRota(),
  });

  /// Sem aparelho de verdade: referências e posição de teste. Padrão até o `main` trocar.
  factory DispositivoTrato.fake() =>
      DispositivoTrato(camera: CapturaFotoFake(), localizador: LocalizadorFake());

  final CapturaFoto camera;
  final Localizador localizador;
  final EnvioMidia envio;

  /// Tira a foto e a prepara para o backend. Null se cancelada.
  Future<String?> fotografarEEnviar() async {
    final local = await camera.fotografar();
    if (local == null) return null;
    return envio.enviar(local);
  }
}

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
}

/// PROVISÓRIO — só teste e demonstração.
class LocalizadorFake implements Localizador {
  LocalizadorFake({this.posicao = const PosicaoGps(latitude: -19.92, longitude: -43.94)});

  final PosicaoGps? posicao;

  @override
  Future<PosicaoGps?> posicaoAtual() async => posicao;
}
