// Serviço recorrente (`/v1/recorrencias`). O app só pede e mostra: quem pode propor, aceitar,
// pausar ou cobrar é do backend; valores em centavos inteiros.

/// Hora de Brasília (UTC-3, sem horário de verão desde 2019), independente do fuso do aparelho.
DateTime emBrasilia(DateTime momento) => momento.toUtc().subtract(const Duration(hours: 3));

/// "qui, 05/12 · 14:00" no horário de Brasília.
String dataHoraBrasilia(DateTime momento) {
  const dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  final b = emBrasilia(momento);
  String d2(int n) => n.toString().padLeft(2, '0');
  return '${dias[b.weekday - 1]}, ${d2(b.day)}/${d2(b.month)} · ${d2(b.hour)}:${d2(b.minute)}';
}

/// "05/12/2030" no horário de Brasília.
String dataBrasilia(DateTime momento) {
  final b = emBrasilia(momento);
  String d2(int n) => n.toString().padLeft(2, '0');
  return '${d2(b.day)}/${d2(b.month)}/${b.year}';
}

/// Monta o instante (UTC) de um dia e hora escolhidos no relógio de Brasília.
DateTime deBrasilia(int ano, int mes, int dia, int hora, int minuto) =>
    DateTime.utc(ano, mes, dia, hora, minuto).add(const Duration(hours: 3));

enum FrequenciaRecorrencia {
  semanal('semanal', 'Toda semana'),
  quinzenal('quinzenal', 'A cada 15 dias'),
  mensal('mensal', 'Todo mês');

  const FrequenciaRecorrencia(this.codigo, this.rotulo);

  /// Valor enviado à API.
  final String codigo;
  final String rotulo;

  static FrequenciaRecorrencia? deCodigo(String? c) {
    for (final f in values) {
      if (f.codigo == c) return f;
    }
    return null;
  }
}

class VisitaRecorrente {
  const VisitaRecorrente({
    required this.id,
    required this.dataPrevista,
    required this.status,
    this.pedidoId,
  });

  final String id;
  final DateTime dataPrevista;

  /// `agendada`, `confirmada_paga`, `pulada`, `expirada` ou `cancelada`.
  final String status;

  /// Pedido da visita: o cliente aceita o orçamento e paga nele.
  final String? pedidoId;

  bool get agendada => status == 'agendada';

  String get textoStatus {
    switch (status) {
      case 'agendada':
        return 'Agendada';
      case 'confirmada_paga':
        return 'Confirmada e paga';
      case 'pulada':
        return 'Pulada';
      case 'expirada':
        return 'Expirada';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Em análise';
    }
  }

  static VisitaRecorrente? deJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final data = DateTime.tryParse('${j['data_prevista_em'] ?? ''}');
    if (data == null) return null;
    final pedido = j['pedido_id'];
    return VisitaRecorrente(
      id: j['id'] as String,
      dataPrevista: data,
      status: (j['status'] as String?) ?? '',
      pedidoId: pedido is String && pedido.isNotEmpty ? pedido : null,
    );
  }
}

class Recorrencia {
  const Recorrencia({
    required this.id,
    required this.status,
    required this.frequencia,
    required this.valorCentavos,
    required this.proximaVisita,
    required this.meuPapel,
    required this.propostoPorMim,
    required this.pedidoOrigemId,
    this.valorPropostoCentavos,
    this.outraParteNome,
    this.visitas = const [],
  });

  final String id;

  /// `proposta`, `ativa`, `pausada` ou `cancelada`.
  final String status;
  final String frequencia;
  final int valorCentavos;

  /// Reajuste esperando o aceite do cliente (nunca é cobrado antes).
  final int? valorPropostoCentavos;
  final DateTime proximaVisita;

  /// `cliente` ou `profissional`.
  final String meuPapel;
  final bool propostoPorMim;
  final String? outraParteNome;
  final String pedidoOrigemId;
  final List<VisitaRecorrente> visitas;

  bool get souCliente => meuPapel == 'cliente';
  bool get proposta => status == 'proposta';
  bool get ativa => status == 'ativa';
  bool get pausada => status == 'pausada';
  bool get cancelada => status == 'cancelada';
  bool get temReajustePendente => valorPropostoCentavos != null;

  String get textoFrequencia => FrequenciaRecorrencia.deCodigo(frequencia)?.rotulo ?? frequencia;

  /// Status em português simples (a lista e o detalhe).
  String get textoStatus {
    switch (status) {
      case 'proposta':
        return propostoPorMim ? 'Aguardando resposta' : 'Proposta recebida';
      case 'ativa':
        return 'Ativo';
      case 'pausada':
        return 'Pausado';
      case 'cancelada':
        return 'Cancelado';
      default:
        return 'Em análise';
    }
  }

  static Recorrencia? deJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final proxima = DateTime.tryParse('${j['proxima_visita_em'] ?? ''}');
    if (proxima == null) return null;
    int? centavos(Object? v) => v is num ? v.toInt() : null;
    return Recorrencia(
      id: j['id'] as String,
      status: (j['status'] as String?) ?? '',
      frequencia: (j['frequencia'] as String?) ?? '',
      valorCentavos: centavos(j['valor_centavos']) ?? 0,
      valorPropostoCentavos: centavos(j['valor_proposto_centavos']),
      proximaVisita: proxima,
      meuPapel: (j['meu_papel'] as String?) ?? '',
      propostoPorMim: j['proposto_por_mim'] == true,
      outraParteNome: j['outra_parte_nome'] as String?,
      pedidoOrigemId: (j['pedido_origem_id'] as String?) ?? '',
      visitas: [
        for (final v in (j['visitas'] as List? ?? const []))
          if (VisitaRecorrente.deJson(v) case final visita?) visita,
      ],
    );
  }
}

/// Proposta de uma nova série, a partir de um pedido concluído.
typedef PropostaRecorrencia = ({
  FrequenciaRecorrencia frequencia,
  DateTime proximaVisita,
  int? valorCentavos,
});

abstract interface class ServicoRecorrencias {
  /// `GET /v1/recorrencias`.
  Future<List<Recorrencia>> listar();

  /// `GET /v1/recorrencias/{id}` (com as visitas).
  Future<Recorrencia> detalhe(String id);

  /// `POST /v1/recorrencias`. Devolve a série criada (status `proposta`).
  Future<Recorrencia> propor(String pedidoOrigemId, PropostaRecorrencia proposta);

  Future<Recorrencia> aceitar(String id);

  /// Quem recebeu a proposta recusa; quem propôs cancela (rota `cancelar`).
  Future<Recorrencia> recusar(String id);
  Future<Recorrencia> pausar(String id);
  Future<Recorrencia> retomar(String id);
  Future<Recorrencia> cancelar(String id);
  Future<Recorrencia> pularProxima(String id);
  Future<Recorrencia> pularVisita(String id, String visitaId);

  /// Só o profissional propõe novo valor por visita; vale com o aceite do cliente.
  Future<Recorrencia> proporReajuste(String id, int valorCentavos);

  /// O cliente aceita o novo valor: manda o valor que viu ([valorCentavos]). Se o backend mudou
  /// esse valor, responde 409 e a tela recarrega para mostrar o valor novo.
  Future<Recorrencia> aceitarReajuste(String id, int valorCentavos);
  Future<Recorrencia> recusarReajuste(String id);
}
