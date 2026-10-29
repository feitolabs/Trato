/// Foto de chegada já tirada. [hora] pronta para exibir ("14h06").
class FotoChegada {
  const FotoChegada({required this.hora});

  final String hora;
}

enum ResultadoInicio {
  iniciado,

  /// O backend recusou o código. O app nunca confere o código sozinho.
  codigoIncorreto,
}

/// Porta entre a tela de check-in e câmera, GPS e backend. Nenhuma validação de prova
/// acontece no app (escopo 4): o app captura e envia; o backend decide.
abstract interface class ServicoCheckIn {
  Future<FotoChegada?> tirarFoto();

  /// Distância até o endereço, em metros. Null se não conseguiu localizar.
  Future<int?> localizar();

  Future<void> enviarMensagemRapida(String mensagem);

  Future<void> avisarClienteAusente();

  Future<ResultadoInicio> iniciarServico(String codigo);
}
