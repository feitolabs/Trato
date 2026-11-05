/// Posição registrada, mas o app não conhece o endereço (só o backend confere a distância).
const int distanciaDesconhecidaMetros = -1;

/// Foto de chegada já tirada. [hora] pronta para exibir ("14h06") e [referencia] opcional.
class FotoChegada {
  const FotoChegada({required this.hora, this.referencia});

  final String hora;
  final String? referencia;
}

enum ResultadoInicio {
  iniciado,

  /// O backend recusou o código. O app nunca confere o código sozinho.
  codigoIncorreto,

  /// Sem internet: a prova ficou guardada no aparelho e sai quando a conexão voltar.
  /// O serviço ainda NÃO começou; quem confirma é o backend.
  guardadoOffline,
}

/// Porta entre a tela de check-in e câmera, GPS e backend. Nenhuma validação de prova
/// acontece no app (escopo 4): o app captura e envia; o backend decide.
abstract interface class ServicoCheckIn {
  Future<FotoChegada?> tirarFoto();

  /// Distância até o endereço, em metros. Null se não conseguiu localizar.
  /// [distanciaDesconhecidaMetros] quando a posição foi registrada mas o app ainda não sabe
  /// onde fica o endereço (quem confere a distância é o backend).
  Future<int?> localizar();

  Future<void> enviarMensagemRapida(String mensagem);

  Future<void> avisarClienteAusente();

  Future<ResultadoInicio> iniciarServico(String codigo);
}
