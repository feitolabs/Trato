import 'package:flutter/material.dart';

import '../componentes/componentes.dart';
import '../dados/erros.dart';
import '../dados/servico_upload.dart';
import '../tema/tema.dart';
import 'explicacao_permissao.dart';
import 'permissao.dart';
import 'servico_camera.dart';

/// Junta permissão, câmera/galeria e envio para as telas que só pedem "uma foto".
/// Devolve a referência (`arquivoId`) do arquivo enviado, que é o que as telas guardam.
///
/// Uso (no ponto onde a tela é montada, com o `context` dela):
/// `aoCapturarFoto: () => captura.capturar(context, FinalidadeArquivo.notaMaterial)`
class CapturaFotoGuiada {
  CapturaFotoGuiada({required this.camera, required this.permissao, required this.upload});

  final ServicoCamera camera;
  final ServicoPermissao permissao;
  final ServicoUpload upload;

  /// [frontal] para selfie. [permitirGaleria] oferece "Escolher da galeria" (não serve para
  /// documento nem selfie: ali a foto tem que ser tirada na hora).
  Future<String?> capturar(
    BuildContext context,
    FinalidadeArquivo finalidade, {
    bool frontal = false,
    bool permitirGaleria = false,
    String? pedidoId,
    TextoPermissao textoCamera = TextoPermissao.cameraFoto,
  }) async {
    final avisador = ScaffoldMessenger.of(context);
    var daGaleria = false;
    if (permitirGaleria) {
      final origem = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: CoresTrato.superficie,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EspacosTrato.margemTela,
              0,
              EspacosTrato.margemTela,
              EspacosTrato.x4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BotaoPrimario(
                  texto: 'Tirar foto',
                  icone: Icons.photo_camera_outlined,
                  aoTocar: () => Navigator.of(sheet).pop(false),
                ),
                const SizedBox(height: EspacosTrato.x3),
                BotaoSecundario(
                  texto: 'Escolher da galeria',
                  icone: Icons.photo_library_outlined,
                  aoTocar: () => Navigator.of(sheet).pop(true),
                ),
              ],
            ),
          ),
        ),
      );
      if (origem == null) return null;
      daGaleria = origem;
    }
    if (!context.mounted) return null;
    if (!daGaleria &&
        !await garantirPermissao(context, permissao, TipoPermissao.camera, textoCamera)) {
      return null;
    }
    try {
      final arquivo =
          daGaleria ? await camera.escolherDaGaleria() : await camera.tirarFoto(frontal: frontal);
      if (arquivo == null) return null;
      final enviado = await upload.enviar(arquivo, finalidade, pedidoId: pedidoId);
      return enviado.arquivoId;
    } on ErroTrato catch (erro) {
      _avisar(avisador, erro.mensagem);
    } on FormatException {
      _avisar(avisador, 'Não conseguimos ler essa imagem. Tente outra foto.');
    }
    return null;
  }

  void _avisar(ScaffoldMessengerState avisador, String mensagem) =>
      avisador.showSnackBar(SnackBar(content: Text(mensagem)));
}
