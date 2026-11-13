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
}

/// Contrato com o backend. A tela só pede e mostra.
abstract interface class ServicoMensagens {
  Future<List<ConversaResumo>> listar();
}
