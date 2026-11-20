import '../../componentes/componentes.dart';
import '../profissional/dinheiro.dart';

/// Modelos simples das telas de pedidos. Só descrevem o que é mostrado:
/// quem decide status, aditivo e dinheiro é o backend.

/// Formata centavos como "R$ 45,00" (só exibição, sem regra de dinheiro).
String formatarReais(int centavos) => Dinheiro.formatar(centavos);

class PedidoResumo {
  const PedidoResumo({
    required this.titulo,
    required this.subtitulo,
    required this.statusTexto,
    required this.statusTipo,
    this.id,
    this.estadoApi,
    this.profissionalNome = '',
  });

  /// Id do pedido na API (nulo nos dados de exemplo).
  final String? id;

  /// Estado do pedido como o backend informa ("em_andamento"...). Quem liga as telas usa isto
  /// para decidir a rota; o texto abaixo é só para exibir.
  final String? estadoApi;

  final String titulo;
  final String subtitulo;
  final String statusTexto;
  final TipoStatus statusTipo;
  final String profissionalNome;
}

/// Oferta de exclusividade de 48h vista pelo cliente no detalhe do pedido.
class OfertaExclusividadeCliente {
  const OfertaExclusividadeCliente({
    required this.id,
    required this.pedidoId,
    required this.status,
    this.profissionalId = '',
    this.profissionalNome,
    this.notaPublica,
    this.responderAte,
    this.expiraEm,
    this.texto = 'Sem compromisso',
    this.outrosOrcamentosContinuamVisiveis = true,
  });

  final String id;
  final String pedidoId;
  final String profissionalId;
  final String? profissionalNome;
  final double? notaPublica;

  /// `aguardando_cliente`, `ativa` ou `recusada`.
  final String status;
  final DateTime? responderAte;
  final DateTime? expiraEm;
  final String texto;
  final bool outrosOrcamentosContinuamVisiveis;

  bool get aguardandoCliente => status == 'aguardando_cliente';
  bool get ativa => status == 'ativa';
  bool get recusada => status == 'recusada';
}

enum EstadoAditivo { aguardando, aprovado, recusado }

class Aditivo {
  const Aditivo({
    required this.titulo,
    required this.valorCentavos,
    required this.descricao,
    this.estado = EstadoAditivo.aguardando,
    this.mostrarFoto = true,
  });

  final String titulo;
  final int valorCentavos;
  final String descricao;
  final EstadoAditivo estado;
  final bool mostrarFoto;

  Aditivo comEstado(EstadoAditivo novo) => Aditivo(
        titulo: titulo,
        valorCentavos: valorCentavos,
        descricao: descricao,
        estado: novo,
        mostrarFoto: mostrarFoto,
      );
}

class ItemResumoAditivo {
  const ItemResumoAditivo({
    required this.id,
    required this.descricao,
    required this.valorCentavos,
    required this.estadoTexto,
    required this.estado,
  });

  final String id;
  final String descricao;
  final int valorCentavos;
  final String estadoTexto;
  final String estado;
}

class ItemResumoNota {
  const ItemResumoNota({
    required this.numero,
    required this.totalCentavos,
    required this.itensResumo,
    required this.enviadaEm,
  });

  final int numero;
  final int totalCentavos;
  final String itensResumo;
  final DateTime enviadaEm;
}

class PedidoEmExecucao {
  const PedidoEmExecucao({
    required this.numero,
    required this.titulo,
    required this.etapas,
    required this.fotos,
    this.aditivo,
    this.aditivos = const [],
    this.notas = const [],
    this.orcamentoCentavos,
    this.totalAtualizadoCentavos,
    this.totalNotasCentavos,
    this.codigoInicio,
    this.codigoConclusao,
    this.podeVerConclusao = true,
    this.pagamentoConfirmado = true,
    this.estadoApi,
  });

  /// Estado atual na API (`pago_e_retido`, `agendado`, ...).
  final String? estadoApi;

  /// O parceiro de pagamento já confirmou? Antes disso o selo diz que aguarda o pagamento.
  final bool pagamentoConfirmado;

  /// Código que o cliente passa ao profissional para encerrar o serviço (check-out). Só aparece
  /// com o serviço em andamento.
  final String? codigoConclusao;

  /// "Ver conclusão" só faz sentido quando o profissional já terminou o serviço. Antes disso o
  /// botão abria "fulano terminou o serviço" com um pedido que nem tinha começado.
  final bool podeVerConclusao;

