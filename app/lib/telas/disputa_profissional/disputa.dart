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

/// PROVISÓRIO — só para teste e demonstração.
class ServicoDisputaProfissionalFake implements ServicoDisputaProfissional {
  ServicoDisputaProfissionalFake({
    this.disputa,
    this.retrabalho,
    this.falharAoCarregar = false,
    this.falharAoEnviar = false,
  });

  final DetalheDisputa? disputa;
  final DadosRetrabalho? retrabalho;
  final bool falharAoCarregar;
  final bool falharAoEnviar;
  final List<RespostaDisputa> respostas = [];
  final List<AgendamentoRetrabalho> agendamentos = [];

  @override
  Future<DetalheDisputa?> carregarDisputa(String disputaId) async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return disputa;
  }

  @override
  Future<void> responder(RespostaDisputa resposta) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    respostas.add(resposta);
  }

  @override
  Future<DadosRetrabalho?> carregarRetrabalho(String disputaId) async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return retrabalho;
  }

  @override
  Future<void> agendarRetrabalho(AgendamentoRetrabalho agendamento) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    agendamentos.add(agendamento);
  }
}

const disputaExemplo = DetalheDisputa(
  id: 'disp-1',
  titulo: 'Vazamento na pia',
  cliente: 'Joana Ribeiro',
  motivo: 'O problema voltou ou não foi resolvido',
  descricao: 'Dois dias depois o vazamento voltou embaixo da pia, no mesmo lugar.',
  solucaoPedida: 'Retrabalho sem custo',
  prazoRespostaHoras: 48,
  valorCongeladoCentavos: 22000,
);

const retrabalhoExemplo = DadosRetrabalho(
  disputaId: 'disp-1',
  titulo: 'Vazamento na pia',
  descricaoProblema: 'O vazamento voltou embaixo da pia, no mesmo lugar.',
  prazoAtendimentoDias: 7,
  opcoesHorario: ['Qui, 05/11 · manhã', 'Qui, 05/11 · tarde', 'Sex, 06/11 · manhã'],
);
