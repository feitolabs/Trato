import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/servico_upload.dart';
import 'package:trato/dispositivo/preparador_imagem.dart';
import 'package:trato/dispositivo/servico_camera.dart';

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
