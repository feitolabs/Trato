import '../dados/erros.dart';
import '../dados/repositorios_api.dart';
import '../dados/servico_upload.dart';
import 'servico_camera.dart';
import 'servico_localizacao.dart';

/// Liga câmera, GPS e envio ao check-in/check-out. As permissões já foram garantidas pela
/// tela ([garantirPermissao]) antes de chamar.
///
/// Sem internet na hora de enviar a foto, ela segue como "pendente" (arquivo local) e sai
/// junto com o check-in quando a conexão voltar.
class CapturaCheckInDispositivo implements CapturaCheckIn {
  CapturaCheckInDispositivo({
    required this.camera,
    required this.localizacao,
    required this.upload,
    required this.pedidoId,
    this.destinoLatitude,
    this.destinoLongitude,
    this.finalidadeFoto = FinalidadeArquivo.checkIn,
  });

  final ServicoCamera camera;
  final ServicoLocalizacao localizacao;
  final ServicoUpload upload;
  final String pedidoId;
  final FinalidadeArquivo finalidadeFoto;

  /// Endereço liberado do pedido (só depois do pagamento). Se faltar, não mostramos distância.
  final double? destinoLatitude;
  final double? destinoLongitude;

  @override
  Future<FotoCapturada?> foto() async {
    final arquivo = await camera.tirarFoto();
    if (arquivo == null) return null;
    try {
      final enviado = await upload.enviar(arquivo, finalidadeFoto, pedidoId: pedidoId);
      return FotoCapturada(arquivoId: enviado.arquivoId, tiradaEm: arquivo.capturadaEm);
    } on ErroTrato catch (erro) {
      if (erro.tipo != TipoErro.semInternet) rethrow;
      return FotoCapturada(tiradaEm: arquivo.capturadaEm, local: arquivo);
    }
  }

  @override
  Future<PosicaoCapturada?> posicao() async {
    final PosicaoAtual p;
    try {
      p = await localizacao.posicaoAtual();
    } on ErroLocalizacao catch (erro) {
      throw ErroTrato(TipoErro.recusado, mensagemDaFalha(erro.falha));
    }
    final lat = destinoLatitude;
    final lon = destinoLongitude;
    return PosicaoCapturada(
      p.latitude,
      p.longitude,
      distanciaMetros: lat == null || lon == null
          ? null
          : localizacao.distanciaAteMetros(p, latitude: lat, longitude: lon),
    );
  }
}

String mensagemDaFalha(FalhaLocalizacao falha) => switch (falha) {
      FalhaLocalizacao.gpsDesligado => 'O GPS está desligado. Ligue a localização do aparelho.',
      FalhaLocalizacao.semPermissao => 'Sem permissão de localização. Permita nas configurações.',
      FalhaLocalizacao.semSinal => 'Não encontramos o sinal de GPS. Vá para um lugar aberto.',
    };
