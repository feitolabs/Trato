import 'dart:async';

import 'package:http/http.dart' as http;

import '../dispositivo/preparador_imagem.dart';
import '../dispositivo/servico_camera.dart';
import 'cliente_api.dart';
import 'erros.dart';

/// Para que serve o arquivo. O backend usa para escolher a pasta, o tamanho máximo e o prazo
/// de guarda (dado sensível fica em bucket privado).
enum FinalidadeArquivo {
  checkIn('checkin'),
  checkOut('checkout'),
  documento('verificacao'),
  selfie('verificacao'),
  notaMaterial('nota_material'),
  fotoPedido('pedido'),
  evidenciaDisputa('disputa'),

  /// Sem destino no backend ainda (`docs/app-divergencias.md`).
  portfolio('portfolio');

  const FinalidadeArquivo(this.codigo);

  /// O `destino` de `POST /v1/uploads`.
  final String codigo;

  /// `tipo_documento` do envio de verificação.
  String? get tipoDocumento => switch (this) {
        documento => 'documento_frente',
        selfie => 'selfie',
        _ => null,
      };
}

/// Arquivo já guardado pelo backend. [arquivoId] é a referência que as telas e rotas usam.
class ArquivoEnviado {
  const ArquivoEnviado({required this.arquivoId, this.caminho});

  final String arquivoId;
  final String? caminho;
}

/// Envia arquivo ao armazenamento. Nunca com chave no app: o backend assina uma URL de envio
/// de uso único e o app só faz o PUT nela.
abstract interface class ServicoUpload {
  /// Lança [ErroTrato] (`semInternet` quando não há conexão).
  Future<ArquivoEnviado> enviar(
    ArquivoCapturado arquivo,
    FinalidadeArquivo finalidade, {
    String? pedidoId,
  });
}

/// Para teste e demonstração: guarda o que "enviou" e devolve ids sequenciais.
class ServicoUploadFake implements ServicoUpload {
  ServicoUploadFake({this.falha});

  /// Se preenchido, todo envio lança este erro (ex.: [ErroTrato.semInternet]).
  ErroTrato? falha;
  final List<(ArquivoCapturado, FinalidadeArquivo, String?)> enviados = [];

  @override
  Future<ArquivoEnviado> enviar(
    ArquivoCapturado arquivo,
    FinalidadeArquivo finalidade, {
    String? pedidoId,
  }) async {
    if (falha != null) throw falha!;
    enviados.add((arquivo, finalidade, pedidoId));
    return ArquivoEnviado(arquivoId: 'arq-${enviados.length}');
  }
}

/// Envio real em três passos (`backend/src/trato/api/rotas_upload.py`).
///
/// 1. `POST /v1/uploads` `{destino, nome_arquivo, content_type, tamanho_bytes, pedido_id?,
///    tipo_documento?}` → `{upload_id, url_envio, metodo, expira_em_segundos, content_type}`
/// 2. `PUT url_envio` com os bytes, direto no armazenamento (nunca com chave no app).
/// 3. `POST /v1/uploads/{upload_id}/concluir` `{latitude?, longitude?}`: o backend confere o
///    conteúdo, tira EXIF e registra. Devolve `midia_id` (documento de verificação não devolve).
///
/// [ArquivoEnviado.arquivoId] é o `midia_id` quando existe; senão, o `upload_id` (é o que a
/// verificação do profissional usa).
class ServicoUploadApi implements ServicoUpload {
  ServicoUploadApi(this._api, {http.Client? cliente}) : _cliente = cliente ?? http.Client();

  final ClienteApi _api;
  final http.Client _cliente;

  @override
  Future<ArquivoEnviado> enviar(
    ArquivoCapturado original,
    FinalidadeArquivo finalidade, {
    String? pedidoId,
  }) async {
    if (finalidade == FinalidadeArquivo.portfolio) throw ErroTrato.indisponivel;
    // Sempre sem EXIF/GPS antes de sair do aparelho (M8), mesmo que a foto venha de outro caminho.
    final ArquivoCapturado arquivo;
    try {
      arquivo = garantirSemMetadados(original);
    } on FormatException {
      throw const ErroTrato(TipoErro.recusado, 'Esta foto não pôde ser lida. Tire outra.');
    }
    final tipoDocumento = finalidade.tipoDocumento;
    final resposta = await _api.post(
      '/v1/uploads',
      corpo: {
        'destino': finalidade.codigo,
        'nome_arquivo': '${finalidade.codigo}-${arquivo.sha256.substring(0, arquivo.sha256.length < 12 ? arquivo.sha256.length : 12)}.jpg',
        'content_type': arquivo.mime,
        'tamanho_bytes': arquivo.tamanho,
        if (pedidoId != null) 'pedido_id': pedidoId,
        if (tipoDocumento != null) 'tipo_documento': tipoDocumento,
      },
    );
    final mapa = resposta! as Map<String, dynamic>;
    final uploadId = mapa['upload_id'] as String;
    try {
      final r = await _cliente
          .put(
            Uri.parse(mapa['url_envio'] as String),
            headers: {'Content-Type': arquivo.mime},
            body: arquivo.bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode < 200 || r.statusCode >= 300) throw ErroTrato.servidor;
    } on http.ClientException {
      throw ErroTrato.semInternet;
    } on TimeoutException {
      throw ErroTrato.semInternet;
    }
    final fim = await _api.post('/v1/uploads/$uploadId/concluir', corpo: <String, Object?>{});
    final midia = (fim is Map<String, dynamic>) ? fim['midia_id'] as String? : null;
    return ArquivoEnviado(arquivoId: midia ?? uploadId);
  }
}
