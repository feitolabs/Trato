import 'repositorios_api.dart' show FotoCapturada, PosicaoCapturada;

enum TipoAcaoOffline { checkIn, checkOut }

/// Check-in ou check-out feito sem internet, à espera de envio. Guarda só o que o backend
/// precisa: a foto (arquivo local), a posição e o código digitado.
class AcaoOffline {
  const AcaoOffline({
    required this.pedidoId,
    required this.tipo,
    required this.codigo,
    required this.foto,
    this.posicao,
  });

  final String pedidoId;
  final TipoAcaoOffline tipo;
  final String codigo;
  final FotoCapturada foto;
  final PosicaoCapturada? posicao;
}

/// Fila de ações para enviar quando a internet voltar.
///
/// A implementação em memória some se o app for fechado. Persistir em disco (com a foto em
/// pasta privada do app) depende de decisão de armazenamento local; ver `docs/app-camera-gps.md`.
abstract interface class FilaOffline {
  List<AcaoOffline> get pendentes;
  void guardar(AcaoOffline acao);
  void remover(AcaoOffline acao);
}

class FilaOfflineMemoria implements FilaOffline {
  final List<AcaoOffline> _itens = [];

  @override
  List<AcaoOffline> get pendentes => List.unmodifiable(_itens);

  @override
  void guardar(AcaoOffline acao) => _itens.add(acao);

  @override
  void remover(AcaoOffline acao) => _itens.remove(acao);
}
