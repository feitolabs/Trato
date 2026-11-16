import 'package:trato/telas/disputa_profissional/disputa.dart';

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
  final List<String> passos = [];

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

  @override
  Future<void> avancarRetrabalho(String disputaId, String etapa) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    passos.add(etapa);
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
