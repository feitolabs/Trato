export 'package:trato/telas/pedidos/modelos.dart' show EstadoAditivo;
import 'package:trato/dados/repositorios.dart' show Cobranca, StatusPagamento;
import 'package:trato/telas/aditivo/aditivo.dart';
import 'package:trato/telas/pedidos/modelos.dart' show EstadoAditivo;

/// PROVISÓRIO — só para teste e demonstração.
class ServicoAditivoFake implements ServicoAditivo {
  ServicoAditivoFake({this.detalhe, this.falharAoCarregar = false, this.falharAoEnviar = false});

  final DetalheAditivo? detalhe;
  final bool falharAoCarregar;
  final bool falharAoEnviar;
  final List<NovoAditivo> criados = [];
  final List<(String, bool)> respostas = [];

  @override
  Future<void> criar(NovoAditivo aditivo) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    criados.add(aditivo);
  }

  @override
  Future<DetalheAditivo?> carregar(String aditivoId) async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return detalhe;
  }

  @override
  Future<Cobranca?> responder(String aditivoId, {required bool aprovar}) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    respostas.add((aditivoId, aprovar));
    return null;
  }

  @override
  Future<StatusPagamento> statusDoPagamento(String contratoId) async => StatusPagamento.aguardando;
}

const aditivoExemplo = DetalheAditivo(
  id: 'ad-1',
  pedidoTitulo: 'Troca de tomadas e chuveiro',
  profissional: 'Carlos',
  motivo: 'A fiação do chuveiro estava ressecada. Precisei trocar 6 m de cabo 6 mm.',
  valorCentavos: 4500,
);
