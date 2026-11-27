/// Modelos e serviço do lado do profissional na disputa (F6.7): responder e atender retrabalho.
/// Prazos e valores vêm do backend; o app só mostra e envia a resposta. Valores em centavos.
library;

import '../disputa_acordo/acordo.dart';

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
    this.estado = 'aberta',
    this.acordo,
  });

  final String id;

  /// `aberta` (esperando o profissional), `em_analise`, `aguardando_aprovacao`, `decidida`
  /// ou `acordo`. Só a `aberta` aceita resposta (quem decide é o servidor).
  final String estado;

  /// Valores do acordo, quando o servidor informar.
  final AcordoDisputa? acordo;

  bool get esperaResposta => estado == 'aberta';

  /// Valor novo do servidor não quebra a tela.
  String get situacaoTexto => switch (estado) {
        'aberta' => 'Aguardando a sua resposta',
        'em_analise' || 'aguardando_aprovacao' => 'Em análise',
        'decidida' => 'Disputa decidida',
        'acordo' => 'Encerrada por acordo',
        _ => 'Em acompanhamento',
      };

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
    this.estado = 'aberto',
  });

  final String disputaId;

  /// Onde o retrabalho está: `aberto`, `aceito` ou `em_execucao` (os dois últimos já passaram
  /// do agendamento e só falta andar um passo).
  final String estado;
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

  /// Anda um passo do retrabalho já aceito: `iniciar` ou `resolver`.
  Future<void> avancarRetrabalho(String disputaId, String etapa);
}

