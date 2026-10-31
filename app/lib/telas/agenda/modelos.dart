/// Modelos da aba Agenda do profissional. Só exibição: o backend decide o que está agendado.
library;

enum EstadoAgendamento {
  agendado('Agendado'),
  emAndamento('Em andamento'),
  concluido('Concluído');

  const EstadoAgendamento(this.rotulo);

  final String rotulo;
}

class Agendamento {
  const Agendamento({
    required this.id,
    required this.pedidoId,
    required this.dia,
    required this.horario,
    required this.titulo,
    required this.local,
    this.estado = EstadoAgendamento.agendado,
    this.cliente,
  });

  final String id;
  final String pedidoId;

  /// Dia do atendimento (só a data importa para agrupar).
  final DateTime dia;

  /// Texto pronto: "14h" ou "9h às 12h".
  final String horario;
  final String titulo;

  /// Serviço já contratado: o endereço do atendimento pode aparecer.
  final String local;
  final EstadoAgendamento estado;
  final String? cliente;

  /// Check-in só enquanto o atendimento não terminou.
  bool get podeFazerCheckIn => estado != EstadoAgendamento.concluido;
}
