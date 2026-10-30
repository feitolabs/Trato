import 'dart:async';

import 'package:http/http.dart' as http;

import '../dispositivo/preparador_imagem.dart';
import '../dispositivo/servico_camera.dart';
import 'cliente_api.dart';
import 'erros.dart';

/// Para que serve o arquivo. O backend usa para escolher a pasta, o tamanho máximo e o prazo
/// de guarda (dado sensível fica em bucket privado).
enum FinalidadeArquivo {
  checkIn('check_in'),
  checkOut('check_out'),
  documento('documento'),
  selfie('selfie'),
  notaMaterial('nota_material'),
  fotoPedido('foto_pedido'),
  evidenciaDisputa('evidencia_disputa'),
  portfolio('portfolio');

  const FinalidadeArquivo(this.codigo);

  final String codigo;
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

/// Envio real em dois passos.
///
/// TODO(backend): a rota abaixo ainda NÃO existe. Contrato proposto em `docs/app-camera-gps.md`.
///
/// 1. `POST /v1/arquivos/url-envio` `{finalidade, mime, tamanho_bytes, sha256, pedido_id?}`
///    → `{arquivo_id, url, cabecalhos?}`
/// 2. `PUT url` com os bytes (e os `cabecalhos`, se vierem) direto no armazenamento.
///
/// Enquanto a rota não existir, o passo 1 devolve 404 e vira [ErroTrato.indisponivel].
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
    // Sempre sem EXIF/GPS antes de sair do aparelho (M8), mesmo que a foto venha de outro caminho.
    final ArquivoCapturado arquivo;
    try {
      arquivo = garantirSemMetadados(original);
    } on FormatException {
      throw const ErroTrato(TipoErro.recusado, 'Esta foto não pôde ser lida. Tire outra.');
    }
    final resposta = await _api.post(
      '/v1/arquivos/url-envio',
      corpo: {
        'finalidade': finalidade.codigo,
        'mime': arquivo.mime,
        'tamanho_bytes': arquivo.tamanho,
        'sha256': arquivo.sha256,
        if (pedidoId != null) 'pedido_id': pedidoId,
      },
      // O mesmo conteúdo reenviado reaproveita o registro: seguro tentar de novo.
      chaveIdempotencia: 'arquivo-${arquivo.sha256}-${finalidade.codigo}',
    );
    final mapa = resposta! as Map<String, dynamic>;
    final url = Uri.parse(mapa['url'] as String);
    final cabecalhos = {
      'Content-Type': arquivo.mime,
      for (final e in ((mapa['cabecalhos'] as Map<String, dynamic>?) ?? {}).entries)
        e.key: '${e.value}',
    };
    try {
      final r = await _cliente
          .put(url, headers: cabecalhos, body: arquivo.bytes)
          .timeout(const Duration(seconds: 60));
      if (r.statusCode < 200 || r.statusCode >= 300) throw ErroTrato.servidor;
    } on http.ClientException {
      throw ErroTrato.semInternet;
    } on TimeoutException {
      throw ErroTrato.semInternet;
    }
    return ArquivoEnviado(
      arquivoId: mapa['arquivo_id'] as String,
      caminho: mapa['caminho'] as String?,
    );
  }
}
