import 'package:trato/telas/profissional/servico_check_in.dart';
import 'package:trato/telas/profissional/servico_check_out.dart';

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
