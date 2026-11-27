/// Exclusividade de 48 h pedida pelo cliente (Termos 13.6). Custo, prazo, saldo, validade dos
/// créditos e devolução vêm do servidor (`/v1/pedidos/{id}/exclusividade-cliente`).
library;

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

int? _inteiro(Object? v) => v is num ? v.toInt() : null;

/// Um crédito de Tratinhos ainda válido, na ordem em que será usado.
class CreditoTratinho {
  const CreditoTratinho({required this.moedas, this.expiraEm});

  final int moedas;
  final DateTime? expiraEm;
}

class ExclusividadeDoCliente {
  const ExclusividadeDoCliente({
    required this.id,
    required this.status,
    this.profissionalId = '',
    this.moedas,
    this.expiraEm,
    this.devolvida = false,
  });

  factory ExclusividadeDoCliente.deJson(Map<String, dynamic> j) => ExclusividadeDoCliente(
        id: '${j['id'] ?? ''}',
        status: '${j['status'] ?? ''}',
        profissionalId: '${j['profissional_id'] ?? ''}',
        moedas: _inteiro(j['moedas']),
        expiraEm: _data(j['expira_em']),
        devolvida: j['devolvida'] == true,
      );

  final String id;

  /// `ativa`, `concluida`, `cancelada` ou `expirada_sem_contratacao`.
  final String status;
  final String profissionalId;
  final int? moedas;
  final DateTime? expiraEm;

  /// Os Tratinhos voltaram (falha do Trato ou desistência do profissional).
  final bool devolvida;

  bool get ativa => status == 'ativa';
}

class SituacaoExclusividadeCliente {
  const SituacaoExclusividadeCliente({
    required this.disponivel,
    this.custo = 0,
    this.duracaoHoras = 0,
    this.saldoLivre = 0,
    this.creditos = const [],
    this.exclusividade,
  });

  factory SituacaoExclusividadeCliente.deJson(Map<String, dynamic> j) {
    final custo = _inteiro(j['custo_moedas']) ?? 0;
    final horas = _inteiro(j['duracao_horas']) ?? 0;
    final ex = j['exclusividade'];
    return SituacaoExclusividadeCliente(
      // Sem o custo ou o prazo do servidor não dá para avisar direito: não se oferece.
      disponivel: j['disponivel'] == true && custo > 0 && horas > 0,
      custo: custo,
      duracaoHoras: horas,
      saldoLivre: _inteiro(j['saldo_livre']) ?? 0,
      creditos: [
        for (final c in (j['creditos'] as List? ?? const []))
          if (c is Map && c['moedas'] is num)
            CreditoTratinho(
              moedas: (c['moedas'] as num).toInt(),
              expiraEm: _data(c['expira_em']),
            ),
      ],
      exclusividade: ex is Map<String, dynamic> ? ExclusividadeDoCliente.deJson(ex) : null,
    );
  }

  final bool disponivel;
  final int custo;
  final int duracaoHoras;
  final int saldoLivre;
  final List<CreditoTratinho> creditos;
  final ExclusividadeDoCliente? exclusividade;
}

/// Quem pode ser escolhido: um orçamento recebido ou o profissional convidado.
class EscolhaExclusividade {
  const EscolhaExclusividade({required this.rotulo, this.orcamentoId, this.profissionalId});

  final String rotulo;
  final String? orcamentoId;
  final String? profissionalId;
}
