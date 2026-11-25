/// Uma conversa na lista de Mensagens: uma por pedido e profissional.
/// O chat em si é `ChatPedidoTela` (telas/pedidos/chat_pedido_tela.dart).
class ConversaResumo {
  const ConversaResumo({
    required this.pedidoId,
    required this.tituloPedido,
    required this.interlocutor,
    required this.iniciais,
    required this.ultimaMensagem,
    required this.quando,
    this.naoLidas = 0,
    this.outraParteId,
    this.profissionalId,
    this.conversaId,
    this.codigoPedido,
    this.encerrada = false,
    this.contratado = false,
    this.rotuloEstado,
  });

  /// Id da conversa no backend (para marcar como lida ao sair do chat).
  final String? conversaId;

  final String pedidoId;
  final String tituloPedido;
  final String interlocutor;
  final String iniciais;
  final String ultimaMensagem;

  /// Texto pronto, ex.: "10h20" ou "ontem".
  final String quando;
  final int naoLidas;

  /// Quem está do outro lado (para buscar a foto de perfil).
  final String? outraParteId;

  /// Preenchido só quando QUEM VÊ é o cliente: com qual profissional abrir o chat do pedido.
  final String? profissionalId;

  /// Identificador curto do pedido (ex.: `#FDDA`), derivado de [pedidoId] quando não informado.
  final String? codigoPedido;

  /// Conversa de um serviço já encerrado/finalizado.
  final bool encerrada;

  /// Conversa em que o profissional foi contratado para o pedido.
  final bool contratado;

  /// Rótulo opcional de estado; quando nulo, derivado de [encerrada], [contratado] e [ultimaMensagem].
  final String? rotuloEstado;

  /// A mesma conversa com o rótulo de estado do pedido ("Concluído", "Cancelado"...).
  ConversaResumo comRotuloEstado(String rotulo) => ConversaResumo(
        pedidoId: pedidoId,
        tituloPedido: tituloPedido,
        interlocutor: interlocutor,
        iniciais: iniciais,
        ultimaMensagem: ultimaMensagem,
        quando: quando,
        naoLidas: naoLidas,
        outraParteId: outraParteId,
        profissionalId: profissionalId,
        conversaId: conversaId,
        codigoPedido: codigoPedido,
        encerrada: encerrada,
        contratado: contratado,
        rotuloEstado: rotulo,
      );

  String get codigoEfetivo {
    final informada = codigoPedido?.trim() ?? '';
    if (informada.isNotEmpty) {
      return informada.startsWith('#') ? informada.toUpperCase() : '#${informada.toUpperCase()}';
    }
    final limpo = pedidoId.replaceAll('-', '').trim();
    if (limpo.isEmpty) return '';
    return '#${(limpo.length > 4 ? limpo.substring(0, 4) : limpo).toUpperCase()}';
  }

  String get subtituloComCodigo {
    final cod = codigoEfetivo;
    if (cod.isEmpty || tituloPedido.toUpperCase().contains(cod.toUpperCase())) {
      return tituloPedido;
    }
    return '$tituloPedido · $cod';
  }

  String get estadoEfetivo {
    final informado = rotuloEstado?.trim() ?? '';
    if (informado.isNotEmpty) return informado;
    if (ultimaMensagem.toLowerCase().contains('retrabalho')) return 'Retrabalho';
    if (encerrada) return 'Concluído';
    if (contratado) return 'Em andamento';
    return 'Em negociação';
  }
}

/// Contrato com o backend. A tela só pede e mostra.
abstract interface class ServicoMensagens {
  Future<List<ConversaResumo>> listar();
}
