/// Contestação da decisão de uma disputa (Termos 8.7). Prazo, situação, resposta e nova decisão
/// vêm do servidor (`/v1/pedidos/{id}/disputa/contestacoes`): o app só mostra e envia o texto e
/// os arquivos.
library;

import 'package:crypto/crypto.dart' as crypto;

import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';
import '../../dados/servico_upload.dart';
import '../../dispositivo/servico_camera.dart';
import '../medidas/modelos.dart' show ProvaEscolhida, tipoDaProva, textoProvaRecusada;

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _texto(Object? v) {
  final t = v is String ? v.trim() : '';
  return t.isEmpty ? null : t;
}

/// Os mesmos limites do servidor, que é quem decide.
const minimoDoTexto = 10;
const maximoDoTexto = 4000;
const maximoDeArquivos = 10;

class ContestacaoDaParte {
  const ContestacaoDaParte({
    required this.id,
    required this.status,
    required this.minha,
    this.protocolo,
    this.abertaEm,
    this.responderAte,
    this.oQueFaltou,
    this.anexos = const [],
    this.resposta,
    this.novaDecisao,
    this.novoValorReembolsoCentavos,
    this.decididaEm,
  });

  factory ContestacaoDaParte.deJson(Map<String, dynamic> j) => ContestacaoDaParte(
        id: '${j['id'] ?? ''}',
        status: _texto(j['status']) ?? '',
        // Sem o campo, trata como da outra parte: nada "seu" é mostrado por engano.
        minha: j['minha'] == true,
        protocolo: _texto(j['protocolo']),
        abertaEm: _data(j['aberta_em']),
        responderAte: _data(j['responder_ate']),
        oQueFaltou: _texto(j['o_que_faltou']),
        anexos: [
          for (final a in (j['anexos'] is List ? j['anexos'] as List : const []))
            if (a is String) a,
        ],
        resposta: _texto(j['resposta']),
        novaDecisao: _texto(j['nova_decisao']),
        novoValorReembolsoCentavos: j['novo_valor_reembolso_centavos'] is int
            ? j['novo_valor_reembolso_centavos'] as int
            : null,
        decididaEm: _data(j['decidida_em']),
      );

  final String id;

  /// `aberta`, `em_analise`, `mantida`, `alterada` ou `revertida`.
  final String status;
  final bool minha;
  final String? protocolo;
  final DateTime? abertaEm;
  final DateTime? responderAte;

  /// Só vem na contestação de quem consulta.
  final String? oQueFaltou;
  final List<String> anexos;
  final String? resposta;
  final String? novaDecisao;
  final int? novoValorReembolsoCentavos;
  final DateTime? decididaEm;

  String get statusTexto => switch (status) {
        'aberta' => 'Contestação enviada',
        'em_analise' => 'Em análise',
        'mantida' => 'Analisada: decisão mantida',
        'alterada' => 'Analisada: decisão alterada',
        'revertida' => 'Analisada: decisão revertida',
        _ => 'Contestação registrada',
      };

  String? get novaDecisaoTexto => switch (novaDecisao) {
        null => null,
        'liberar_tudo' => 'Liberar todo o valor ao profissional',
        'reembolso_total' => 'Devolver todo o valor ao cliente',
        'reembolso_parcial' => 'Devolver parte do valor ao cliente',
        'nova_visita' => 'Nova visita para resolver o serviço',
        _ => 'Veja a resposta ou fale com o Trato',
      };
}

class ContestacoesDoPedido {
  const ContestacoesDoPedido({
    required this.podeContestar,
    this.contestarAte,
    this.itens = const [],
  });

  factory ContestacoesDoPedido.deJson(Map<String, dynamic> j) => ContestacoesDoPedido(
        podeContestar: j['pode_contestar'] == true,
        contestarAte: _data(j['contestar_ate']),
        itens: [
          for (final i in (j['itens'] is List ? j['itens'] as List : const []))
            if (i is Map<String, dynamic>) ContestacaoDaParte.deJson(i),
        ],
      );

  final bool podeContestar;

  /// Nulo (e sem itens): não há disputa decidida.
  final DateTime? contestarAte;
  final List<ContestacaoDaParte> itens;

  bool get temDecisao => podeContestar || contestarAte != null || itens.isNotEmpty;

  ContestacaoDaParte? get minha {
    for (final i in itens) {
      if (i.minha) return i;
    }
    return null;
  }
}

/// Falha ao subir um dos arquivos: a mensagem aparece junto dele.
class ErroDeArquivo implements Exception {
  const ErroDeArquivo(this.indice, this.mensagem);

  final int indice;
  final String mensagem;
}

abstract interface class ServicoContestacaoDecisao {
  /// Há como enviar arquivos neste aparelho.
  bool get podeAnexar;

  /// Nulo: o servidor não tem a função ou o pedido não é encontrado (404/503).
  Future<ContestacoesDoPedido?> ver(String pedidoId);

  /// Envia os arquivos (se houver) e depois a contestação. Em caso de erro, [arquivos] guarda o
  /// que já subiu, e tentar de novo com o mesmo conteúdo não duplica.
  Future<ContestacaoDaParte> contestar(
    String pedidoId,
    String oQueFaltou, {
    List<ProvaEscolhida> arquivos = const [],
  });
}

class ServicoContestacaoDecisaoApi implements ServicoContestacaoDecisao {
  ServicoContestacaoDecisaoApi(this._api, {this.upload});

  final ClienteApi _api;

  /// O envio de arquivos do pedido (URL assinada), o mesmo das fotos da disputa.
  final ServicoUpload? upload;

  String _rota(String pedidoId) => '/v1/pedidos/$pedidoId/disputa/contestacoes';

  @override
  bool get podeAnexar => upload != null;

  @override
  Future<ContestacoesDoPedido?> ver(String pedidoId) async {
    try {
      final j = await _api.get(_rota(pedidoId));
      return j is Map<String, dynamic> ? ContestacoesDoPedido.deJson(j) : null;
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return null;
      rethrow;
    }
  }

  @override
  Future<ContestacaoDaParte> contestar(
    String pedidoId,
    String oQueFaltou, {
    List<ProvaEscolhida> arquivos = const [],
  }) async {
    for (final (i, a) in arquivos.indexed) {
      if (a.anexoId != null) continue;
      final tipo = tipoDaProva(a.bytes);
      final envio = upload;
      if (tipo == null || envio == null) throw ErroDeArquivo(i, textoProvaRecusada);
      try {
        final enviado = await envio.enviar(
          ArquivoCapturado(
            bytes: a.bytes,
            sha256: crypto.sha256.convert(a.bytes).toString(),
            capturadaEm: DateTime.now().toUtc(),
            mime: tipo,
          ),
          FinalidadeArquivo.evidenciaDisputa,
          pedidoId: pedidoId,
        );
        a.anexoId = enviado.arquivoId;
      } on ErroTrato catch (e) {
        throw ErroDeArquivo(i, e.mensagem);
      }
    }
    try {
      final j = await _api.post(
        _rota(pedidoId),
        corpo: {
          'o_que_faltou': oQueFaltou.trim(),
          'anexos': [for (final a in arquivos) a.anexoId],
        },
      );
      return ContestacaoDaParte.deJson(
        j is Map<String, dynamic> ? j : const <String, dynamic>{},
      );
    } on ErroTrato catch (e) {
      // O servidor não aceitou algum arquivo: a próxima tentativa envia todos de novo.
      if (e.codigo == 'anexo_invalido') {
        for (final a in arquivos) {
          a.anexoId = null;
        }
      }
      rethrow;
    }
  }
}
