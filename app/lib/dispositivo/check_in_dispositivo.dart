import '../telas/profissional/servico_check_in.dart';
import 'dispositivo.dart';

/// Check-in com câmera e GPS reais; o resto (mensagem rápida, cliente ausente, código de início)
/// segue no [base]. O app só captura: a prova de chegada é conferida pelo backend.
class ServicoCheckInDispositivo implements ServicoCheckIn {
  ServicoCheckInDispositivo({required this.base, required this.dispositivo});

  final ServicoCheckIn base;
  final DispositivoTrato dispositivo;

  /// Última foto e posição capturadas; seguem para o backend quando a rota existir.
  String? ultimaFoto;
  PosicaoGps? ultimaPosicao;

  @override
  Future<FotoChegada?> tirarFoto() async {
    final ref = await dispositivo.fotografarEEnviar();
    if (ref == null) return null;
    ultimaFoto = ref;
    final agora = DateTime.now();
    final hora = '${agora.hour}h${agora.minute.toString().padLeft(2, '0')}';
    return FotoChegada(hora: hora);
  }

  /// A distância até o endereço é do backend (o app não tem o endereço antes da contratação).
  /// Com a posição capturada devolve 0 só para liberar o passo; o backend decide a validade.
  @override
  Future<int?> localizar() async {
    final posicao = await dispositivo.localizador.posicaoAtual();
    if (posicao == null) return null;
    ultimaPosicao = posicao;
    return 0;
  }

  @override
  Future<void> enviarMensagemRapida(String mensagem) => base.enviarMensagemRapida(mensagem);

  @override
  Future<void> avisarClienteAusente() => base.avisarClienteAusente();

  @override
  Future<ResultadoInicio> iniciarServico(String codigo) => base.iniciarServico(codigo);
}
