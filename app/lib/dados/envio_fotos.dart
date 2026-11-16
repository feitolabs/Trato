import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../dispositivo/servico_camera.dart';
import 'servico_upload.dart';

/// Sobe as fotos tiradas no aparelho (caminhos de arquivo) e devolve o que a API pede em
/// `fotos`: `{arquivo_id, tirada_em}`. Referência que não é arquivo local (ou já foi enviada)
/// é ignorada. Sem [upload], devolve vazio. Erro de rede sobe ao chamador: a prova não pode
/// sumir em silêncio.
Future<List<Map<String, Object?>>> enviarFotosLocais(
  ServicoUpload? upload,
  Iterable<String> referencias,
  FinalidadeArquivo finalidade, {
  required String pedidoId,
}) async {
  if (upload == null) return const [];
  final saida = <Map<String, Object?>>[];
  for (final ref in referencias) {
    final arquivo = File(ref);
    if (ref.startsWith('[') || !arquivo.existsSync()) continue;
    final bytes = await arquivo.readAsBytes();
    final capturadaEm = DateTime.now().toUtc();
    final enviado = await upload.enviar(
      ArquivoCapturado(
        bytes: bytes,
        sha256: crypto.sha256.convert(bytes).toString(),
        capturadaEm: capturadaEm,
      ),
      finalidade,
      pedidoId: pedidoId,
    );
    saida.add({
      'arquivo_id': enviado.arquivoId,
      'tirada_em': capturadaEm.toIso8601String(),
    });
  }
  return saida;
}
