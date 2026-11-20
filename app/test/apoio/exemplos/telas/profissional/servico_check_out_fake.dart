import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';

/// PROVISÓRIO — SÓ PARA TESTE E DEMONSTRAÇÃO.
class ServicoCheckOutFake implements ServicoCheckOut {
  ServicoCheckOutFake({this.codigoCerto = '7310', this.offline = false});

  final String codigoCerto;
  final bool offline;
  final List<String> codigosEnviados = [];
  final List<String> justificativasSemCodigo = [];
  bool localizou = false;

  @override
  Future<FotoChegada?> tirarFotoFinal() async => const FotoChegada(hora: '16h40');

  @override
  Future<int?> localizar() async {
    localizou = true;
    return 20;
  }

  @override
  Future<ResultadoFim> finalizar(
    String codigo, {
    bool semCodigo = false,
    String? justificativa,
  }) async {
    if (semCodigo) {
      justificativasSemCodigo.add(justificativa ?? '');
      return offline ? ResultadoFim.guardadoOffline : ResultadoFim.concluido;
    }
    codigosEnviados.add(codigo);
    if (offline) return ResultadoFim.guardadoOffline;
    return codigo == codigoCerto ? ResultadoFim.concluido : ResultadoFim.codigoIncorreto;
  }
}
