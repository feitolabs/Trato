import '../../componentes/componentes.dart';

/// Modelos simples das telas de pedidos. Só descrevem o que é mostrado:
/// quem decide status, aditivo e dinheiro é o backend.

/// Formata centavos como "R$ 45,00" (só exibição, sem regra de dinheiro).
String formatarReais(int centavos) {
  final inteiro = centavos ~/ 100;
  final resto = (centavos % 100).toString().padLeft(2, '0');
  final milhares = inteiro.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]}.',
      );
  return 'R\$ $milhares,$resto';
}

class PedidoResumo {
  const PedidoResumo({
    required this.titulo,
    required this.subtitulo,
    required this.statusTexto,
    required this.statusTipo,
    this.id,
    this.estadoApi,
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
}

enum EstadoAditivo { aguardando, aprovado, recusado }

class Aditivo {
  const Aditivo({
    required this.titulo,
    required this.valorCentavos,
    required this.descricao,
    this.estado = EstadoAditivo.aguardando,
  });

  final String titulo;
  final int valorCentavos;
  final String descricao;
  final EstadoAditivo estado;

  Aditivo comEstado(EstadoAditivo novo) =>
      Aditivo(titulo: titulo, valorCentavos: valorCentavos, descricao: descricao, estado: novo);
}

class PedidoEmExecucao {
  const PedidoEmExecucao({
    required this.numero,
    required this.titulo,
    required this.etapas,
    required this.fotos,
    this.aditivo,
    this.codigoInicio,
    this.podeVerConclusao = true,
  });

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
}

enum TipoMensagem { texto, foto, sistema }

/// Proposta de valor menor feita pelo cliente, vinda na conversa (o backend marca o texto).
class ContrapropostaChat {
  const ContrapropostaChat({required this.orcamentoId, required this.valorCentavos});

  final String orcamentoId;
  final int valorCentavos;

  /// Lê `[contraproposta:<orcamento>:<centavos>] texto`. Devolve a proposta e o texto limpo.
  static (ContrapropostaChat?, String) ler(String texto) {
    final m = RegExp(r'^\[contraproposta:([^:\]]+):(\d+)\]\s*').firstMatch(texto);
    if (m == null) return (null, texto);
    return (
      ContrapropostaChat(orcamentoId: m.group(1)!, valorCentavos: int.parse(m.group(2)!)),
      texto.substring(m.end),
    );
  }
}

class MensagemChat {
  const MensagemChat({
    required this.tipo,
    required this.hora,
    this.texto,
    this.minha = false,
    this.lida = false,
    this.recebida = false,
    this.contraproposta,
  });

  /// Preenchida quando a mensagem é uma contraproposta de valor.
  final ContrapropostaChat? contraproposta;

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
  });

  /// Quem está do outro lado (para buscar a foto de perfil).
  final String? usuarioId;
  final String nome;
  final String iniciais;
  final String numeroPedido;
  final String situacao;
  final List<MensagemChat> mensagens;
  final List<String> respostasRapidas;
}
