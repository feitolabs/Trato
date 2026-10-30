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

/// PROVISÓRIO — SÓ PARA TESTE E DEMONSTRAÇÃO.
class ServicoCheckOutFake implements ServicoCheckOut {
  ServicoCheckOutFake({this.codigoCerto = '7310', this.offline = false});

  final String codigoCerto;
  final bool offline;
  final List<String> codigosEnviados = [];

  @override
  Future<FotoChegada?> tirarFotoFinal() async => const FotoChegada(hora: '16h40');

  @override
  Future<ResultadoFim> finalizar(String codigo) async {
    codigosEnviados.add(codigo);
    if (offline) return ResultadoFim.guardadoOffline;
    return codigo == codigoCerto ? ResultadoFim.concluido : ResultadoFim.codigoIncorreto;
  }
}
