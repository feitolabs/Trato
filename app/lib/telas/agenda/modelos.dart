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
    this.remoto = false,
    this.consultaMapa,
    this.semData = false,
    this.estadoApi,
  });

  /// Estado na API (`pago_e_retido`, `agendado`, `em_andamento`). Ausente = o de [estado].
  final String? estadoApi;

  /// Pago, mas o profissional ainda não marcou a data da visita (`pago_e_retido`): sem horário não
  /// há check-in; o próximo passo é marcar a data.
  bool get aguardandoData => estadoApi == 'pago_e_retido';

  /// A visita ainda não foi marcada: o atendimento aparece em "Sem data marcada", não em "Hoje".
  final bool semData;

  /// Serviço remoto: o check-in não pede foto nem localização.
  final bool remoto;

  /// Endereço para abrir no mapa (presencial).
  final String? consultaMapa;

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
  bool get podeFazerCheckIn => estado != EstadoAgendamento.concluido && !aguardandoData;
}
