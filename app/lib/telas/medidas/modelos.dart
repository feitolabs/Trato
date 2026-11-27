/// Medidas da conta (Termos 11.8 e 20). Tipo, motivo, prazos e contestação vêm do servidor
/// (`/v1/me/medidas`): o app só mostra e envia a versão da pessoa.
library;

import 'dart:async';
import 'dart:io' show IOException;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../dados/cliente_api.dart';
import '../../dados/erros.dart';
import '../../dispositivo/preparador_imagem.dart';
import '../../dispositivo/servico_camera.dart';
import 'retorno_conta.dart';

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _texto(Object? v) {
  final t = v is String ? v.trim() : '';
  return t.isEmpty ? null : t;
}

/// Limites do envio de provas (os mesmos do servidor, que é quem decide).
const maximoDeProvas = 10;
const tamanhoMaximoDaProva = 10 * 1024 * 1024;
const textoProvaRecusada = 'Envie foto (JPG, PNG ou WebP) ou PDF.';

/// O tipo pelo conteúdo do arquivo (o nome não conta). Nulo: tipo que o servidor não aceita.
String? tipoDaProva(Uint8List b) {
  bool comeca(List<int> marca, [int em = 0]) {
    if (b.length < em + marca.length) return false;
    for (var i = 0; i < marca.length; i++) {
      if (b[em + i] != marca[i]) return false;
    }
    return true;
  }

  if (comeca(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (comeca(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (comeca('RIFF'.codeUnits) && comeca('WEBP'.codeUnits, 8)) return 'image/webp';
  if (comeca('%PDF'.codeUnits)) return 'application/pdf';
  return null;
}

String nomeDoTipo(String contentType) => switch (contentType) {
      'image/jpeg' => 'Foto JPG',
      'image/png' => 'Imagem PNG',
      'image/webp' => 'Imagem WebP',
      'application/pdf' => 'PDF',
      _ => 'Arquivo',
    };

String tamanhoLegivel(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB'
    : '${(bytes / 1024).ceil()} KB';

/// Um arquivo escolhido no aparelho para ir com a contestação.
class ProvaEscolhida {
  ProvaEscolhida({required this.nome, required this.bytes});

  final String nome;
  final Uint8List bytes;

  /// Preenchido quando o arquivo já subiu: "tentar de novo" não envia outra vez.
  String? anexoId;
}

class AnexoDaContestacao {
  const AnexoDaContestacao({
    required this.anexoId,
    required this.contentType,
    required this.tamanhoBytes,
  });

  final String anexoId;
  final String contentType;
  final int tamanhoBytes;
}

class ContestacaoDeMedida {
  const ContestacaoDeMedida({
    required this.status,
    this.protocolo,
    this.versao,
    this.abertaEm,
    this.responderAte,
    this.resposta,
    this.decididaEm,
    this.anexos = const [],
  });

  /// O que foi enviado como prova (o servidor não manda link).
  final List<AnexoDaContestacao> anexos;

  factory ContestacaoDeMedida.deJson(Map<String, dynamic> j) => ContestacaoDeMedida(
        status: _texto(j['status']) ?? '',
        protocolo: _texto(j['protocolo']),
        versao: _texto(j['versao']),
        abertaEm: _data(j['aberta_em']),
        responderAte: _data(j['responder_ate']),
        resposta: _texto(j['resposta']),
        decididaEm: _data(j['decidida_em']),
        anexos: [
          for (final a in (j['anexos'] is List ? j['anexos'] as List : const []))
            if (a is Map)
              AnexoDaContestacao(
                anexoId: '${a['anexo_id'] ?? ''}',
                contentType: '${a['content_type'] ?? ''}',
                tamanhoBytes: (a['tamanho_bytes'] as num?)?.toInt() ?? 0,
              ),
        ],
      );

  /// `aberta`, `em_analise`, `mantida`, `alterada` ou `revertida`.
  final String status;
  final String? protocolo;

  /// A versão dos fatos que a pessoa escreveu.
  final String? versao;
  final DateTime? abertaEm;
  final DateTime? responderAte;
  final String? resposta;
  final DateTime? decididaEm;

  String get statusTexto => switch (status) {
        'aberta' => 'Contestação enviada',
        'em_analise' => 'Contestação em análise',
        'mantida' => 'Contestação analisada: medida mantida',
        'alterada' => 'Contestação analisada: medida alterada',
        'revertida' => 'Contestação analisada: medida revertida',
        _ => 'Contestação registrada',
      };
}

class MedidaDeConta {
  const MedidaDeConta({
    required this.id,
    required this.tipo,
    this.protocolo,
    this.motivo,
    this.clausulas = const [],
    this.inicioEm,
    this.fimEm,
    this.efeito,
    this.comoContestar,
    this.detalheAdiado = false,
    this.vigente = false,
    this.revertidaEm,
    this.avisadoEm,
    this.contestavelAte,
    this.contestacao,
  });

  factory MedidaDeConta.deJson(Map<String, dynamic> j) => MedidaDeConta(
        id: '${j['id'] ?? ''}',
        tipo: _texto(j['tipo']) ?? '',
        protocolo: _texto(j['protocolo']),
        motivo: _texto(j['motivo']),
        clausulas: [
          for (final c in (j['clausulas'] is List ? j['clausulas'] as List : const []))
            if ('$c'.trim().isNotEmpty) '$c'.trim(),
        ],
        inicioEm: _data(j['inicio_em']),
        fimEm: _data(j['fim_em']),
        efeito: _texto(j['efeito_pedidos_valores']),
        comoContestar: _texto(j['como_contestar']),
        detalheAdiado: j['detalhe_adiado'] == true,
        vigente: j['vigente'] == true,
        revertidaEm: _data(j['revertida_em']),
        avisadoEm: _data(j['avisado_em']),
        contestavelAte: _data(j['contestavel_ate']),
        contestacao: j['contestacao'] is Map<String, dynamic>
            ? ContestacaoDeMedida.deJson(j['contestacao'] as Map<String, dynamic>)
            : null,
      );

  final String id;

  /// `aviso`, `restricao`, `suspensao`, `encerramento`, `bloqueio_preventivo`, `trava_saque` ou
  /// `remocao_conteudo`.
  final String tipo;
  final String? protocolo;
  final String? motivo;
  final List<String> clausulas;
  final DateTime? inicioEm;
  final DateTime? fimEm;

  /// O que acontece com pedidos e valores em andamento (20.4).
  final String? efeito;
  final String? comoContestar;
  final bool detalheAdiado;
  final bool vigente;
  final DateTime? revertidaEm;
  final DateTime? avisadoEm;

  /// 30 dias do aviso (20.5); a data é do servidor.
  final DateTime? contestavelAte;
  final ContestacaoDeMedida? contestacao;

  String get tipoTexto => switch (tipo) {
        'aviso' => 'Aviso',
        'restricao' => 'Restrição de funções',
        'suspensao' => 'Suspensão da conta',
        'encerramento' => 'Encerramento da conta',
        'bloqueio_preventivo' => 'Bloqueio preventivo',
        'trava_saque' => 'Trava de saques',
        'remocao_conteudo' => 'Remoção de conteúdo',
        _ => 'Medida na conta',
      };

  String get situacaoTexto => revertidaEm != null
      ? 'Revertida'
      : vigente
          ? 'Em vigor'
          : 'Encerrada';

  /// O botão "Contestar" aparece; quem decide se vale é o servidor.
  bool podeContestar(DateTime agora) =>
      contestacao == null &&
      revertidaEm == null &&
      contestavelAte != null &&
      !agora.isAfter(contestavelAte!);
}

const textoMedidasIndisponiveis =
    'As medidas da conta estão indisponíveis no momento. Fale com o atendimento.';

abstract interface class ServicoMedidas {
  /// Nulo: o servidor não tem a função (404/503).
  Future<List<MedidaDeConta>?> listar();

  /// Envia as provas (se houver) e depois a contestação. Em caso de erro, [provas] guarda o
  /// que já subiu.
  Future<MedidaDeConta> contestar(
    String id,
    String versao, {
    List<ProvaEscolhida> provas = const [],
  });
}

class ServicoMedidasApi implements ServicoMedidas, ServicoRetornoConta {
  ServicoMedidasApi(this._api, {http.Client? cliente}) : _cliente = cliente ?? http.Client();

  final ClienteApi _api;

  static const _caminhoRetorno = '/v1/me/conta/retorno';

  @override
  Future<List<PedidoRetorno>?> listarRetornos() async {
    try {
      final j = await _api.get(_caminhoRetorno);
      final itens = j is Map ? j['itens'] : null;
      return [
        if (itens is List)
          for (final item in itens)
            if (item is Map) PedidoRetorno.deJson(item),
      ];
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return null;
      rethrow;
    }
  }

  @override
  Future<PedidoRetorno> pedirRetorno(String justificativa) async {
    final j = await _api.post(_caminhoRetorno, corpo: {'justificativa': justificativa.trim()});
    return PedidoRetorno.deJson(j is Map ? j : const {});
  }

  /// Só para o PUT no link assinado do armazenamento (sem a chave da sessão).
  final http.Client _cliente;

  @override
  Future<List<MedidaDeConta>?> listar() async {
    try {
      final j = await _api.get('/v1/me/medidas');
      return [
        for (final m in (j! as List))
          if (m is Map<String, dynamic>) MedidaDeConta.deJson(m),
      ];
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 || e.codigoHttp == 503) return null;
      rethrow;
    }
  }

  @override
  Future<MedidaDeConta> contestar(
    String id,
    String versao, {
    List<ProvaEscolhida> provas = const [],
  }) async {
    for (final prova in provas) {
      prova.anexoId ??= await _enviarProva(id, prova);
    }
    try {
      final j = await _api.post(
        '/v1/me/medidas/$id/contestacao',
        corpo: {
          'versao': versao.trim(),
          // Sem arquivo o campo não vai: o servidor antigo recusa campo a mais.
          if (provas.isNotEmpty) 'anexos': [for (final p in provas) p.anexoId],
        },
      );
      return MedidaDeConta.deJson(j! as Map<String, dynamic>);
    } on ErroTrato catch (e) {
      if (const {'anexo_nao_enviado', 'anexo_invalido', 'arquivo_invalido'}.contains(e.codigo)) {
        // O servidor não aceitou o que subiu: a próxima tentativa envia de novo.
        for (final p in provas) {
          p.anexoId = null;
        }
      }
      throw _traduzir(e);
    }
  }

  Future<String> _enviarProva(String id, ProvaEscolhida prova) async {
    var bytes = prova.bytes;
    var tipo = tipoDaProva(bytes);
    if (tipo == null) throw const ErroTrato(TipoErro.recusado, textoProvaRecusada);
    if (tipo == 'image/jpeg') {
      // Sem local nem dados do aparelho antes de sair (M8).
      try {
        final limpa = garantirSemMetadados(ArquivoCapturado(
          bytes: bytes,
          sha256: crypto.sha256.convert(bytes).toString(),
          capturadaEm: DateTime.now().toUtc(),
        ));
        bytes = limpa.bytes;
        tipo = limpa.mime;
      } on FormatException {
        throw const ErroTrato(TipoErro.recusado, 'Esta foto não pôde ser lida. Escolha outra.');
      }
    }
    final Map<String, dynamic> pedido;
    try {
      pedido = (await _api.post('/v1/me/medidas/$id/contestacao/anexos', corpo: {
        'nome_arquivo': prova.nome,
        'content_type': tipo,
        'tamanho_bytes': bytes.length,
      }))! as Map<String, dynamic>;
    } on ErroTrato catch (e) {
      if (e.codigoHttp == 404 && e.codigo != 'nao_encontrada') {
        throw const ErroTrato(
          TipoErro.recusado,
          'Por enquanto não dá para enviar arquivos. Remova-os para contestar só com o texto.',
        );
      }
      throw _traduzir(e);
    }
    final falha = ErroTrato(
      TipoErro.recusado,
      'Não foi possível enviar o arquivo "${prova.nome}". Tente de novo.',
    );
    try {
      final r = await _cliente
          .put(
            Uri.parse(pedido['url'] as String),
            headers: {'Content-Type': tipo, 'x-upsert': 'true'},
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode < 200 || r.statusCode >= 300) throw falha;
    } on http.ClientException {
      throw ErroTrato.semInternet;
    } on IOException {
      throw ErroTrato.semInternet;
    } on TimeoutException {
      throw ErroTrato.semInternet;
    }
    return pedido['anexo_id'] as String;
  }

  ErroTrato _traduzir(ErroTrato e) {
    final texto = switch (e.codigo) {
      'prazo_encerrado' => 'O prazo de 30 dias para contestar terminou.',
      'ja_contestada' => 'Esta medida já foi contestada.',
      'nao_encontrada' => 'Medida não encontrada.',
      'anexo_nao_enviado' => 'Um dos arquivos não chegou. Tente de novo.',
      'anexo_invalido' || 'arquivo_invalido' => e.mensagem,
      _ => e.codigoHttp == 404 || e.codigoHttp == 503 ? textoMedidasIndisponiveis : null,
    };
    if (texto == null) return e;
    return ErroTrato(TipoErro.recusado, texto, codigoHttp: e.codigoHttp, codigo: e.codigo);
  }
}
