import 'servico_check_in.dart';

enum ResultadoFim {
  concluido,

  /// O backend recusou o código de conclusão.
  codigoIncorreto,

  /// Sem internet: a prova ficou guardada e sai quando a conexão voltar.
  guardadoOffline,
}

/// Porta entre a tela de check-out (foto final + código de conclusão) e o backend.
abstract interface class ServicoCheckOut {
  Future<FotoChegada?> tirarFotoFinal();
  Future<ResultadoFim> finalizar(String codigo);
}

