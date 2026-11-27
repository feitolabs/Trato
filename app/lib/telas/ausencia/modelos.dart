/// Cliente ausente (Termos 7.6). O app só pede e mostra: espera, prazos, decisão, retenção e
/// reembolso vêm do servidor (`/v1/pedidos/{id}/ausencia`).
library;

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _texto(Object? v) {
  final t = v is String ? v.trim() : '';
  return t.isEmpty ? null : t;
}

class CasoAusencia {
  const CasoAusencia({
    required this.status,
    this.chegadaEm,
    this.podeRegistrarEm,
    this.registradaEm,
    this.justificativaAte,
    this.justificativaTexto,
    this.anexos = 0,
    this.decisao,
    this.retencaoCentavos,
    this.retencaoJustificativa,
    this.comprovantesDaRetencao = 0,
    this.cancelamentoStatus,
    this.reembolsoCentavos,
    this.contestarAte,
    this.contestacao,
  });

  factory CasoAusencia.deJson(Map<String, dynamic> j) => CasoAusencia(
        status: _texto(j['status']) ?? '',
        chegadaEm: _data(j['chegada_em']),
        podeRegistrarEm: _data(j['pode_registrar_em']),
        registradaEm: _data(j['registrada_em']),
        justificativaAte: _data(j['justificativa_ate']),
        justificativaTexto: _texto(j['justificativa_texto']),
        anexos: (j['anexos'] as List?)?.length ?? 0,
        decisao: _texto(j['decisao']),
        retencaoCentavos: (j['retencao_centavos'] as num?)?.toInt(),
        retencaoJustificativa: _texto(j['retencao_justificativa']),
        comprovantesDaRetencao: (j['retencao_comprovantes'] as List?)?.length ?? 0,
        cancelamentoStatus: _texto(j['cancelamento_status']),
        reembolsoCentavos: (j['reembolso_centavos'] as num?)?.toInt(),
        contestarAte: _data(j['contestar_ate']),
        contestacao: j['contestacao'] is Map<String, dynamic>
            ? ContestacaoAusencia.deJson(j['contestacao'] as Map<String, dynamic>)
            : null,
      );

  /// Termos 8.7: até quando o cliente contesta a retenção (do servidor).
  final DateTime? contestarAte;
  final ContestacaoAusencia? contestacao;

  /// Há uma retenção proposta, ainda sem contestação (o prazo é conferido à parte).
  bool get temRetencaoContestavel =>
      contestacao == null &&
      contestarAte != null &&
      (retencaoCentavos ?? 0) > 0 &&
      cancelamentoStatus == 'proposta_retencao_enviada';

  bool podeContestar(DateTime agora) => temRetencaoContestavel && !agora.isAfter(contestarAte!);

  /// `aguardando_espera`, `aguardando_justificativa`, `em_analise`, `justificativa_aceita`,
  /// `justificativa_recusada` ou `expirada_sem_justificativa`.
  final String status;
  final DateTime? chegadaEm;

  /// Antes disso o servidor recusa "Cliente ausente".
  final DateTime? podeRegistrarEm;
  final DateTime? registradaEm;
  final DateTime? justificativaAte;
  final String? justificativaTexto;
  final int anexos;

  /// O que o analista escreveu.
  final String? decisao;
  final int? retencaoCentavos;
  final String? retencaoJustificativa;
  final int comprovantesDaRetencao;

  /// `proposta_retencao_enviada` (ainda não cobrada), `confirmado`, `cancelado_sem_retencao`...
  final String? cancelamentoStatus;
  final int? reembolsoCentavos;

  bool get esperando => status == 'aguardando_espera';
  bool get pedeJustificativa => status == 'aguardando_justificativa';
}

class ContestacaoAusencia {
  const ContestacaoAusencia({
    required this.status,
    this.protocolo,
    this.texto,
    this.responderAte,
    this.resposta,
  });

  factory ContestacaoAusencia.deJson(Map<String, dynamic> j) => ContestacaoAusencia(
        status: _texto(j['status']) ?? '',
        protocolo: _texto(j['protocolo']),
        texto: _texto(j['texto']),
        responderAte: _data(j['responder_ate']),
        resposta: _texto(j['resposta']),
      );

  /// `aberta`, `mantida`, `alterada` ou `revertida`.
  final String status;
  final String? protocolo;
  final String? texto;
  final DateTime? responderAte;
  final String? resposta;
}

/// Uma prova do caso, com link assinado curto.
class AnexoAusencia {
  const AnexoAusencia({
    required this.tipo,
    required this.arquivoId,
    this.enviadoPor,
    this.url,
    this.expiraEmSegundos,
  });

  factory AnexoAusencia.deJson(Map<String, dynamic> j) => AnexoAusencia(
        tipo: _texto(j['tipo']) ?? '',
        arquivoId: _texto(j['arquivo_id']) ?? '',
        enviadoPor: _texto(j['enviado_por']),
        url: _texto(j['url']),
        expiraEmSegundos: (j['expira_em_segundos'] as num?)?.toInt(),
      );

  /// `registro_ausencia`, `justificativa`, `comprovante_retencao` ou `contestacao`.
  final String tipo;
  final String arquivoId;

  /// `cliente`, `profissional` ou `equipe`.
  final String? enviadoPor;
  final String? url;
  final int? expiraEmSegundos;
}

/// Do lado do profissional, no check-in: a chegada que abre a espera.
abstract interface class ServicoChegadaAusencia {
  /// Caso deste agendamento, se já existe. Nulo: nenhum (ou servidor sem a função).
  Future<CasoAusencia?> casoDeAusencia();

  /// Registra a chegada com a foto e o local. Nulo: servidor sem a rota (vale o fluxo antigo).
  Future<CasoAusencia?> registrarChegada();
}