  /// Código que o cliente passa ao profissional para começar. Só o backend o gera e confere.
  final String? codigoInicio;

  final String numero;
  final String titulo;
  final List<EtapaLinhaDoTempo> etapas;

  /// Rótulos das fotos de check-in ("[Check-in · 14h06]", "[Antes]").
  final List<String> fotos;
  final Aditivo? aditivo;
  final List<ItemResumoAditivo> aditivos;
  final List<ItemResumoNota> notas;
  final int? orcamentoCentavos;
  final int? totalAtualizadoCentavos;
  final int? totalNotasCentavos;
}

enum TipoMensagem { texto, foto, sistema }

/// Proposta de valor/prazo vinda na conversa (`[contraproposta:...]` do cliente ou
/// `[proposta:...]` do profissional).
class ContrapropostaChat {
  const ContrapropostaChat({
    required this.orcamentoId,
    required this.valorCentavos,
    this.prazoExecucaoDias,
    this.ehPropostaDoProfissional = false,
  });

  final String orcamentoId;
  final int valorCentavos;
  final int? prazoExecucaoDias;
  final bool ehPropostaDoProfissional;

  /// Lê `[contraproposta:<orcamento>:<centavos>(:<dias>)?] texto` ou
  /// `[proposta:<orcamento>:<centavos>(:<dias>)?] texto`.
  static (ContrapropostaChat?, String) ler(String texto) {
    final m = RegExp(
      r'^\[(contraproposta|proposta):([^:\]]+):(\d+)(?::(\d+))?\]\s*',
    ).firstMatch(texto);
    if (m == null) return (null, texto);
    final diasStr = m.group(4);
    return (
      ContrapropostaChat(
        orcamentoId: m.group(2)!,
        valorCentavos: int.parse(m.group(3)!),
        prazoExecucaoDias: diasStr == null ? null : int.parse(diasStr),
        ehPropostaDoProfissional: m.group(1) == 'proposta',
      ),
      texto.substring(m.end),
    );
  }
}

/// Sugestão de janela de visita vinda na conversa (`[agenda:<inicio_iso>|<fim_iso>] texto`).
class PropostaAgendaChat {
  const PropostaAgendaChat({
    required this.inicio,
    required this.fim,
  });

  final DateTime inicio;
  final DateTime fim;

  static (PropostaAgendaChat?, String) ler(String texto) {
    final m = RegExp(r'^\[agenda:([^|\]]+)\|([^\]]+)\]\s*').firstMatch(texto);
    if (m == null) return (null, texto);
    final inicio = DateTime.tryParse(m.group(1)!);
    final fim = DateTime.tryParse(m.group(2)!);
    if (inicio == null || fim == null) return (null, texto);
    return (
      PropostaAgendaChat(inicio: inicio.toLocal(), fim: fim.toLocal()),
      texto.substring(m.end),
    );
  }
}

class MensagemChat {
  const MensagemChat({
    required this.tipo,
    required this.hora,
    this.id,
    this.texto,
    this.minha = false,
    this.lida = false,
    this.recebida = false,
    this.contraproposta,
    this.propostaAgenda,
  });

  /// Id da mensagem na API (para aceitar proposta de agenda no chat).
  final int? id;

  /// Preenchida quando a mensagem é uma contraproposta de valor.
  final ContrapropostaChat? contraproposta;

  /// Preenchida quando a mensagem é uma sugestão de dia e horário da visita.
  final PropostaAgendaChat? propostaAgenda;

  /// Chegou ao aparelho de quem recebeu (✓✓ cinza). Mensagem lida conta como recebida.
  final bool recebida;

  final TipoMensagem tipo;
  final String hora;

  /// Texto da mensagem; na foto, o rótulo do espaço da foto.
  final String? texto;
  final bool minha;
  final bool lida;
}

class ConversaPedido {
  const ConversaPedido({
    required this.nome,
    required this.iniciais,
    required this.numeroPedido,
    required this.situacao,
    required this.mensagens,
    required this.respostasRapidas,
    this.usuarioId,
    this.orcamentosAtivos = const {},
    this.pedidoAberto = true,
    this.souCliente = true,
  });

  /// Quem está do outro lado (para buscar a foto de perfil).
  final String? usuarioId;
  final Set<String> orcamentosAtivos;
  final bool pedidoAberto;
  final bool souCliente;
  final String nome;
  final String iniciais;
  final String numeroPedido;
  final String situacao;
  final List<MensagemChat> mensagens;
  final List<String> respostasRapidas;
}
