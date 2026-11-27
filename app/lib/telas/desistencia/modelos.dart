/// Desistir do pedido (Termos 7.2 e 7.3). O app só pede e mostra: se pode desistir, o que
/// acontece e quanto volta vêm do servidor (`/v1/pedidos/{id}/desistencia` e `/desistir`).
library;

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _texto(Object? v) {
  final t = v is String ? v.trim() : '';
  return t.isEmpty ? null : t;
}

/// O que acontece se a pessoa confirmar.
enum EfeitoDesistencia {
  reembolsoIntegral,
  analise,
  indisponivel;

  /// Valor desconhecido vira [indisponivel]: o app não promete o que não entende.
  static EfeitoDesistencia deTexto(Object? v) => switch (v) {
        'reembolso_integral' => reembolsoIntegral,
        'analise' => analise,
        _ => indisponivel,
      };
}

/// Comprovante da desistência.
class RegistroDesistencia {
  const RegistroDesistencia({
    this.protocolo,
    this.recebidoEm,
    this.situacao = '',
    this.reembolsoCentavos,
    this.mensagem,
  });

  factory RegistroDesistencia.deJson(Map<String, dynamic> j) => RegistroDesistencia(
        protocolo: _texto(j['protocolo']),
        recebidoEm: _data(j['recebido_em']),
        situacao: _texto(j['situacao']) ?? '',
        reembolsoCentavos: (j['reembolso_centavos'] as num?)?.toInt(),
        mensagem: _texto(j['mensagem']),
      );

  final String? protocolo;
  final DateTime? recebidoEm;

  /// `reembolso_integral`, `em_analise` ou `analisado`.
  final String situacao;

  /// Nulo enquanto o analista não decide.
  final int? reembolsoCentavos;
  final String? mensagem;

  String get situacaoTexto => switch (situacao) {
        'reembolso_integral' => 'Pedido cancelado, com reembolso integral',
        'em_analise' => 'Em análise por um analista',
        'analisado' => 'Analisada',
        _ => 'Recebida',
      };
}

class SituacaoDesistencia {
  const SituacaoDesistencia({
    required this.efeito,
    this.podeDesistir = false,
    this.motivoIndisponivel,
    this.arrependimentoAte,
    this.pediuExecucaoImediata = false,
    this.registro,
  });

  factory SituacaoDesistencia.deJson(Map<String, dynamic> j) {
    final registro = j['registro'];
    return SituacaoDesistencia(
      efeito: EfeitoDesistencia.deTexto(j['efeito']),
      podeDesistir: j['pode_desistir'] == true,
      motivoIndisponivel: _texto(j['motivo_indisponivel']),
      arrependimentoAte: _data(j['arrependimento_ate']),
      pediuExecucaoImediata: j['consentimento_execucao_imediata'] == true,
      registro: registro is Map<String, dynamic> ? RegistroDesistencia.deJson(registro) : null,
    );
  }

  final EfeitoDesistencia efeito;
  final bool podeDesistir;
  final String? motivoIndisponivel;

  /// Fim do prazo de arrependimento.
  final DateTime? arrependimentoAte;

  /// O cliente marcou, no pagamento, que queria o serviço antes do fim dos 7 dias.
  final bool pediuExecucaoImediata;
  final RegistroDesistencia? registro;

  /// Há comprovante para mostrar no lugar do formulário. Se o servidor ainda deixa desistir, o
  /// registro é de outra coisa (recusa anterior, cliente ausente) e o formulário aparece.
  bool get mostraComprovante => registro != null && !podeDesistir;
}
