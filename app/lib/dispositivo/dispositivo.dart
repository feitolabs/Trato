import '../dados/cliente_api.dart';
import '../dados/servico_upload.dart';
import 'captura_foto.dart';
import 'permissao.dart';
import 'servico_camera.dart';
import 'servico_camera_real.dart';
import 'servico_localizacao.dart';
import 'servico_localizacao_real.dart';

/// Todos os serviços de aparelho num só lugar, para o ponto de entrada montar uma vez.
class Dispositivo {
  Dispositivo({
    required this.camera,
    required this.localizacao,
    required this.permissao,
    required this.upload,
  });

  /// Aparelho de verdade (câmera, GPS, permissões do sistema) e envio pela API.
  factory Dispositivo.real(ClienteApi api) => Dispositivo(
        camera: ServicoCameraReal(),
        localizacao: const ServicoLocalizacaoReal(),
        permissao: const ServicoPermissaoReal(),
        upload: ServicoUploadApi(api),
      );

  /// Demonstração e testes: nada toca no aparelho nem na rede.
  factory Dispositivo.fake() => Dispositivo(
        camera: ServicoCameraFake(),
        localizacao: ServicoLocalizacaoFake(),
        permissao: ServicoPermissaoFake(),
        upload: ServicoUploadFake(),
      );

  final ServicoCamera camera;
  final ServicoLocalizacao localizacao;
  final ServicoPermissao permissao;
  final ServicoUpload upload;

  late final CapturaFoto fotos = CapturaFoto(camera: camera, permissao: permissao, upload: upload);
}
