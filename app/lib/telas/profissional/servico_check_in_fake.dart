import 'servico_check_in.dart';

/// PROVISÓRIO — SÓ PARA TESTE E DEMONSTRAÇÃO. Não acessa câmera, GPS nem backend.
/// A conferência do código de início é do backend; aqui [codigoCerto] é um valor de teste.
class ServicoCheckInFake implements ServicoCheckIn {
  ServicoCheckInFake({this.codigoCerto = '4821'});

  final String codigoCerto;
  final List<String> mensagens = [];
  final List<String> codigosEnviados = [];
  bool clienteAusenteAvisado = false;

  @override
  Future<FotoChegada?> tirarFoto() async => const FotoChegada(hora: '14h06');

  @override
  Future<int?> localizar() async => 20;

  @override
  Future<void> enviarMensagemRapida(String mensagem) async =>
      mensagens.add(mensagem);

  @override
  Future<void> avisarClienteAusente() async => clienteAusenteAvisado = true;

  @override
  Future<ResultadoInicio> iniciarServico(String codigo) async {
    codigosEnviados.add(codigo);
    return codigo == codigoCerto
        ? ResultadoInicio.iniciado
        : ResultadoInicio.codigoIncorreto;
  }
}
