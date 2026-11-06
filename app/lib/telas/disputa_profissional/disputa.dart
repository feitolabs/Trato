/// Modelos e serviço do lado do profissional na disputa (F6.7): responder e atender retrabalho.
/// Prazos e valores vêm do backend; o app só mostra e envia a resposta. Valores em centavos.
library;

class DetalheDisputa {
  const DetalheDisputa({
    required this.id,
    required this.titulo,
    required this.cliente,
    required this.motivo,
    required this.descricao,
    required this.solucaoPedida,
    required this.prazoRespostaHoras,
    required this.valorCongeladoCentavos,
  });

  final String id;

  /// Ex.: "Vazamento na pia".
  final String titulo;
  final String cliente;
  final String motivo;
  final String descricao;

  /// O que o cliente pediu ("Retrabalho sem custo", "Reembolso parcial"...).
  final String solucaoPedida;
  final int prazoRespostaHoras;
  final int valorCongeladoCentavos;
}

enum TipoRespostaDisputa { atenderRetrabalho, proporReembolsoParcial, discordar }

class RespostaDisputa {
  const RespostaDisputa({
    required this.disputaId,
    required this.tipo,
    required this.mensagem,
    this.reembolsoParcialCentavos,
    this.evidencias = const [],
  });

  final String disputaId;
  final TipoRespostaDisputa tipo;
  final String mensagem;

  /// Só quando [tipo] é reembolso parcial.
  final int? reembolsoParcialCentavos;
  final List<String> evidencias;
}

/// Retrabalho a atender: datas oferecidas ao cliente.
class DadosRetrabalho {
  const DadosRetrabalho({
    required this.disputaId,
    required this.titulo,
    required this.descricaoProblema,
    required this.prazoAtendimentoDias,
    required this.opcoesHorario,
  });

  final String disputaId;
  final String titulo;
  final String descricaoProblema;
  final int prazoAtendimentoDias;

  /// Horários que o backend aceita (já formatados, ex.: "Qui, 05/11 · manhã").
  final List<String> opcoesHorario;
}

class AgendamentoRetrabalho {
  const AgendamentoRetrabalho({required this.disputaId, required this.horario, required this.mensagem});

  final String disputaId;
  final String horario;
  final String mensagem;
}

abstract interface class ServicoDisputaProfissional {
  /// null = não há disputa aberta.
  Future<DetalheDisputa?> carregarDisputa(String disputaId);
  Future<void> responder(RespostaDisputa resposta);

  /// null = não há retrabalho pendente.
  Future<DadosRetrabalho?> carregarRetrabalho(String disputaId);
  Future<void> agendarRetrabalho(AgendamentoRetrabalho agendamento);
}

